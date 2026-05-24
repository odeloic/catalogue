#!/usr/bin/env bash
#
# Assertions for detect-tracker.sh and template-loader.sh.
#
# detect-tracker.sh is driven via DETECT_TRACKER_FIXTURE_REMOTE so we don't
# depend on any real remote. template-loader.sh is checked for both valid
# inputs (exit 0 + content) and invalid inputs (exit 1).
#
# Run from the repo root:
#   bash skills/create-issue/tests/test-detect-tracker.sh

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DETECT="$SKILL_DIR/scripts/detect-tracker.sh"
LOADER="$SKILL_DIR/scripts/template-loader.sh"
FIX_DIR="$SCRIPT_DIR/fixtures/remotes"

pass=0; fail=0

assert_tracker() {
  local label="$1" fixture="$2" expected="$3"
  local remote out got exit_code=0
  remote="$(cat "$FIX_DIR/$fixture" | tr -d '\n')"
  out="$(DETECT_TRACKER_FIXTURE_REMOTE="$remote" "$DETECT" 2>&1)" || exit_code=$?
  got="$(printf '%s' "$out" | jq -r '.primary_tracker' 2>/dev/null || true)"
  if [[ "$exit_code" -eq 0 && "$got" == "$expected" ]]; then
    pass=$((pass+1))
    printf '  ok    %-40s → %s\n' "$label" "$expected"
  else
    fail=$((fail+1))
    printf '  FAIL  %-40s expected=%s got=%s exit=%s\n' "$label" "$expected" "$got" "$exit_code"
    printf '         out: %s\n' "$out" | head -2
  fi
}

assert_loader_ok() {
  local label="$1" type="$2" tracker="$3"
  local out exit_code=0
  out="$("$LOADER" "$type" "$tracker" 2>&1)" || exit_code=$?
  if [[ "$exit_code" -eq 0 && -n "$out" ]]; then
    pass=$((pass+1))
    printf '  ok    %-40s → exit 0, %d bytes\n' "$label" "${#out}"
  else
    fail=$((fail+1))
    printf '  FAIL  %-40s expected exit=0 with content, got exit=%s len=%d\n' "$label" "$exit_code" "${#out}"
  fi
}

assert_loader_fail() {
  local label="$1"
  shift
  local exit_code=0
  "$LOADER" "$@" >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 1 ]]; then
    pass=$((pass+1))
    printf '  ok    %-40s → exit 1\n' "$label"
  else
    fail=$((fail+1))
    printf '  FAIL  %-40s expected exit=1, got exit=%s\n' "$label" "$exit_code"
  fi
}

echo "Tracker detection:"
assert_tracker "github HTTPS remote"  "github-https.txt" github
assert_tracker "github SSH remote"    "github-ssh.txt"   github
assert_tracker "gitlab HTTPS remote"  "gitlab-https.txt" gitlab
assert_tracker "gitlab SSH remote"    "gitlab-ssh.txt"   gitlab
assert_tracker "unknown host remote"  "unknown.txt"      unknown
assert_tracker "empty remote"         "empty.txt"        unknown

echo
echo "Template loader (valid):"
for type in bug feature improvement change; do
  for tracker in github gitlab linear; do
    assert_loader_ok "$type / $tracker" "$type" "$tracker"
  done
done

echo
echo "Template loader (invalid):"
assert_loader_fail "wrong arg count (0)"
assert_loader_fail "wrong arg count (1)"      bug
assert_loader_fail "invalid type"             nonsense github
assert_loader_fail "invalid tracker"          bug nonsense

echo
echo "Passed: $pass   Failed: $fail"
[[ "$fail" -eq 0 ]]
