#!/usr/bin/env bash
#
# Asserts on detect-migration-needs.sh output against three fixture repos:
#   - prisma-repo:  schema + migrations + a public surface
#   - openapi-repo: openapi contract + a public surface, no schema
#   - bare-repo:    nothing to detect
#
# Run from the repo root:
#   bash skills/ship-change/tests/test-detect-migration-needs.sh

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DETECT="$SKILL_DIR/scripts/detect-migration-needs.sh"
FIXTURES="$SKILL_DIR/tests/fixtures"

pass=0; fail=0

note_pass() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
note_fail() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; if [[ -n "${2:-}" ]]; then printf '         %s\n' "$2"; fi; }

run_against() {
  local root="$1"
  MIGRATION_SCAN_ROOT="$root" "$DETECT" 2>&1
}

# ---- prisma-repo -----------------------------------------------------------

echo "prisma-repo:"
out="$(run_against "$FIXTURES/prisma-repo")"

if [[ "$(jq -r '.has_migration_system' <<<"$out")" == "true" ]]; then
  note_pass "has_migration_system = true"
else
  note_fail "has_migration_system = true" "out=$out"
fi

if jq -e '.schema_files | index("prisma/schema.prisma")' <<<"$out" >/dev/null; then
  note_pass "schema_files includes prisma/schema.prisma"
else
  note_fail "schema_files includes prisma/schema.prisma" "schema_files=$(jq -c .schema_files <<<"$out")"
fi

if jq -e '.migration_paths | index("prisma/migrations")' <<<"$out" >/dev/null; then
  note_pass "migration_paths includes prisma/migrations"
else
  note_fail "migration_paths includes prisma/migrations" "migration_paths=$(jq -c .migration_paths <<<"$out")"
fi

if jq -e '.warnings | map(test("backward-compat")) | any' <<<"$out" >/dev/null; then
  note_pass "warnings mention backward-compat"
else
  note_fail "warnings mention backward-compat" "warnings=$(jq -c .warnings <<<"$out")"
fi

if jq -e '.warnings | map(test("deprecation strategy")) | any' <<<"$out" >/dev/null; then
  note_pass "warnings mention deprecation strategy (public surface)"
else
  note_fail "warnings mention deprecation strategy (public surface)" "warnings=$(jq -c .warnings <<<"$out")"
fi

# ---- openapi-repo ----------------------------------------------------------

echo
echo "openapi-repo:"
out="$(run_against "$FIXTURES/openapi-repo")"

if [[ "$(jq -r '.has_migration_system' <<<"$out")" == "false" ]]; then
  note_pass "has_migration_system = false (no schema)"
else
  note_fail "has_migration_system = false (no schema)" "out=$out"
fi

if jq -e '.api_contract_files | index("api/openapi.yaml")' <<<"$out" >/dev/null; then
  note_pass "api_contract_files includes api/openapi.yaml"
else
  note_fail "api_contract_files includes api/openapi.yaml" "api_contract_files=$(jq -c .api_contract_files <<<"$out")"
fi

if [[ "$(jq '.schema_files | length' <<<"$out")" -eq 0 ]]; then
  note_pass "schema_files is empty"
else
  note_fail "schema_files is empty" "schema_files=$(jq -c .schema_files <<<"$out")"
fi

if jq -e '.warnings | map(test("consumer-visible")) | any' <<<"$out" >/dev/null; then
  note_pass "warnings mention consumer-visible (API contract)"
else
  note_fail "warnings mention consumer-visible (API contract)" "warnings=$(jq -c .warnings <<<"$out")"
fi

# ---- bare-repo -------------------------------------------------------------

echo
echo "bare-repo:"
out="$(run_against "$FIXTURES/bare-repo")"

if [[ "$(jq -r '.has_migration_system' <<<"$out")" == "false" ]]; then
  note_pass "has_migration_system = false"
else
  note_fail "has_migration_system = false" "out=$out"
fi

for field in migration_paths schema_files api_contract_files public_api_surfaces config_schemas warnings; do
  if [[ "$(jq ".$field | length" <<<"$out")" -eq 0 ]]; then
    note_pass "$field is empty"
  else
    note_fail "$field is empty" "$(jq -c .$field <<<"$out")"
  fi
done

# ---- shape: all required keys present in every output ---------------------

echo
echo "shape:"
for repo in prisma-repo openapi-repo bare-repo; do
  out="$(run_against "$FIXTURES/$repo")"
  for key in has_migration_system migration_paths schema_files api_contract_files public_api_surfaces config_schemas warnings; do
    if jq -e "has(\"$key\")" <<<"$out" >/dev/null; then
      note_pass "$repo has key '$key'"
    else
      note_fail "$repo has key '$key'" "out=$out"
    fi
  done
done

echo
echo "Passed: $pass   Failed: $fail"
[[ "$fail" -eq 0 ]]
