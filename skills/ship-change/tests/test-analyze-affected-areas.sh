#!/usr/bin/env bash
#
# Asserts on the JSON shape and plausibility of hit counts returned by
# analyze-affected-areas.sh when run against this repo with known keywords.
#
# Run from the repo root:
#   bash skills/ship-change/tests/test-analyze-affected-areas.sh

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ANALYZE="$SKILL_DIR/scripts/analyze-affected-areas.sh"
REPO_ROOT="$(git -C "$SKILL_DIR" rev-parse --show-toplevel)"

pass=0; fail=0

note_pass() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
note_fail() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; if [[ -n "${2:-}" ]]; then printf '         %s\n' "$2"; fi; }

# ---- usage error on no args ------------------------------------------------

out=""
code=0
out="$("$ANALYZE" 2>&1)" || code=$?
if [[ "$code" -eq 2 ]]; then
  note_pass "no args -> exit 2"
else
  note_fail "no args -> exit 2" "got exit=$code, out=$out"
fi

# ---- shape: known keyword from this repo ----------------------------------

# Use a keyword guaranteed to exist multiple times in this repo.
out="$(AFFECTED_REPO_ROOT="$REPO_ROOT" "$ANALYZE" triage 2>&1)" || {
  note_fail "analyze runs cleanly with known keyword" "$out"
}

# Validate top-level shape.
for key in keywords matches top_directories exclusions_applied; do
  if jq -e "has(\"$key\")" <<<"$out" >/dev/null 2>&1; then
    note_pass "JSON has key '$key'"
  else
    note_fail "JSON has key '$key'" "out=$out"
  fi
done

# keywords echoed back correctly.
echoed="$(jq -r '.keywords | join(",")' <<<"$out")"
if [[ "$echoed" == "triage" ]]; then
  note_pass "keywords echoed back"
else
  note_fail "keywords echoed back" "got='$echoed'"
fi

# matches array has entries (we know the keyword exists in this repo).
matches_len="$(jq '.matches | length' <<<"$out")"
if [[ "$matches_len" -ge 1 ]]; then
  note_pass "matches has >=1 entry for known keyword"
else
  note_fail "matches has >=1 entry for known keyword" "matches_len=$matches_len"
fi

# Each match entry has the expected shape.
shape_ok="$(jq '
  [.matches[] | (has("directory") and has("files") and has("total_hits"))]
  | all
' <<<"$out")"
if [[ "$shape_ok" == "true" ]]; then
  note_pass "every match has directory/files/total_hits"
else
  note_fail "every match has directory/files/total_hits"
fi

# Files within each match have path + hits, hits is a positive int.
files_shape_ok="$(jq '
  [.matches[].files[] | (has("path") and has("hits") and (.hits | type == "number") and (.hits > 0))]
  | all
' <<<"$out")"
if [[ "$files_shape_ok" == "true" ]]; then
  note_pass "every file entry has path/hits and hits > 0"
else
  note_fail "every file entry has path/hits and hits > 0"
fi

# top_directories is consistent with matches (same order, same dirs).
consistent="$(jq '
  (.top_directories) == (.matches | map(.directory))
' <<<"$out")"
if [[ "$consistent" == "true" ]]; then
  note_pass "top_directories matches matches[].directory order"
else
  note_fail "top_directories matches matches[].directory order"
fi

# matches sorted by total_hits descending.
sorted_ok="$(jq '
  (.matches | map(.total_hits)) as $h
  | ($h == ($h | sort | reverse))
' <<<"$out")"
if [[ "$sorted_ok" == "true" ]]; then
  note_pass "matches sorted by total_hits desc"
else
  note_fail "matches sorted by total_hits desc"
fi

# ---- hit count plausibility ------------------------------------------------
# 'triage' appears in skills/triage at high frequency, so the triage directory
# (or one of its subdirs) should be in the top directories.
has_triage="$(jq '[.top_directories[] | test("skills/triage")] | any' <<<"$out")"
if [[ "$has_triage" == "true" ]]; then
  note_pass "top_directories includes skills/triage*"
else
  note_fail "top_directories includes skills/triage*" "top=$(jq -c .top_directories <<<"$out")"
fi

# ---- multiple keywords -----------------------------------------------------

out_multi="$(AFFECTED_REPO_ROOT="$REPO_ROOT" "$ANALYZE" triage SKILL 2>&1)" || {
  note_fail "analyze runs cleanly with multiple keywords" "$out_multi"
}
keys_multi="$(jq -r '.keywords | join(",")' <<<"$out_multi")"
if [[ "$keys_multi" == "triage,SKILL" ]]; then
  note_pass "multiple keywords echoed back"
else
  note_fail "multiple keywords echoed back" "got='$keys_multi'"
fi

# Multi-keyword search should find at least as many matches as the
# single-keyword variant (it's a superset query).
multi_len="$(jq '.matches | length' <<<"$out_multi")"
if [[ "$multi_len" -ge "$matches_len" ]]; then
  note_pass "multi-keyword finds >= single-keyword"
else
  note_fail "multi-keyword finds >= single-keyword" "single=$matches_len multi=$multi_len"
fi

# ---- zero-hit case ---------------------------------------------------------
# Build the sentinel from parts so it never appears literally in this file.
SENTINEL="$(printf '%s%s%s' "QQ" "X__no_match__" "WW$$")"
out_zero="$(AFFECTED_REPO_ROOT="$REPO_ROOT" "$ANALYZE" "$SENTINEL" 2>&1)" || {
  note_fail "zero-hit keyword still exits 0" "$out_zero"
}
zero_len="$(jq '.matches | length' <<<"$out_zero")"
if [[ "$zero_len" -eq 0 ]]; then
  note_pass "zero-hit keyword returns empty matches"
else
  note_fail "zero-hit keyword returns empty matches" "len=$zero_len, out=$out_zero"
fi

# ---- top-N override --------------------------------------------------------

out_topn="$(AFFECTED_TOP_N=2 AFFECTED_REPO_ROOT="$REPO_ROOT" "$ANALYZE" triage SKILL 2>&1)" || {
  note_fail "AFFECTED_TOP_N=2 honored" "$out_topn"
}
topn_len="$(jq '.matches | length' <<<"$out_topn")"
if [[ "$topn_len" -le 2 ]]; then
  note_pass "AFFECTED_TOP_N=2 caps matches"
else
  note_fail "AFFECTED_TOP_N=2 caps matches" "len=$topn_len"
fi

echo
echo "Passed: $pass   Failed: $fail"
[[ "$fail" -eq 0 ]]
