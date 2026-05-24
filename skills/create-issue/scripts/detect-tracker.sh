#!/usr/bin/env bash
#
# detect-tracker.sh
#
# Inspects the current repo to figure out which issue tracker is in play.
# Read-only. Emits a JSON document to stdout describing the decision.
#
# Inspection sources:
#   - `git remote get-url origin` and `upstream`
#   - presence of `.github/` and `.gitlab/` directories
#   - recent commit messages (last 20) for Linear-style team prefixes
#   - current branch name for the same
#
# Output shape:
#   {
#     "primary_tracker": "github|gitlab|linear|unknown",
#     "evidence": ["remote.origin.url=..."],
#     "secondary_signals": [{"tracker": "linear", "reason": "..."}],
#     "repo_identifier": "owner/repo" | null,
#     "confidence": "high|medium|low"
#   }
#
# `primary_tracker: unknown` means the caller should ask the user.
#
# Exit code: always 0. Use the JSON to communicate.
#
# Env:
#   DETECT_TRACKER_FIXTURE_REMOTE=<url>   Overrides the real `origin` remote
#                                         lookup. For unit tests.

set -euo pipefail

err() { printf '%s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required command: $1"; exit 1; }
}

require_cmd jq

# ---- gather raw signals ----------------------------------------------------

origin_url=""
upstream_url=""

if [[ -n "${DETECT_TRACKER_FIXTURE_REMOTE+set}" ]]; then
  # Fixture mode is active when the env var is set, even if its value is
  # empty. This lets tests assert behavior on missing remotes.
  origin_url="$DETECT_TRACKER_FIXTURE_REMOTE"
else
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  upstream_url="$(git remote get-url upstream 2>/dev/null || true)"
fi

repo_root=""
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

has_github_dir=0
has_gitlab_dir=0
if [[ -n "$repo_root" ]]; then
  [[ -d "$repo_root/.github" ]] && has_github_dir=1
  [[ -d "$repo_root/.gitlab" ]] && has_gitlab_dir=1
fi

recent_log=""
branch=""
if [[ -z "${DETECT_TRACKER_FIXTURE_REMOTE+set}" ]]; then
  recent_log="$(git log -n 20 --pretty=%s 2>/dev/null || true)"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi

# ---- classify --------------------------------------------------------------

evidence=()
secondary=()

host_from_url() {
  local url="$1"
  if [[ "$url" =~ github\.com ]]; then echo github; return; fi
  if [[ "$url" =~ gitlab\.com ]] || [[ "$url" =~ gitlab\. ]]; then echo gitlab; return; fi
  echo ""
}

repo_id_from_url() {
  local url="$1"
  if [[ "$url" =~ github\.com[:/]+([^/]+)/([^/]+) ]]; then
    printf '%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
    return
  fi
  if [[ "$url" =~ gitlab\.com[:/]+(.+?)(\.git)?$ ]]; then
    printf '%s' "${BASH_REMATCH[1]%.git}"
    return
  fi
  echo ""
}

primary=""
repo_identifier=""

origin_host="$(host_from_url "$origin_url")"
upstream_host="$(host_from_url "$upstream_url")"

if [[ -n "$origin_host" ]]; then
  primary="$origin_host"
  evidence+=("remote.origin.url=$origin_url")
  repo_identifier="$(repo_id_from_url "$origin_url")"
elif [[ -n "$upstream_host" ]]; then
  primary="$upstream_host"
  evidence+=("remote.upstream.url=$upstream_url")
  repo_identifier="$(repo_id_from_url "$upstream_url")"
fi

if [[ "$has_github_dir" -eq 1 ]]; then
  if [[ "$primary" == "github" ]]; then
    evidence+=(".github/ directory present")
  else
    secondary+=("github:.github/ directory present")
  fi
fi
if [[ "$has_gitlab_dir" -eq 1 ]]; then
  if [[ "$primary" == "gitlab" ]]; then
    evidence+=(".gitlab/ directory present")
  else
    secondary+=("gitlab:.gitlab/ directory present")
  fi
fi

# Linear-style team prefix in branch or commit messages.
linear_branch_hit=""
if [[ "$branch" =~ ([A-Z]+-[0-9]+) ]]; then
  linear_branch_hit="${BASH_REMATCH[1]}"
elif [[ "$branch" =~ ([a-zA-Z]+-[0-9]+) ]]; then
  linear_branch_hit="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')"
fi

linear_commit_hit=""
if [[ -n "$recent_log" ]]; then
  linear_commit_hit="$(printf '%s\n' "$recent_log" | grep -oE '[A-Z]+-[0-9]+' | head -1 || true)"
fi

if [[ -n "$linear_branch_hit" ]]; then
  secondary+=("linear:branch name references $linear_branch_hit")
fi
if [[ -n "$linear_commit_hit" ]]; then
  secondary+=("linear:recent commit references $linear_commit_hit")
fi

# Confidence:
#   high   = primary set via remote URL host
#   medium = primary set only via directory presence
#   low    = no primary
confidence="low"
if [[ -n "$primary" ]]; then
  if [[ -n "$origin_host" || -n "$upstream_host" ]]; then
    confidence="high"
  else
    confidence="medium"
  fi
fi

if [[ -z "$primary" ]]; then
  # No remote and no dir signal. If we have Linear hints, surface as primary.
  if [[ -n "$linear_branch_hit" || -n "$linear_commit_hit" ]]; then
    primary="linear"
    confidence="low"
    if [[ -n "$linear_branch_hit" ]]; then evidence+=("branch=$branch references $linear_branch_hit"); fi
    if [[ -n "$linear_commit_hit" ]]; then evidence+=("commit references $linear_commit_hit"); fi
    # Drop them from secondary since they became primary evidence.
    secondary=()
  else
    primary="unknown"
  fi
fi

# ---- emit JSON -------------------------------------------------------------

ev_json="$(printf '%s\n' "${evidence[@]:-}" | jq -R . | jq -s 'map(select(length>0))')"
sec_json="$(printf '%s\n' "${secondary[@]:-}" \
  | jq -R 'select(length>0) | split(":") | {tracker: .[0], reason: (.[1:] | join(":"))}' \
  | jq -s '.')"

jq -n \
  --arg primary "$primary" \
  --argjson evidence "$ev_json" \
  --argjson secondary "$sec_json" \
  --arg repo "$repo_identifier" \
  --arg confidence "$confidence" \
  '{
    primary_tracker: $primary,
    evidence: $evidence,
    secondary_signals: $secondary,
    repo_identifier: (if $repo == "" then null else $repo end),
    confidence: $confidence
  }'
