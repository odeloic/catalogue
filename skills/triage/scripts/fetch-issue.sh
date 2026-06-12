#!/usr/bin/env bash
#
# fetch-issue.sh <input>
#
# Detects source (Linear / GitHub / GitLab) from a URL, bare ID, or the current
# git branch, then fetches the issue and emits a normalized JSON document on
# stdout. Also writes the document to .claude/triage/<id>.json.
#
# Strictly read-only.
#
# Exit codes:
#   0  success — JSON on stdout
#   1  fetch / auth / parse failure (message on stderr)
#   2  Linear detected — script cannot reach MCP. Prints "LINEAR:<id>" on
#      stderr so the agent can take over.
#   3  source could not be determined from input or branch.
#
# Env:
#   FETCH_ISSUE_MODE=fixture  Read from tests/fixtures/<source>/<id>.json
#                             instead of calling gh / glab. For unit tests.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

err() { printf '%s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required command: $1"; exit 1; }
}

# run <label> <cmd...>
# Runs a command, capturing its stderr. On success echoes stdout. On failure,
# prints <label> plus the tool's own stderr (auth error, 404, rate-limit,
# network) and exits 1, so the agent gets a concrete reason instead of a bare
# "command failed" — and can pick an alternative (e.g. retry with -R, switch
# to the MCP path, or report the auth gap).
run() {
  local label="$1"; shift
  local errfile out rc
  errfile="$(mktemp "${TMPDIR:-/tmp}/fetch-issue.XXXXXX")"
  if out="$("$@" 2>"$errfile")"; then
    rm -f "$errfile"
    printf '%s\n' "$out"
    return 0
  else
    rc=$?
  fi
  err "$label (exit $rc)"
  if [[ -s "$errfile" ]]; then
    while IFS= read -r _line; do err "  | $_line"; done <"$errfile"
  fi
  rm -f "$errfile"
  exit 1
}

require_cmd jq

# ---- input parsing ---------------------------------------------------------

INPUT="${1:-}"

if [[ -z "$INPUT" ]]; then
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -z "$branch" ]]; then
    err "no input provided and not inside a git repo"
    exit 3
  fi
  # Prefer Linear-style team prefix, then a bare number.
  if [[ "$branch" =~ ([A-Za-z]+-[0-9]+) ]]; then
    INPUT="${BASH_REMATCH[1]}"
  elif [[ "$branch" =~ ([0-9]+) ]]; then
    INPUT="${BASH_REMATCH[1]}"
  else
    err "could not infer issue id from branch: $branch"
    exit 3
  fi
fi

detect_source() {
  local in="$1"
  if [[ "$in" == *linear.app* ]]; then
    echo linear; return
  fi
  if [[ "$in" == *github.com* ]]; then
    echo github; return
  fi
  if [[ "$in" == *gitlab.com* ]] || [[ "$in" == */-/issues/* ]]; then
    echo gitlab; return
  fi
  # Linear team-prefix anywhere in the input (covers bare ENG-123 and
  # branch-name inputs like `user/eng-123-do-thing`).
  if [[ "$in" =~ [A-Za-z]+-[0-9]+ ]]; then
    echo linear; return
  fi
  if [[ "$in" =~ ^#?[0-9]+$ ]]; then
    local remote
    remote="$(git remote get-url origin 2>/dev/null || true)"
    if [[ "$remote" == *github* ]]; then echo github; return; fi
    if [[ "$remote" == *gitlab* ]]; then echo gitlab; return; fi
  fi
  return 1
}

extract_id() {
  local in="$1" src="$2"
  case "$src" in
    linear)
      if [[ "$in" =~ ([A-Za-z]+-[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'
      else
        return 1
      fi
      ;;
    github|gitlab)
      if [[ "$in" =~ /issues/([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
      elif [[ "$in" =~ ^#?([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
      else
        return 1
      fi
      ;;
  esac
}

# For GitHub/GitLab URLs, pull owner/repo so we can pass `-R` and don't depend
# on the cwd being inside the target repo.
extract_repo() {
  local in="$1" src="$2"
  case "$src" in
    github)
      if [[ "$in" =~ github\.com[:/]+([^/]+)/([^/]+) ]]; then
        printf '%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
      fi
      ;;
    gitlab)
      if [[ "$in" =~ gitlab\.com[:/]+(.+)/-/issues/ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
      fi
      ;;
  esac
}

SOURCE="$(detect_source "$INPUT" || true)"
if [[ -z "${SOURCE:-}" ]]; then
  err "could not determine source (Linear / GitHub / GitLab) from: $INPUT"
  exit 3
fi

ID="$(extract_id "$INPUT" "$SOURCE")"
if [[ -z "${ID:-}" ]]; then
  err "could not extract issue id from: $INPUT"
  exit 3
fi

REPO="$(extract_repo "$INPUT" "$SOURCE" || true)"

# ---- output destination ----------------------------------------------------

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_DIR="$REPO_ROOT/.claude/triage"
mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/$ID.json"

write_out() {
  local json="$1"
  printf '%s\n' "$json" | tee "$OUT_FILE"
}

# ---- fixture mode ----------------------------------------------------------

if [[ "${FETCH_ISSUE_MODE:-}" == "fixture" ]]; then
  fix="$SKILL_DIR/tests/fixtures/$SOURCE/$ID.json"
  if [[ ! -f "$fix" ]]; then
    err "fixture not found: $fix"
    exit 1
  fi
  write_out "$(cat "$fix")"
  exit 0
fi

# ---- Linear: hand off to the agent -----------------------------------------

if [[ "$SOURCE" == "linear" ]]; then
  err "LINEAR:$ID"
  exit 2
fi

# ---- GitHub ----------------------------------------------------------------

fetch_github() {
  require_cmd gh
  if ! gh auth status >/dev/null 2>&1; then
    err "GitHub auth missing. Run: gh auth login"
    exit 1
  fi

  local issue comments_raw prs comments_total comments_kept
  local -a gh_args=()
  if [[ -n "${REPO:-}" ]]; then gh_args=(-R "$REPO"); fi

  issue="$(run "gh issue view failed for issue $ID" \
    gh issue view "$ID" ${gh_args[@]+"${gh_args[@]}"} --json number,title,author,assignees,state,labels,body,url,createdAt,updatedAt,closedAt)"
  comments_raw="$(run "gh issue view --json comments failed for issue $ID" \
    gh issue view "$ID" ${gh_args[@]+"${gh_args[@]}"} --json comments)"
  prs="$(gh pr list ${gh_args[@]+"${gh_args[@]}"} --search "$ID in:title,body" --state all --json number,title,url,state,author,isDraft --limit 20 2>/dev/null || echo '[]')"

  comments_total="$(jq '.comments | length' <<<"$comments_raw")"
  if [[ "$comments_total" -gt 100 ]]; then
    comments_kept="$(jq '.comments | (.[0:5] + .[-10:])' <<<"$comments_raw")"
  else
    comments_kept="$(jq '.comments' <<<"$comments_raw")"
  fi

  jq -n \
    --argjson issue "$issue" \
    --argjson comments "$comments_kept" \
    --argjson prs "$prs" \
    --argjson total "$comments_total" \
    '{
      source: "github",
      id: ($issue.number|tostring),
      url: $issue.url,
      title: $issue.title,
      author: ($issue.author.login // null),
      assignee: ($issue.assignees[0].login // null),
      status: ($issue.state | ascii_downcase),
      labels: [$issue.labels[].name],
      issue_type: null,
      description: ($issue.body // ""),
      acceptance_criteria: [],
      comments: [$comments[] | {author: (.author.login // "unknown"), at: .createdAt, body: .body}],
      comments_total: $total,
      related: [],
      prior_attempts: [$prs[] | {
        type: "pr",
        url: .url,
        title: .title,
        state: (if .isDraft then "draft" else (.state | ascii_downcase) end),
        author: (.author.login // null)
      }],
      classification: null
    }'
}

# ---- GitLab ----------------------------------------------------------------

fetch_gitlab() {
  require_cmd glab
  if ! glab auth status >/dev/null 2>&1; then
    err "GitLab auth missing. Run: glab auth login"
    exit 1
  fi

  local issue mrs comments_total
  local -a glab_args=()
  if [[ -n "${REPO:-}" ]]; then glab_args=(-R "$REPO"); fi

  issue="$(run "glab issue view failed for issue $ID" \
    glab issue view "$ID" ${glab_args[@]+"${glab_args[@]}"} -F json)"
  mrs="$(glab mr list ${glab_args[@]+"${glab_args[@]}"} --search "$ID" -F json 2>/dev/null || echo '[]')"

  comments_total="$(jq '(.discussions // .notes // []) | length' <<<"$issue" 2>/dev/null || echo 0)"

  jq -n \
    --argjson issue "$issue" \
    --argjson mrs "$mrs" \
    --argjson total "$comments_total" \
    '{
      source: "gitlab",
      id: (($issue.iid // $issue.id) | tostring),
      url: ($issue.web_url // ""),
      title: $issue.title,
      author: ($issue.author.username // null),
      assignee: ($issue.assignee.username // ($issue.assignees[0].username // null)),
      status: ($issue.state // "unknown"),
      labels: ($issue.labels // []),
      issue_type: ($issue.issue_type // null),
      description: ($issue.description // ""),
      acceptance_criteria: [],
      comments: [],
      comments_total: $total,
      related: [],
      prior_attempts: [$mrs[] | {
        type: "mr",
        url: (.web_url // ""),
        title: .title,
        state: ((.state // "unknown") | ascii_downcase),
        author: (.author.username // null)
      }],
      classification: null
    }'
}

# ---- dispatch --------------------------------------------------------------

# Capture the result in its own step. Folding the fetch into
# `write_out "$(fetch_github)"` would discard the function's exit status — a
# failed fetch would still write an empty document and exit 0, leaving the
# agent with silent garbage. Assign first so `set -e` propagates the failure.
case "$SOURCE" in
  github) RESULT="$(fetch_github)" ;;
  gitlab) RESULT="$(fetch_gitlab)" ;;
  *) err "unsupported source: $SOURCE"; exit 1 ;;
esac
write_out "$RESULT"
