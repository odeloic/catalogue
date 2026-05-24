#!/usr/bin/env bash
#
# Prefix-style detection assertions for extract-commit-style.sh.
#
# Each fixture under tests/fixtures/<style>/commits.txt is a list of commits
# in the format the script's --fixture loader expects:
#
#   - Subject line, then optional body lines.
#   - Commits separated by a line containing only `---` (three dashes).
#
# The test passes the fixture dir to the script via --fixture and asserts the
# detected prefix_style. Source-detection bugs and JSON-shape bugs both surface
# here, so this is the highest-leverage test in the skill.
#
# Run from the repo root:
#   bash skills/commit-changes/tests/test-extract-style.sh

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
EXTRACT="$SKILL_DIR/scripts/extract-commit-style.sh"

pass=0; fail=0

assert_style() {
  local label="$1" fixture="$2" expected="$3"
  local out exit_code=0
  out="$("$EXTRACT" --fixture "$SKILL_DIR/tests/fixtures/$fixture" 2>&1)" || exit_code=$?
  if (( exit_code != 0 )); then
    fail=$((fail+1))
    printf '  FAIL  %-30s script exited %s\n         out: %s\n' "$label" "$exit_code" "$out"
    return
  fi
  local got
  got="$(printf '%s' "$out" | jq -r '.prefix_style' 2>/dev/null || true)"
  if [[ "$got" == "$expected" ]]; then
    pass=$((pass+1))
    printf '  ok    %-30s -> %s\n' "$label" "$expected"
  else
    fail=$((fail+1))
    printf '  FAIL  %-30s expected=%s got=%s\n' "$label" "$expected" "$got"
    printf '         out: %s\n' "$(printf '%s' "$out" | head -c 400)"
  fi
}

assert_field() {
  local label="$1" fixture="$2" field="$3" expected="$4"
  local out got exit_code=0
  out="$("$EXTRACT" --fixture "$SKILL_DIR/tests/fixtures/$fixture" 2>&1)" || exit_code=$?
  if (( exit_code != 0 )); then
    fail=$((fail+1))
    printf '  FAIL  %-30s script exited %s\n' "$label" "$exit_code"
    return
  fi
  got="$(printf '%s' "$out" | jq -r "$field" 2>/dev/null || true)"
  if [[ "$got" == "$expected" ]]; then
    pass=$((pass+1))
    printf '  ok    %-30s %s = %s\n' "$label" "$field" "$expected"
  else
    fail=$((fail+1))
    printf '  FAIL  %-30s %s expected=%s got=%s\n' "$label" "$field" "$expected" "$got"
  fi
}

echo "Prefix-style detection:"
assert_style "conventional fixture"  conventional conventional
assert_style "ticket fixture"        ticket       ticket
assert_style "plain fixture"         plain        none
assert_style "gitmoji fixture"       gitmoji      gitmoji

echo
echo "Derived fields:"
assert_field "conventional uses scope" conventional ".scope_used" "true"
assert_field "ticket has no scope"     ticket       ".scope_used" "false"
assert_field "plain is sentence-case"  plain        ".subject_case" "sentence"

echo
echo "Passed: $pass   Failed: $fail"
[[ "$fail" -eq 0 ]]
