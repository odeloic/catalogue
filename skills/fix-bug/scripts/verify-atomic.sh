#!/usr/bin/env bash
#
# verify-atomic.sh <triage-id> [target-dir]
#
# Reads .claude/triage/<triage-id>.json from the target repo, diffs the working
# tree against the merge base of HEAD and the upstream/default branch, and
# classifies each touched file as test/source/lockfile/unrelated relative to
# the scope hints in the triage report.
#
# Read-only. Does not modify the working tree.
#
# Output: JSON to stdout. Shape:
#   {
#     "files_touched": ["..."],
#     "test_files": ["..."],
#     "source_files": ["..."],
#     "unrelated_candidates": ["..."],
#     "lockfile_changes": ["package-lock.json"],
#     "warnings": ["..."],
#     "stats": { "added": 12, "removed": 4, "files": 3 }
#   }
#
# Exit codes:
#   0  success — JSON on stdout
#   1  fatal (missing jq, not a git repo, triage file missing, etc.)
#   2  triage id not provided
#
# Env:
#   VERIFY_ATOMIC_BASE  Override the merge-base reference (default: auto-detect
#                       origin/HEAD, then origin/main, then origin/master, then
#                       main, then master, then HEAD).
#   VERIFY_ATOMIC_DIFF  Path to a file containing a pre-computed `git diff
#                       --numstat` output. For tests.
#   VERIFY_ATOMIC_NAMES Path to a file containing a pre-computed `git diff
#                       --name-only` output. For tests.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

err() { printf '%s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required command: $1"; exit 1; }
}

require_cmd jq

TRIAGE_ID="${1:-}"
if [[ -z "$TRIAGE_ID" ]]; then
  err "usage: verify-atomic.sh <triage-id> [target-dir]"
  exit 2
fi

TARGET="${2:-$PWD}"
if [[ ! -d "$TARGET" ]]; then
  err "target directory not found: $TARGET"
  exit 1
fi
TARGET="$(cd -- "$TARGET" && pwd)"

REPO_ROOT="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  err "not inside a git repo: $TARGET"
  exit 1
fi

TRIAGE_FILE="$REPO_ROOT/.claude/triage/$TRIAGE_ID.json"
if [[ ! -f "$TRIAGE_FILE" ]]; then
  err "triage file not found: $TRIAGE_FILE"
  exit 1
fi

WARNINGS=()
add_warning() { WARNINGS+=("$1"); }

# ---- merge base resolution -------------------------------------------------

resolve_base() {
  if [[ -n "${VERIFY_ATOMIC_BASE:-}" ]]; then
    printf '%s' "$VERIFY_ATOMIC_BASE"
    return
  fi
  local cand
  for cand in origin/HEAD origin/main origin/master main master; do
    if git -C "$REPO_ROOT" rev-parse --verify --quiet "$cand" >/dev/null; then
      printf '%s' "$cand"
      return
    fi
  done
  printf '%s' "HEAD"
}

BASE="$(resolve_base)"

# ---- diff collection -------------------------------------------------------

MERGE_BASE=""
if [[ "$BASE" != "HEAD" ]]; then
  MERGE_BASE="$(git -C "$REPO_ROOT" merge-base "$BASE" HEAD 2>/dev/null || true)"
fi
if [[ -z "$MERGE_BASE" ]]; then
  MERGE_BASE="HEAD"
  add_warning "no merge base resolvable; comparing against HEAD (working tree only)"
fi

collect_names() {
  if [[ -n "${VERIFY_ATOMIC_NAMES:-}" ]]; then
    cat "$VERIFY_ATOMIC_NAMES"
    return
  fi
  if [[ "$MERGE_BASE" == "HEAD" ]]; then
    git -C "$REPO_ROOT" diff --name-only HEAD
    git -C "$REPO_ROOT" ls-files --others --exclude-standard
  else
    git -C "$REPO_ROOT" diff --name-only "$MERGE_BASE"...HEAD
    git -C "$REPO_ROOT" diff --name-only HEAD
    git -C "$REPO_ROOT" ls-files --others --exclude-standard
  fi
}

collect_numstat() {
  if [[ -n "${VERIFY_ATOMIC_DIFF:-}" ]]; then
    cat "$VERIFY_ATOMIC_DIFF"
    return
  fi
  if [[ "$MERGE_BASE" == "HEAD" ]]; then
    git -C "$REPO_ROOT" diff --numstat HEAD
  else
    git -C "$REPO_ROOT" diff --numstat "$MERGE_BASE"...HEAD
    git -C "$REPO_ROOT" diff --numstat HEAD
  fi
}

NAMES_RAW="$(collect_names || true)"
NUMSTAT_RAW="$(collect_numstat || true)"

# Deduplicate and drop blanks.
FILES_TOUCHED=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  FILES_TOUCHED+=("$line")
done < <(printf '%s\n' "$NAMES_RAW" | awk 'NF' | sort -u)

# ---- scope hints from triage ----------------------------------------------

# Pull anything that looks like a path out of the triage doc. Look in
# description, comments[].body, and any explicit files_touched array.
SCOPE_HINTS_JSON="$(jq -r '
  def paths_from(t):
    [ t | scan("[A-Za-z0-9_./-]+\\.[A-Za-z0-9_]+") ]
    | map(select(test("/") or test("\\.(js|jsx|ts|tsx|py|go|rs|rb|php|ex|exs|java|kt|swift|c|cc|cpp|h|hpp|md|yml|yaml|json|toml)$")));
  [
    (paths_from(.description // ""))[],
    ((.comments // [])[] | paths_from(.body // ""))[],
    ((.fix // {}) | (.files_touched // [])[])
  ]
  | unique
' "$TRIAGE_FILE" 2>/dev/null || echo "[]")"

mapfile -t SCOPE_HINTS < <(jq -r '.[]' <<<"$SCOPE_HINTS_JSON" 2>/dev/null || true)

# ---- classify files --------------------------------------------------------

is_test_file() {
  local f="$1"
  case "$f" in
    *test_*.py|*_test.py|*tests/*|*test/*|*__tests__/*|*.test.ts|*.test.tsx|*.test.js|*.test.jsx) return 0 ;;
    *.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx|*_test.go|spec/*|*/spec/*) return 0 ;;
    *_spec.rb|*test*.rb) return 0 ;;
  esac
  return 1
}

is_lockfile() {
  local f
  f="$(basename "$1")"
  case "$f" in
    package-lock.json|pnpm-lock.yaml|yarn.lock|bun.lock|bun.lockb|Cargo.lock|composer.lock|Gemfile.lock|poetry.lock|uv.lock|go.sum|mix.lock) return 0 ;;
  esac
  return 1
}

is_generated() {
  local f="$1"
  case "$f" in
    *.min.js|*.min.css|dist/*|*/dist/*|build/*|*/build/*|node_modules/*|vendor/*) return 0 ;;
  esac
  return 1
}

# A modified source file is "in scope" if it:
#   - is listed verbatim in scope hints,
#   - shares a basename with something in scope hints,
#   - or imports / is imported by a source file already in scope (one hop).
matches_hint() {
  local f="$1"
  local base
  base="$(basename "$f")"
  for hint in "${SCOPE_HINTS[@]:-}"; do
    [[ -z "$hint" ]] && continue
    if [[ "$f" == *"$hint" || "$hint" == *"$f" || "$base" == "$(basename "$hint")" ]]; then
      return 0
    fi
  done
  return 1
}

SOURCE_FILES=()
TEST_FILES=()
LOCKFILES=()
GENERATED=()
SOURCE_NON_TEST=()

for f in "${FILES_TOUCHED[@]:-}"; do
  [[ -z "$f" ]] && continue
  if is_lockfile "$f"; then
    LOCKFILES+=("$f")
    continue
  fi
  if is_test_file "$f"; then
    TEST_FILES+=("$f")
    continue
  fi
  if is_generated "$f"; then
    GENERATED+=("$f")
    add_warning "generated/vendored file modified: $f"
    continue
  fi
  SOURCE_FILES+=("$f")
  SOURCE_NON_TEST+=("$f")
done

# One-hop import graph for source files. Cheap heuristic: a file imports
# another when its content references the other's basename (without ext).
imports_or_imported_by() {
  local a="$1" b="$2"
  local a_stem b_stem
  a_stem="$(basename "$a" | sed -E 's/\.[A-Za-z0-9]+$//')"
  b_stem="$(basename "$b" | sed -E 's/\.[A-Za-z0-9]+$//')"
  if [[ -f "$REPO_ROOT/$a" ]] && grep -q -F "$b_stem" "$REPO_ROOT/$a" 2>/dev/null; then
    return 0
  fi
  if [[ -f "$REPO_ROOT/$b" ]] && grep -q -F "$a_stem" "$REPO_ROOT/$b" 2>/dev/null; then
    return 0
  fi
  return 1
}

UNRELATED=()

# Files that match a hint directly form the seed set; others are checked for
# a one-hop link to any seed.
IN_SCOPE_SEEDS=()
for f in "${SOURCE_NON_TEST[@]:-}"; do
  if matches_hint "$f"; then
    IN_SCOPE_SEEDS+=("$f")
  fi
done

# Tests next to source files in scope are "in scope".
for f in "${SOURCE_NON_TEST[@]:-}"; do
  [[ -z "$f" ]] && continue
  if matches_hint "$f"; then
    continue
  fi
  # one-hop check against any in-scope seed
  hit=0
  for seed in "${IN_SCOPE_SEEDS[@]:-}"; do
    if imports_or_imported_by "$f" "$seed"; then
      hit=1; break
    fi
  done
  if [[ $hit -eq 0 ]]; then
    # If there are NO scope hints at all, do not flag everything as unrelated
    # — the agent has nothing to compare against. Surface a warning instead.
    if [[ ${#SCOPE_HINTS[@]} -eq 0 ]]; then
      :
    else
      UNRELATED+=("$f")
    fi
  fi
done

if [[ ${#SCOPE_HINTS[@]} -eq 0 ]]; then
  add_warning "triage has no file/area hints; cannot classify unrelated changes"
fi

if [[ ${#LOCKFILES[@]} -gt 0 ]]; then
  add_warning "lockfile changes present; confirm dependency updates are intentional"
fi

# ---- stats -----------------------------------------------------------------

ADDED=0
REMOVED=0
while IFS=$'\t' read -r add rem _path; do
  [[ -z "${add:-}" ]] && continue
  [[ "$add" == "-" ]] && add=0
  [[ "$rem" == "-" ]] && rem=0
  ADDED=$((ADDED + add))
  REMOVED=$((REMOVED + rem))
done < <(printf '%s\n' "$NUMSTAT_RAW" | awk 'NF')

FILES_COUNT=${#FILES_TOUCHED[@]}

# ---- emit ------------------------------------------------------------------

array_to_json() {
  local name="$1"
  local count_var="${name}[@]"
  local items=("${!count_var}")
  if [[ ${#items[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "${items[@]}" | jq -R . | jq -s .
  fi
}

FILES_JSON="$(array_to_json FILES_TOUCHED)"
TEST_JSON="$(array_to_json TEST_FILES)"
SOURCE_JSON="$(array_to_json SOURCE_FILES)"
UNRELATED_JSON="$(array_to_json UNRELATED)"
LOCK_JSON="$(array_to_json LOCKFILES)"
WARNINGS_JSON="$(array_to_json WARNINGS)"

jq -n \
  --argjson files "$FILES_JSON" \
  --argjson tests "$TEST_JSON" \
  --argjson sources "$SOURCE_JSON" \
  --argjson unrelated "$UNRELATED_JSON" \
  --argjson locks "$LOCK_JSON" \
  --argjson warnings "$WARNINGS_JSON" \
  --argjson added "$ADDED" \
  --argjson removed "$REMOVED" \
  --argjson files_count "$FILES_COUNT" \
  '{
    files_touched: $files,
    test_files: $tests,
    source_files: $sources,
    unrelated_candidates: $unrelated,
    lockfile_changes: $locks,
    warnings: $warnings,
    stats: { added: $added, removed: $removed, files: $files_count }
  }'
