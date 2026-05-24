#!/usr/bin/env bash
#
# Assertions for fetch-pr-context.sh: source detection, JSON shape, and
# size_class classification. Runs the script in fixture mode (no network).
#
# Run from the repo root:
#   bash skills/review-changes/tests/test-fetch-pr-context.sh

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
FETCH="$SKILL_DIR/scripts/fetch-pr-context.sh"

pass=0; fail=0

run_fetch() {
  FETCH_PR_MODE=fixture "$FETCH" "$1" 2>/dev/null
}

assert_source() {
  local label="$1" input="$2" expected="$3"
  local out got
  out="$(run_fetch "$input")" || true
  got="$(printf '%s' "$out" | jq -r '.source' 2>/dev/null || true)"
  if [[ "$got" == "$expected" ]]; then
    pass=$((pass+1))
    printf '  ok    %-50s -> %s\n' "$label" "$expected"
  else
    fail=$((fail+1))
    printf '  FAIL  %-50s expected=%s got=%s\n' "$label" "$expected" "$got"
  fi
}

assert_id() {
  local label="$1" input="$2" expected="$3"
  local out got
  out="$(run_fetch "$input")" || true
  got="$(printf '%s' "$out" | jq -r '.id' 2>/dev/null || true)"
  if [[ "$got" == "$expected" ]]; then
    pass=$((pass+1))
    printf '  ok    %-50s -> id=%s\n' "$label" "$expected"
  else
    fail=$((fail+1))
    printf '  FAIL  %-50s expected id=%s got=%s\n' "$label" "$expected" "$got"
  fi
}

assert_size_class() {
  local label="$1" input="$2" expected="$3"
  local out got
  out="$(run_fetch "$input")" || true
  got="$(printf '%s' "$out" | jq -r '.size_metrics.size_class' 2>/dev/null || true)"
  if [[ "$got" == "$expected" ]]; then
    pass=$((pass+1))
    printf '  ok    %-50s -> size=%s\n' "$label" "$expected"
  else
    fail=$((fail+1))
    printf '  FAIL  %-50s expected size=%s got=%s\n' "$label" "$expected" "$got"
  fi
}

assert_has_keys() {
  local label="$1" input="$2"
  shift 2
  local out missing=""
  out="$(run_fetch "$input")" || true
  for key in "$@"; do
    local present
    present="$(printf '%s' "$out" | jq "has(\"$key\")" 2>/dev/null || echo false)"
    if [[ "$present" != "true" ]]; then
      missing="$missing $key"
    fi
  done
  if [[ -z "$missing" ]]; then
    pass=$((pass+1))
    printf '  ok    %-50s -> all top-level keys present\n' "$label"
  else
    fail=$((fail+1))
    printf '  FAIL  %-50s missing:%s\n' "$label" "$missing"
  fi
}

assert_unresolved() {
  local label="$1" input="$2"
  local exit_code=0
  FETCH_PR_MODE=fixture "$FETCH" "$input" >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 3 ]]; then
    pass=$((pass+1))
    printf '  ok    %-50s -> exit 3\n' "$label"
  else
    fail=$((fail+1))
    printf '  FAIL  %-50s expected exit=3 got=%s\n' "$label" "$exit_code"
  fi
}

echo "Source detection:"
assert_source "github PR URL"          "https://github.com/odeloic/jonas/pull/42" github
assert_source "gitlab MR URL"          "https://gitlab.com/acme/widgets/-/merge_requests/77" gitlab
assert_source "local branch name"      "refactor/auth-overhaul" local

echo
echo "ID extraction:"
assert_id "github PR URL"              "https://github.com/odeloic/jonas/pull/42" 42
assert_id "gitlab MR URL"              "https://gitlab.com/acme/widgets/-/merge_requests/77" 77
assert_id "local branch -> slugified"  "refactor/auth-overhaul" refactor_auth-overhaul

echo
echo "Size classification (re-derived from metrics in fixture):"
assert_size_class "github small PR"    "https://github.com/odeloic/jonas/pull/42" small
assert_size_class "gitlab medium MR"   "https://gitlab.com/acme/widgets/-/merge_requests/77" medium
assert_size_class "local xlarge"       "refactor/auth-overhaul" xlarge

echo
echo "JSON shape (top-level keys present):"
assert_has_keys "github PR" "https://github.com/odeloic/jonas/pull/42" \
  source id url title author is_draft base head diff files_changed linked_issues ci size_metrics depends_on
assert_has_keys "gitlab MR" "https://gitlab.com/acme/widgets/-/merge_requests/77" \
  source id url title author is_draft base head diff files_changed linked_issues ci size_metrics depends_on
assert_has_keys "local branch" "refactor/auth-overhaul" \
  source id url title author is_draft base head diff files_changed linked_issues ci size_metrics depends_on

echo
echo "Unresolved inputs:"
assert_unresolved "garbage with spaces" "not an issue at all"

echo
echo "Passed: $pass   Failed: $fail"
[[ "$fail" -eq 0 ]]
