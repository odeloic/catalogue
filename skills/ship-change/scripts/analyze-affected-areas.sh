#!/usr/bin/env bash
#
# analyze-affected-areas.sh <keyword1> [keyword2 ...]
#
# Searches the repo for the given keywords, groups hits by directory, and
# returns JSON to stdout describing the top directories.
#
# Strictly read-only. Respects .gitignore and excludes common build / vendor
# directories.
#
# Search backend:
#   Prefers `rg` (ripgrep). Falls back to `grep -r` with hardcoded excludes if
#   rg is not installed.
#
# Output JSON:
#   {
#     "keywords": [...],
#     "matches": [
#       { "directory": "<dir>",
#         "files": [{"path": "...", "hits": N}, ...],
#         "total_hits": N }
#     ],
#     "top_directories": ["...", ...],
#     "exclusions_applied": [...]
#   }
#
# Exit codes:
#   0  success — JSON on stdout (even if zero matches)
#   1  missing dependency or invocation error
#   2  no keywords provided
#
# Env:
#   AFFECTED_TOP_N            Number of top directories to return (default 10).
#   AFFECTED_REPO_ROOT        Override repo root (default: git toplevel, or cwd).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

err() { printf '%s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required command: $1"; exit 1; }
}

require_cmd jq

if [[ $# -lt 1 ]]; then
  err "usage: analyze-affected-areas.sh <keyword1> [keyword2 ...]"
  exit 2
fi

KEYWORDS=("$@")
TOP_N="${AFFECTED_TOP_N:-10}"

if [[ -n "${AFFECTED_REPO_ROOT:-}" ]]; then
  REPO_ROOT="$AFFECTED_REPO_ROOT"
else
  REPO_ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

EXCLUDES=(node_modules dist build .next .nuxt .git vendor vendored target out coverage .venv venv __pycache__ .turbo .cache)

# Build a single alternation regex so we do one pass over the repo. We escape
# regex metacharacters in each keyword so callers can pass plain strings.
escape_regex() {
  printf '%s' "$1" | sed -e 's/[]\/$*.^[]/\\&/g'
}

pattern=""
for kw in "${KEYWORDS[@]}"; do
  esc="$(escape_regex "$kw")"
  if [[ -z "$pattern" ]]; then
    pattern="$esc"
  else
    pattern="$pattern|$esc"
  fi
done

raw=""
if command -v rg >/dev/null 2>&1; then
  rg_args=(--no-heading --count-matches --no-messages)
  for ex in "${EXCLUDES[@]}"; do
    rg_args+=(--glob "!$ex" --glob "!**/$ex/**")
  done
  raw="$(rg "${rg_args[@]}" -e "$pattern" "$REPO_ROOT" 2>/dev/null || true)"
else
  grep_excludes=()
  for ex in "${EXCLUDES[@]}"; do
    grep_excludes+=(--exclude-dir="$ex")
  done
  # grep -c reports zero-hit files too, filter those out below.
  raw="$(grep -r -E -I -c "${grep_excludes[@]}" -e "$pattern" "$REPO_ROOT" 2>/dev/null || true)"
  raw="$(printf '%s\n' "$raw" | awk -F: '$NF > 0')"
fi

keywords_json="$(printf '%s\n' "${KEYWORDS[@]}" | jq -R . | jq -s .)"
exclusions_json="$(printf '%s\n' "${EXCLUDES[@]}" | jq -R . | jq -s .)"

if [[ -z "$raw" ]]; then
  jq -n \
    --argjson keywords "$keywords_json" \
    --argjson exclusions "$exclusions_json" \
    '{
      keywords: $keywords,
      matches: [],
      top_directories: [],
      exclusions_applied: $exclusions
    }'
  exit 0
fi

# Normalize raw "path:count" lines into JSON. Path may contain colons on some
# systems but ripgrep/grep -c emit "<path>:<integer>" with the last colon as
# the separator, so split on the last one.
parsed="$(printf '%s\n' "$raw" | awk -v root="$REPO_ROOT" '
  {
    line = $0
    idx = match(line, /:[0-9]+$/)
    if (idx == 0) next
    path = substr(line, 1, idx - 1)
    hits = substr(line, idx + 1) + 0
    if (hits <= 0) next
    n = split(path, parts, "/")
    if (n <= 1) {
      dir = "."
    } else {
      dir = parts[1]
      for (i = 2; i < n; i++) dir = dir "/" parts[i]
    }
    rel_path = path
    rel_dir = dir
    if (index(path, root) == 1) {
      rel_path = substr(path, length(root) + 2)
      n2 = split(rel_path, rp, "/")
      if (n2 <= 1) rel_dir = "."
      else {
        rel_dir = rp[1]
        for (i = 2; i < n2; i++) rel_dir = rel_dir "/" rp[i]
      }
    }
    printf "%s\t%s\t%d\n", rel_dir, rel_path, hits
  }
')"

if [[ -z "$parsed" ]]; then
  jq -n \
    --argjson keywords "$keywords_json" \
    --argjson exclusions "$exclusions_json" \
    '{
      keywords: $keywords,
      matches: [],
      top_directories: [],
      exclusions_applied: $exclusions
    }'
  exit 0
fi

# Convert TSV lines into JSON file entries, group by directory, sort, slice.
json_entries="$(printf '%s\n' "$parsed" | jq -R 'split("\t") | {directory: .[0], path: .[1], hits: (.[2]|tonumber)}' | jq -s .)"

result="$(jq \
  --argjson keywords "$keywords_json" \
  --argjson exclusions "$exclusions_json" \
  --argjson top_n "$TOP_N" \
  '
  group_by(.directory)
  | map({
      directory: .[0].directory,
      files: (map({path: .path, hits: .hits}) | sort_by(-.hits)),
      total_hits: (map(.hits) | add)
    })
  | sort_by(-.total_hits)
  | .[0:$top_n] as $top
  | {
      keywords: $keywords,
      matches: $top,
      top_directories: ($top | map(.directory)),
      exclusions_applied: $exclusions
    }
  ' <<<"$json_entries")"

printf '%s\n' "$result"
