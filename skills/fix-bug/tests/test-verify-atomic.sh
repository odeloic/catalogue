#!/usr/bin/env bash
#
# Assertions for verify-atomic.sh. Copies the atomic fixture to a tempdir,
# initializes a minimal git repo there, and runs the script with pre-computed
# diff fixtures supplied via VERIFY_ATOMIC_NAMES / VERIFY_ATOMIC_DIFF.
#
# Run from the repo root:
#   bash skills/fix-bug/tests/test-verify-atomic.sh

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VERIFY="$SKILL_DIR/scripts/verify-atomic.sh"
FIXTURES="$SKILL_DIR/tests/fixtures/atomic"

pass=0; fail=0

setup_repo() {
  local dir
  dir="$(mktemp -d)"
  cp -R "$FIXTURES/.claude" "$dir/"
  (
    cd "$dir"
    git init -q -b main
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  )
  printf '%s' "$dir"
}

run_verify() {
  local repo="$1" id="$2" names="$3" numstat="$4"
  local names_file numstat_file
  names_file="$(mktemp)"; printf '%s\n' "$names" > "$names_file"
  numstat_file="$(mktemp)"; printf '%s\n' "$numstat" > "$numstat_file"
  VERIFY_ATOMIC_BASE="HEAD" \
  VERIFY_ATOMIC_NAMES="$names_file" \
  VERIFY_ATOMIC_DIFF="$numstat_file" \
  "$VERIFY" "$id" "$repo"
  local rc=$?
  rm -f "$names_file" "$numstat_file"
  return $rc
}

assert_jq() {
  local label="$1" json="$2" expr="$3" expected="$4"
  local got
  got="$(printf '%s' "$json" | jq -r "$expr" 2>/dev/null || true)"
  if [[ "$got" == "$expected" ]]; then
    pass=$((pass+1))
    printf '  ok    %-55s %s = %s\n' "$label" "$expr" "$expected"
  else
    fail=$((fail+1))
    printf '  FAIL  %-55s %s expected=%s got=%s\n' "$label" "$expr" "$expected" "$got"
  fi
}

# ---- case 1: clean in-scope fix --------------------------------------------

echo "Case 1: clean in-scope fix (LoginButton.tsx + its test)"
repo="$(setup_repo)"
names=$'src/components/LoginButton.tsx\nsrc/components/LoginButton.test.tsx'
numstat=$'4\t1\tsrc/components/LoginButton.tsx\n12\t0\tsrc/components/LoginButton.test.tsx'
out="$(run_verify "$repo" ENG-1 "$names" "$numstat")"
assert_jq "in-scope" "$out" '.stats.files'                  "2"
assert_jq "in-scope" "$out" '.stats.added'                  "16"
assert_jq "in-scope" "$out" '.stats.removed'                "1"
assert_jq "in-scope" "$out" '.test_files | length'          "1"
assert_jq "in-scope" "$out" '.source_files | length'        "1"
assert_jq "in-scope" "$out" '.unrelated_candidates | length' "0"
assert_jq "in-scope" "$out" '.lockfile_changes | length'    "0"
rm -rf "$repo"

# ---- case 2: lockfile and an unrelated file --------------------------------

echo
echo "Case 2: includes a lockfile change and an unrelated source file"
repo="$(setup_repo)"
names=$'src/components/LoginButton.tsx\npackage-lock.json\nsrc/unrelated/Other.tsx'
numstat=$'2\t1\tsrc/components/LoginButton.tsx\n200\t10\tpackage-lock.json\n5\t0\tsrc/unrelated/Other.tsx'
out="$(run_verify "$repo" ENG-1 "$names" "$numstat")"
assert_jq "lockfile" "$out" '.lockfile_changes | length'    "1"
assert_jq "lockfile" "$out" '.lockfile_changes[0]'          "package-lock.json"
assert_jq "unrelated" "$out" '.unrelated_candidates | length' "1"
assert_jq "unrelated" "$out" '.unrelated_candidates[0]'     "src/unrelated/Other.tsx"
assert_jq "warnings present" "$out" '.warnings | length >= 1' "true"
rm -rf "$repo"

# ---- case 3: no scope hints in triage --------------------------------------

echo
echo "Case 3: triage has no hints — unrelated_candidates stays empty, warns"
repo="$(setup_repo)"
names=$'src/foo.ts\nsrc/bar.ts'
numstat=$'1\t1\tsrc/foo.ts\n1\t0\tsrc/bar.ts'
out="$(run_verify "$repo" ENG-EMPTY "$names" "$numstat")"
assert_jq "no-hints" "$out" '.unrelated_candidates | length' "0"
assert_jq "no-hints" "$out" '.warnings | any(. | contains("no file/area hints"))' "true"
rm -rf "$repo"

# ---- case 4: missing triage file -------------------------------------------

echo
echo "Case 4: missing triage file exits non-zero"
repo="$(setup_repo)"
rc=0
VERIFY_ATOMIC_BASE="HEAD" "$VERIFY" "DOES-NOT-EXIST" "$repo" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 1 ]]; then
  pass=$((pass+1))
  printf '  ok    %-55s exit code = 1\n' "missing-triage"
else
  fail=$((fail+1))
  printf '  FAIL  %-55s expected exit=1 got=%s\n' "missing-triage" "$rc"
fi
rm -rf "$repo"

# ---- case 5: missing triage id argument ------------------------------------

echo
echo "Case 5: no triage id argument exits 2"
rc=0
"$VERIFY" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass=$((pass+1))
  printf '  ok    %-55s exit code = 2\n' "no-arg"
else
  fail=$((fail+1))
  printf '  FAIL  %-55s expected exit=2 got=%s\n' "no-arg" "$rc"
fi

echo
echo "Passed: $pass   Failed: $fail"
[[ "$fail" -eq 0 ]]
