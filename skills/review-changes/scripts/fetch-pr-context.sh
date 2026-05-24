#!/usr/bin/env bash
#
# fetch-pr-context.sh <input>
#
# Detects source (GitHub / GitLab / local branch) from a URL or branch name,
# fetches PR/MR metadata + diff + CI + linked issues, and emits a normalized
# JSON document on stdout. Also writes the document to
# .claude/reviews/<id>.context.json.
#
# Strictly read-only: never approves, comments, or modifies the PR/MR.
#
# Exit codes:
#   0  success — JSON on stdout
#   1  fetch / auth / parse failure (message on stderr)
#   3  source could not be determined from input or branch
#
# Env:
#   FETCH_PR_MODE=fixture  Read from tests/fixtures/<source>/<id>.json
#                          instead of calling gh / glab / git. For unit tests.
#   REVIEW_BASE_REF        Override the base ref for local-branch diff
#                          (default: origin/HEAD, then main, then master).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

err() { printf '%s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required command: $1"; exit 1; }
}

require_cmd jq

INPUT="${1:-}"

if [[ -z "$INPUT" ]]; then
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    err "no input provided and could not determine current branch"
    exit 3
  fi
  INPUT="$branch"
fi

detect_source() {
  local in="$1"
  if [[ "$in" == *github.com* ]] && [[ "$in" == */pull/* ]]; then
    echo github; return
  fi
  if [[ "$in" == *gitlab.com* ]] || [[ "$in" == */-/merge_requests/* ]]; then
    echo gitlab; return
  fi
  if [[ "$in" == *github.com* ]]; then
    echo github; return
  fi
  if [[ "$in" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo local; return
  fi
  return 1
}

extract_id() {
  local in="$1" src="$2"
  case "$src" in
    github)
      if [[ "$in" =~ /pull/([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
      else
        return 1
      fi
      ;;
    gitlab)
      if [[ "$in" =~ /merge_requests/([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
      else
        return 1
      fi
      ;;
    local)
      echo "$in" | tr '/' '_'
      ;;
  esac
}

extract_repo() {
  local in="$1" src="$2"
  case "$src" in
    github)
      if [[ "$in" =~ github\.com[:/]+([^/]+)/([^/]+) ]]; then
        printf '%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
      fi
      ;;
    gitlab)
      if [[ "$in" =~ gitlab\.com[:/]+(.+)/-/merge_requests/ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
      fi
      ;;
  esac
}

SOURCE="$(detect_source "$INPUT" || true)"
if [[ -z "${SOURCE:-}" ]]; then
  err "could not determine source (GitHub / GitLab / local) from: $INPUT"
  exit 3
fi

ID="$(extract_id "$INPUT" "$SOURCE")"
if [[ -z "${ID:-}" ]]; then
  err "could not extract PR/MR id from: $INPUT"
  exit 3
fi

REPO="$(extract_repo "$INPUT" "$SOURCE" || true)"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_DIR="$REPO_ROOT/.claude/reviews"
mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/$ID.context.json"

# size_class thresholds per spec:
#   small:  <=100 added,  <=5 files
#   medium: <=300 added,  <=10 files
#   large:  <=500 added,  <=20 files
#   xlarge: anything beyond
classify_size() {
  local added="$1" files="$2"
  if [[ "$added" -le 100 && "$files" -le 5 ]]; then
    echo small
  elif [[ "$added" -le 300 && "$files" -le 10 ]]; then
    echo medium
  elif [[ "$added" -le 500 && "$files" -le 20 ]]; then
    echo large
  else
    echo xlarge
  fi
}

emit() {
  local json="$1"
  printf '%s\n' "$json" | tee "$OUT_FILE"
}

# ---- fixture mode ----------------------------------------------------------

if [[ "${FETCH_PR_MODE:-}" == "fixture" ]]; then
  fix="$SKILL_DIR/tests/fixtures/$SOURCE/$ID.json"
  if [[ ! -f "$fix" ]]; then
    err "fixture not found: $fix"
    exit 1
  fi
  # Re-classify size_class in case the fixture's metrics disagree with the
  # current thresholds — keeps fixtures stable when thresholds shift.
  raw="$(cat "$fix")"
  added="$(jq -r '.size_metrics.lines_added // 0' <<<"$raw")"
  files="$(jq -r '.size_metrics.files_count // 0' <<<"$raw")"
  size_class="$(classify_size "$added" "$files")"
  emit "$(jq --arg sc "$size_class" '.size_metrics.size_class = $sc' <<<"$raw")"
  exit 0
fi

# ---- GitHub ----------------------------------------------------------------

fetch_github() {
  require_cmd gh
  if ! gh auth status >/dev/null 2>&1; then
    err "GitHub auth missing. Run: gh auth login"
    exit 1
  fi

  local -a gh_args=()
  if [[ -n "${REPO:-}" ]]; then gh_args=(-R "$REPO"); fi

  local pr diff checks linked
  pr="$(gh pr view "$ID" "${gh_args[@]}" --json number,title,url,author,isDraft,state,baseRefName,baseRefOid,headRefName,headRefOid,files,additions,deletions,body)" || {
    err "gh pr view failed for $ID"; exit 1;
  }
  diff="$(gh pr diff "$ID" "${gh_args[@]}" 2>/dev/null || echo "")"
  checks="$(gh pr checks "$ID" "${gh_args[@]}" --json name,state,link 2>/dev/null || echo '[]')"
  linked="$(gh pr view "$ID" "${gh_args[@]}" --json closingIssuesReferences 2>/dev/null || echo '{"closingIssuesReferences":[]}')"

  local added removed files_count size_class
  added="$(jq -r '.additions // 0' <<<"$pr")"
  removed="$(jq -r '.deletions // 0' <<<"$pr")"
  files_count="$(jq -r '.files | length' <<<"$pr")"
  size_class="$(classify_size "$added" "$files_count")"

  jq -n \
    --argjson pr "$pr" \
    --arg diff "$diff" \
    --argjson checks "$checks" \
    --argjson linked "$linked" \
    --arg id "$ID" \
    --argjson added "$added" \
    --argjson removed "$removed" \
    --argjson files_count "$files_count" \
    --arg size_class "$size_class" \
    '{
      source: "github",
      id: $id,
      url: $pr.url,
      title: $pr.title,
      author: ($pr.author.login // null),
      is_draft: ($pr.isDraft // false),
      base: { ref: $pr.baseRefName, sha: $pr.baseRefOid },
      head: { ref: $pr.headRefName, sha: $pr.headRefOid },
      diff: $diff,
      files_changed: [$pr.files[]? | {
        path: .path,
        added: (.additions // 0),
        removed: (.deletions // 0),
        status: "modified"
      }],
      linked_issues: [($linked.closingIssuesReferences // [])[] | {
        id: (.number | tostring),
        source: "github",
        url: ("https://github.com/" + .repository.nameWithOwner + "/issues/" + (.number|tostring))
      }],
      ci: (
        ($checks // []) as $c
        | {
            status: (
              if ($c | length) == 0 then "none"
              elif any($c[]; (.state // "") | ascii_downcase == "failure") then "failure"
              elif any($c[]; (.state // "") | ascii_downcase | . == "pending" or . == "in_progress" or . == "queued") then "pending"
              elif all($c[]; (.state // "") | ascii_downcase | . == "success" or . == "neutral" or . == "skipped") then "success"
              else "pending"
              end
            ),
            checks: [$c[] | {name: .name, status: ((.state // "") | ascii_downcase), url: (.link // "")}],
            failures: [$c[] | select((.state // "") | ascii_downcase == "failure") | .name]
          }
      ),
      size_metrics: {
        lines_added: $added,
        lines_removed: $removed,
        files_count: $files_count,
        size_class: $size_class
      },
      depends_on: [
        ($pr.body // "")
        | scan("(?:[Dd]epends on|[Bb]locked by)[ :]+(#[0-9]+|https?://[^ \\n]+)")
        | .[0]
      ]
    }'
}

# ---- GitLab ----------------------------------------------------------------

fetch_gitlab() {
  require_cmd glab
  if ! glab auth status >/dev/null 2>&1; then
    err "GitLab auth missing. Run: glab auth login"
    exit 1
  fi

  local -a glab_args=()
  if [[ -n "${REPO:-}" ]]; then glab_args=(-R "$REPO"); fi

  local mr diff ci_raw
  mr="$(glab mr view "$ID" "${glab_args[@]}" -F json)" || {
    err "glab mr view failed for $ID"; exit 1;
  }
  diff="$(glab mr diff "$ID" "${glab_args[@]}" 2>/dev/null || echo "")"
  ci_raw="$(glab ci status --mr "$ID" "${glab_args[@]}" -F json 2>/dev/null || echo '[]')"

  local added removed files_count size_class
  added="$(jq -r '([.changes[]?.diff // ""] | join("\n") | [splits("\n") | select(startswith("+") and (startswith("+++") | not))] | length)' <<<"$mr" 2>/dev/null || echo 0)"
  removed="$(jq -r '([.changes[]?.diff // ""] | join("\n") | [splits("\n") | select(startswith("-") and (startswith("---") | not))] | length)' <<<"$mr" 2>/dev/null || echo 0)"
  files_count="$(jq -r '(.changes // []) | length' <<<"$mr")"
  size_class="$(classify_size "$added" "$files_count")"

  jq -n \
    --argjson mr "$mr" \
    --arg diff "$diff" \
    --argjson ci "$ci_raw" \
    --arg id "$ID" \
    --argjson added "$added" \
    --argjson removed "$removed" \
    --argjson files_count "$files_count" \
    --arg size_class "$size_class" \
    '{
      source: "gitlab",
      id: $id,
      url: ($mr.web_url // ""),
      title: $mr.title,
      author: ($mr.author.username // null),
      is_draft: (($mr.draft // $mr.work_in_progress // false)),
      base: { ref: ($mr.target_branch // ""), sha: ($mr.diff_refs.base_sha // "") },
      head: { ref: ($mr.source_branch // ""), sha: ($mr.diff_refs.head_sha // "") },
      diff: $diff,
      files_changed: [($mr.changes // [])[] | {
        path: (.new_path // .old_path),
        added: 0,
        removed: 0,
        status: (if .new_file then "added" elif .deleted_file then "deleted" elif .renamed_file then "renamed" else "modified" end)
      }],
      linked_issues: [
        ($mr.description // "")
        | scan("(?:[Cc]loses|[Ff]ixes|[Rr]esolves|[Rr]elates to)[ :]+#([0-9]+)")
        | { id: .[0], source: "gitlab", url: "" }
      ],
      ci: (
        ($ci // []) as $c
        | {
            status: (
              if ($c | length) == 0 then "none"
              elif any($c[]; (.status // "") | ascii_downcase == "failed") then "failure"
              elif any($c[]; (.status // "") | ascii_downcase | . == "pending" or . == "running" or . == "created") then "pending"
              elif all($c[]; (.status // "") | ascii_downcase | . == "success" or . == "manual" or . == "skipped") then "success"
              else "pending"
              end
            ),
            checks: [$c[] | {name: (.name // ""), status: ((.status // "") | ascii_downcase), url: (.web_url // "")}],
            failures: [$c[] | select((.status // "") | ascii_downcase == "failed") | (.name // "")]
          }
      ),
      size_metrics: {
        lines_added: $added,
        lines_removed: $removed,
        files_count: $files_count,
        size_class: $size_class
      },
      depends_on: [
        ($mr.description // "")
        | scan("(?:[Dd]epends on|[Bb]locked by)[ :]+(![0-9]+|https?://[^ \\n]+)")
        | .[0]
      ]
    }'
}

# ---- Local branch ----------------------------------------------------------

fetch_local() {
  require_cmd git
  local branch="$INPUT"
  if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
    err "branch not found: $branch"
    exit 1
  fi

  local base="${REVIEW_BASE_REF:-}"
  if [[ -z "$base" ]]; then
    if git rev-parse --verify "origin/HEAD" >/dev/null 2>&1; then
      base="$(git rev-parse --abbrev-ref origin/HEAD)"
    elif git rev-parse --verify main >/dev/null 2>&1; then
      base="main"
    elif git rev-parse --verify master >/dev/null 2>&1; then
      base="master"
    else
      err "could not determine base ref; set REVIEW_BASE_REF"
      exit 1
    fi
  fi

  local base_sha head_sha diff numstat title author
  base_sha="$(git rev-parse "$base" 2>/dev/null || echo "")"
  head_sha="$(git rev-parse "$branch" 2>/dev/null || echo "")"
  diff="$(git diff "$base"..."$branch" 2>/dev/null || echo "")"
  numstat="$(git diff --numstat "$base"..."$branch" 2>/dev/null || echo "")"
  title="$(git log -1 --pretty=%s "$branch" 2>/dev/null || echo "")"
  author="$(git log -1 --pretty=%an "$branch" 2>/dev/null || echo "")"

  local added removed files_count size_class
  added=0; removed=0; files_count=0
  if [[ -n "$numstat" ]]; then
    while IFS=$'\t' read -r a r _; do
      [[ "$a" == "-" ]] && a=0
      [[ "$r" == "-" ]] && r=0
      added=$((added + a))
      removed=$((removed + r))
      files_count=$((files_count + 1))
    done <<<"$numstat"
  fi
  size_class="$(classify_size "$added" "$files_count")"

  local files_json
  files_json="$(awk -F'\t' 'NF==3 {
    a=$1; r=$2;
    if (a=="-") a=0;
    if (r=="-") r=0;
    printf "{\"path\":\"%s\",\"added\":%s,\"removed\":%s,\"status\":\"modified\"}\n", $3, a, r
  }' <<<"$numstat" | jq -s '.')"
  [[ -z "$files_json" || "$files_json" == "null" ]] && files_json='[]'

  local commit_log
  commit_log="$(git log --pretty=%B "$base"..."$branch" 2>/dev/null || echo "")"

  jq -n \
    --arg id "$ID" \
    --arg title "$title" \
    --arg author "$author" \
    --arg base "$base" \
    --arg base_sha "$base_sha" \
    --arg head "$branch" \
    --arg head_sha "$head_sha" \
    --arg diff "$diff" \
    --argjson files "$files_json" \
    --argjson added "$added" \
    --argjson removed "$removed" \
    --argjson files_count "$files_count" \
    --arg size_class "$size_class" \
    --arg log "$commit_log" \
    '{
      source: "local",
      id: $id,
      url: "",
      title: $title,
      author: $author,
      is_draft: false,
      base: { ref: $base, sha: $base_sha },
      head: { ref: $head, sha: $head_sha },
      diff: $diff,
      files_changed: $files,
      linked_issues: [
        ($log + " " + $head)
        | [scan("([A-Z][A-Z0-9]+-[0-9]+)")[0]] as $linear
        | [scan("#([0-9]+)")[0]] as $gh
        | (
            ($linear | map({id: ., source: "linear", url: ""}))
            + ($gh | map({id: ., source: "github", url: ""}))
          )
        | unique_by(.id)
        | .[]
      ],
      ci: { status: "none", checks: [], failures: [] },
      size_metrics: {
        lines_added: $added,
        lines_removed: $removed,
        files_count: $files_count,
        size_class: $size_class
      },
      depends_on: [
        $log
        | scan("(?:[Dd]epends on|[Bb]locked by)[ :]+(#[0-9]+|[A-Z][A-Z0-9]+-[0-9]+|https?://[^ \\n]+)")
        | .[0]
      ]
    }'
}

# ---- dispatch --------------------------------------------------------------

case "$SOURCE" in
  github) emit "$(fetch_github)" ;;
  gitlab) emit "$(fetch_gitlab)" ;;
  local)  emit "$(fetch_local)" ;;
  *) err "unsupported source: $SOURCE"; exit 1 ;;
esac
