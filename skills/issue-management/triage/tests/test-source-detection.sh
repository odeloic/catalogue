#!/usr/bin/env bash
#
# Source-detection assertions for fetch-issue.sh.
#
# Runs the script in fixture mode (no network) for cases that have a fixture,
# and inspects exit codes + stderr for the rest. Source detection is where
# real bugs live, so this file is the single most useful test in the skill.
#
# Run from the repo root:
#   bash skills/issue-management/triage/tests/test-source-detection.sh

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
FETCH="$SKILL_DIR/scripts/fetch-issue.sh"

pass=0; fail=0

assert_source() {
  local label="$1" input="$2" expected="$3"
  local out exit_code
  out="$(FETCH_ISSUE_MODE=fixture "$FETCH" "$input" 2>&1)" || exit_code=$?
  exit_code=${exit_code:-0}
  local got
  got="$(printf '%s' "$out" | jq -r '.source' 2>/dev/null || true)"
  if [[ "$got" == "$expected" ]]; then
    pass=$((pass+1))
    printf '  ok    %-40s → %s\n' "$label" "$expected"
  else
    fail=$((fail+1))
    printf '  FAIL  %-40s expected=%s got=%s exit=%s\n' "$label" "$expected" "$got" "$exit_code"
    printf '         out: %s\n' "$out" | head -2
  fi
}

assert_linear_handoff() {
  local label="$1" input="$2" expected_id="$3"
  local out exit_code
  out="$("$FETCH" "$input" 2>&1)" || exit_code=$?
  exit_code=${exit_code:-0}
  if [[ "$exit_code" -eq 2 && "$out" == *"LINEAR:$expected_id"* ]]; then
    pass=$((pass+1))
    printf '  ok    %-40s → LINEAR:%s (exit 2)\n' "$label" "$expected_id"
  else
    fail=$((fail+1))
    printf '  FAIL  %-40s expected exit=2 LINEAR:%s, got exit=%s out=%s\n' "$label" "$expected_id" "$exit_code" "$out"
  fi
}

assert_unresolved() {
  local label="$1" input="$2"
  local exit_code=0
  "$FETCH" "$input" >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 3 ]]; then
    pass=$((pass+1))
    printf '  ok    %-40s → exit 3\n' "$label"
  else
    fail=$((fail+1))
    printf '  FAIL  %-40s expected exit=3, got exit=%s\n' "$label" "$exit_code"
  fi
}

echo "Source detection:"
assert_source "github URL"        "https://github.com/odeloic/jonas/issues/26" github
assert_source "gitlab URL"        "https://gitlab.com/group/project/-/issues/42" gitlab
assert_linear_handoff "linear bare ID"        "ENG-1" "ENG-1"
assert_linear_handoff "linear in branch path" "user/ode-18-feature" "ODE-18"
assert_linear_handoff "linear URL"            "https://linear.app/acme/issue/ENG-1/x" "ENG-1"
assert_unresolved "garbage input"             "not-an-issue-at-all"

echo
echo "Passed: $pass   Failed: $fail"
[[ "$fail" -eq 0 ]]
