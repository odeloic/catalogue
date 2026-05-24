#!/usr/bin/env bash
#
# Assertions for detect-test-infra.sh. Runs the script against each fixture
# directory and inspects the JSON output for the expected framework, command,
# and confidence.
#
# Run from the repo root:
#   bash skills/fix-bug/tests/test-detect-test-infra.sh

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DETECT="$SKILL_DIR/scripts/detect-test-infra.sh"
FIXTURES="$SKILL_DIR/tests/fixtures"

pass=0; fail=0

assert_field() {
  local label="$1" fixture="$2" field="$3" expected="$4"
  local out got
  out="$("$DETECT" "$FIXTURES/$fixture" 2>&1)" || true
  got="$(printf '%s' "$out" | jq -r "$field" 2>/dev/null || true)"
  if [[ "$got" == "$expected" ]]; then
    pass=$((pass+1))
    printf '  ok    %-45s %s = %s\n' "$label" "$field" "$expected"
  else
    fail=$((fail+1))
    printf '  FAIL  %-45s %s expected=%s got=%s\n' "$label" "$field" "$expected" "$got"
    printf '         out: %s\n' "$(printf '%s' "$out" | head -c 300)"
  fi
}

assert_evidence_contains() {
  local label="$1" fixture="$2" needle="$3"
  local out
  out="$("$DETECT" "$FIXTURES/$fixture" 2>&1)" || true
  if printf '%s' "$out" | jq -e --arg n "$needle" '.evidence | any(. | contains($n))' >/dev/null 2>&1; then
    pass=$((pass+1))
    printf '  ok    %-45s evidence contains "%s"\n' "$label" "$needle"
  else
    fail=$((fail+1))
    printf '  FAIL  %-45s evidence missing "%s"\n' "$label" "$needle"
    printf '         out: %s\n' "$(printf '%s' "$out" | head -c 300)"
  fi
}

echo "Node / vitest fixture:"
assert_field "node-vitest" node-vitest ".exists"     "true"
assert_field "node-vitest" node-vitest ".framework"  "vitest"
assert_field "node-vitest" node-vitest ".test_command" "pnpm test"
assert_field "node-vitest" node-vitest ".confidence" "high"
assert_evidence_contains "node-vitest" node-vitest "package.json:devDependencies.vitest"

echo
echo "Python / pytest fixture:"
assert_field "python-pytest" python-pytest ".exists"      "true"
assert_field "python-pytest" python-pytest ".framework"   "pytest"
assert_field "python-pytest" python-pytest ".test_command" "pytest"
assert_field "python-pytest" python-pytest ".confidence"  "high"

echo
echo "Go fixture:"
assert_field "go-mod" go-mod ".exists"      "true"
assert_field "go-mod" go-mod ".framework"   "go test"
assert_field "go-mod" go-mod ".test_command" "go test ./..."

echo
echo "Rust fixture:"
assert_field "rust-cargo" rust-cargo ".exists"      "true"
assert_field "rust-cargo" rust-cargo ".framework"   "cargo test"
assert_field "rust-cargo" rust-cargo ".test_command" "cargo test"

echo
echo "No-test-infra fixture:"
assert_field "no-test-infra" no-test-infra ".exists" "false"

echo
echo "Passed: $pass   Failed: $fail"
[[ "$fail" -eq 0 ]]
