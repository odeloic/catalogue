#!/usr/bin/env bash
#
# Assertions for investigate.sh + render-mermaid.sh.
#
# Runs investigate.sh against the fixture tree under tests/fixtures/sample-repo
# and checks ranking + suggestion behavior. Smoke-tests render-mermaid.sh.
#
# Run from the repo root:
#   bash skills/explain-codebase/tests/test-investigate.sh

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INVESTIGATE="$SKILL_DIR/scripts/investigate.sh"
RENDER="$SKILL_DIR/scripts/render-mermaid.sh"
FIXTURE="$SKILL_DIR/tests/fixtures/sample-repo"

pass=0; fail=0

if ! command -v rg >/dev/null 2>&1; then
  echo "SKIP: ripgrep (rg) is not installed. Install with: brew install ripgrep"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq is not installed. Install with: brew install jq"
  exit 0
fi

run_investigate() {
  INVESTIGATE_FIXTURE_ROOT="$FIXTURE" "$INVESTIGATE" "$@" 2>/dev/null
}

assert_eq() {
  local label="$1" expected="$2" got="$3"
  if [[ "$got" == "$expected" ]]; then
    pass=$((pass+1))
    printf '  ok    %-50s → %s\n' "$label" "$got"
  else
    fail=$((fail+1))
    printf '  FAIL  %-50s expected=%s got=%s\n' "$label" "$expected" "$got"
  fi
}

assert_nonempty() {
  local label="$1" got="$2"
  if [[ -n "$got" && "$got" != "null" && "$got" != "[]" ]]; then
    pass=$((pass+1))
    printf '  ok    %-50s → %s\n' "$label" "$got"
  else
    fail=$((fail+1))
    printf '  FAIL  %-50s expected non-empty, got=%s\n' "$label" "$got"
  fi
}

assert_gt() {
  local label="$1" threshold="$2" got="$3"
  if [[ "$got" -gt "$threshold" ]] 2>/dev/null; then
    pass=$((pass+1))
    printf '  ok    %-50s → %s > %s\n' "$label" "$got" "$threshold"
  else
    fail=$((fail+1))
    printf '  FAIL  %-50s expected > %s, got=%s\n' "$label" "$threshold" "$got"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass=$((pass+1))
    printf '  ok    %-50s → contains "%s"\n' "$label" "$needle"
  else
    fail=$((fail+1))
    printf '  FAIL  %-50s expected to contain "%s"\n' "$label" "$needle"
  fi
}

echo "investigate.sh — known keyword (session):"
OUT="$(run_investigate session)"
assert_gt        "total_hits > 0"                0 "$(jq '.total_hits' <<<"$OUT")"
assert_eq        "#1 ranked_file is session.ts"  "src/auth/session.ts" "$(jq -r '.ranked_files[0].path' <<<"$OUT")"
assert_gt        "#1 has definitions > 0"        0 "$(jq '.ranked_files[0].definitions' <<<"$OUT")"
assert_eq        "no suggestions key on hit"     "null" "$(jq '.suggestions // null' <<<"$OUT" | head -1)"

echo
echo "investigate.sh — known keyword (auth):"
OUT="$(run_investigate auth)"
assert_eq        "#1 ranked_file is auth.ts"     "src/auth/auth.ts" "$(jq -r '.ranked_files[0].path' <<<"$OUT")"
assert_gt        "#1 has definitions > 0"        0 "$(jq '.ranked_files[0].definitions' <<<"$OUT")"

echo
echo "investigate.sh — empty result, suggestions present:"
OUT="$(run_investigate xyznonexistentterm)"
assert_eq        "total_hits == 0"               "0" "$(jq '.total_hits' <<<"$OUT")"
assert_eq        "ranked_files is []"            "[]" "$(jq -c '.ranked_files' <<<"$OUT")"
assert_nonempty  "suggestions non-empty"         "$(jq -c '.suggestions' <<<"$OUT")"

echo
echo "render-mermaid.sh — smoke:"
TMP_DIAGRAM="$(mktemp -t explain-diagram-XXXXXX).mmd"
trap 'rm -f "$TMP_DIAGRAM"' EXIT
printf 'flowchart LR\n  A --> B\n  B --> C\n' > "$TMP_DIAGRAM"
HTML_OUT="$("$RENDER" "$TMP_DIAGRAM" --title "Test Diagram" --explanation "A simple flow." 2>/dev/null)"
assert_contains  "html contains <pre class=mermaid>" '<pre class="mermaid">' "$HTML_OUT"
assert_contains  "html contains diagram source"      'flowchart LR' "$HTML_OUT"
assert_contains  "html contains A --> B"             'A --> B' "$HTML_OUT"
assert_contains  "html contains title"               '<title>Test Diagram</title>' "$HTML_OUT"
assert_contains  "html contains explanation"         'A simple flow.' "$HTML_OUT"

echo
echo "Passed: $pass   Failed: $fail"
[[ "$fail" -eq 0 ]]
