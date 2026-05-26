#!/usr/bin/env bash
#
# investigate.sh <keyword> [keyword...]
#
# Ranked, read-only repo search. Emits JSON on stdout matching the shape
# documented in the skill spec. Uses ripgrep, respects .gitignore, and excludes
# common vendor/build directories.
#
# Per-file score = 3 * definitions + 1 * references.
# Definitions are detected by line patterns like `function NAME`, `class NAME`,
# `def NAME`, `const NAME`, `let NAME`, `var NAME`, `interface NAME`,
# `type NAME`, `NAME =`, and top-level `NAME:` (TS/JS object keys).
#
# Exit codes:
#   0  success — JSON on stdout (use total_hits / ranked_files for status)
#   1  ripgrep not installed
#   2  no keywords passed
#
# Env:
#   INVESTIGATE_FIXTURE_ROOT=<dir>  Run rg under this directory instead of the
#                                   cwd. Used by tests.

set -euo pipefail

err() { printf '%s\n' "$*" >&2; }

if ! command -v rg >/dev/null 2>&1; then
  err "ripgrep (rg) is required but not installed."
  err "Install: brew install ripgrep   |   apt-get install ripgrep   |   cargo install ripgrep"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but not installed."
  err "Install: brew install jq   |   apt-get install jq"
  exit 1
fi

if [[ $# -lt 1 ]]; then
  err "usage: investigate.sh <keyword> [keyword...]"
  exit 2
fi

KEYWORDS=("$@")

EXCLUSIONS=(node_modules dist build .next vendor __pycache__ target .venv coverage .git)

ROOT="${INVESTIGATE_FIXTURE_ROOT:-.}"

# Build rg args.
RG_ARGS=(--no-messages --no-heading --line-number --color never --ignore-case)
for ex in "${EXCLUSIONS[@]}"; do
  RG_ARGS+=(--glob "!${ex}" --glob "!**/${ex}/**")
done

# Build a single regex of alternatives, word-bounded.
build_pattern() {
  local alts="" k
  for k in "${KEYWORDS[@]}"; do
    # Escape regex specials for safety; users may pass plain identifiers but
    # tolerate punctuation just in case.
    local esc
    esc="$(printf '%s' "$k" | sed -e 's/[\/&]/\\&/g' -e 's/[.[\*^$()+?{}|]/\\&/g')"
    if [[ -z "$alts" ]]; then alts="$esc"; else alts="$alts|$esc"; fi
  done
  printf '\\b(%s)\\b' "$alts"
}

PATTERN="$(build_pattern)"

# ---- run rg and time it ----------------------------------------------------

START_MS=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || date +%s000)

# Stream rg results; tolerate exit code 1 (no matches).
RG_OUT="$(rg "${RG_ARGS[@]}" -e "$PATTERN" "$ROOT" 2>/dev/null || true)"

END_MS=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || date +%s000)
DURATION_MS=$((END_MS - START_MS))

# ---- empty result short-circuit --------------------------------------------

if [[ -z "$RG_OUT" ]]; then
  # Build keyword variation suggestions.
  SUGGESTIONS=()
  for k in "${KEYWORDS[@]}"; do
    # singular/plural toggle
    if [[ "$k" == *s ]] && [[ "${#k}" -gt 2 ]]; then
      SUGGESTIONS+=("${k%s}")
    else
      SUGGESTIONS+=("${k}s")
    fi
    # snake/camel toggle (cheap heuristic)
    if [[ "$k" == *_* ]]; then
      cc="$(printf '%s' "$k" | awk -F_ '{ out=$1; for (i=2;i<=NF;i++) out=out toupper(substr($i,1,1)) substr($i,2); print out }')"
      SUGGESTIONS+=("$cc")
    elif [[ "$k" =~ [a-z][A-Z] ]]; then
      sc="$(printf '%s' "$k" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')"
      SUGGESTIONS+=("$sc")
    fi
  done
  # Dedupe + cap at 3. (bash 3.2 compatible — no mapfile)
  _dedup_input="$(printf '%s\n' "${SUGGESTIONS[@]}" | awk '!seen[$0]++' | head -n 3)"
  SUGGESTIONS=()
  while IFS= read -r _s; do
    [[ -n "$_s" ]] && SUGGESTIONS+=("$_s")
  done <<<"$_dedup_input"
  unset _dedup_input _s

  jq -n \
    --argjson keywords "$(printf '%s\n' "${KEYWORDS[@]}" | jq -R . | jq -s .)" \
    --argjson suggestions "$(printf '%s\n' "${SUGGESTIONS[@]}" | jq -R . | jq -s .)" \
    --argjson exclusions "$(printf '%s\n' "${EXCLUSIONS[@]}" | jq -R . | jq -s .)" \
    --argjson duration "$DURATION_MS" \
    '{
      keywords: $keywords,
      total_hits: 0,
      ranked_files: [],
      top_directories: [],
      exclusions_applied: $exclusions,
      search_duration_ms: $duration,
      suggestions: $suggestions
    }'
  exit 0
fi

# ---- score in awk ----------------------------------------------------------

# Pipe rg output (path:line:content) into awk. Build per-file counters and
# capture the first few match line numbers.
#
# Definition detection: a line is a "definition" of one of the keywords if any
# of the patterns below matches. Otherwise it's a "reference".

# Build a regex of plain keyword alternatives for awk (no word boundaries —
# we'll check those in awk against context).
AWK_KEYS="$(printf '%s\n' "${KEYWORDS[@]}" | paste -sd'|' -)"

# Strip the leading ROOT/ prefix from paths so output is repo-relative.
ROOT_PREFIX="$ROOT/"

SCORED_JSON="$(printf '%s\n' "$RG_OUT" | awk -F: -v keys="$AWK_KEYS" -v root_prefix="$ROOT_PREFIX" '
  BEGIN {
    # Definition signal patterns (POSIX ERE — no \< / \> word anchors, those
    # are GNU-only). We bound with explicit non-identifier classes.
    # WB = trailing word boundary (non-identifier char or EOL).
    WB = "($|[^a-z0-9_])"
    LB = "(^|[^a-z0-9_])"
    # Strong (type-level / function-level) definitions count for more than
    # weak (const/let/var binding) definitions, so a file that *defines* the
    # symbol outranks a file that just binds a local variable of the same
    # name. Strong = 10, weak = 3, reference = 1.
    n_strong = 7
    strong[1] = "function[ \t]+KW" WB
    strong[2] = "class[ \t]+KW" WB
    strong[3] = "def[ \t]+KW" WB
    strong[4] = "interface[ \t]+KW" WB
    strong[5] = "type[ \t]+KW" WB
    strong[6] = "fn[ \t]+KW" WB
    strong[7] = "struct[ \t]+KW" WB
    n_weak = 4
    weak[1] = "const[ \t]+KW" WB
    weak[2] = "let[ \t]+KW" WB
    weak[3] = "var[ \t]+KW" WB
    weak[4] = "^[ \t]*KW[ \t]*:"

    split(keys, kw_arr, "|")
  }
  {
    path  = $1
    lineno = $2
    # Reconstruct the content (it may contain colons).
    content = ""
    for (i = 3; i <= NF; i++) {
      content = content (i == 3 ? "" : ":") $i
    }

    # Normalize path to repo-relative.
    if (index(path, root_prefix) == 1) {
      path = substr(path, length(root_prefix) + 1)
    }

    # Lowercase content + keywords for case-insensitive definition matching.
    lc_content = tolower(content)

    # Classify hit as strong-def / weak-def / reference.
    hit_kind = "ref"
    for (ki in kw_arr) {
      kw = tolower(kw_arr[ki])
      if (match(lc_content, "(^|[^a-z0-9_])" kw "([^a-z0-9_]|$)") == 0) continue
      for (di = 1; di <= n_strong; di++) {
        pat = strong[di]; gsub("KW", kw, pat)
        if (match(lc_content, pat)) { hit_kind = "strong"; break }
      }
      if (hit_kind == "strong") break
      for (di = 1; di <= n_weak; di++) {
        pat = weak[di]; gsub("KW", kw, pat)
        if (match(lc_content, pat)) { hit_kind = "weak"; break }
      }
      if (hit_kind != "ref") break
    }

    if (hit_kind == "strong")     strong_count[path]++
    else if (hit_kind == "weak")  weak_count[path]++
    else                          refs_count[path]++
    total_hits++

    # Collect up to 8 match lines per file.
    if (lines_count[path] < 8) {
      if (path in match_lines) match_lines[path] = match_lines[path] "," lineno
      else                    match_lines[path] = lineno
      lines_count[path]++
    }

    # Track top-level directory.
    top = path
    if (index(top, "/") > 0) sub(/\/.*$/, "", top)
    else                     top = "."
    dir_files_seen[top "|" path] = 1
    dir_hits[top]++
  }
  END {
    printf "{\n"
    printf "  \"total_hits\": %d,\n", total_hits

    # Files
    printf "  \"files\": [\n"
    first = 1
    for (p in lines_count) {
      s = (p in strong_count) ? strong_count[p] : 0
      w = (p in weak_count)   ? weak_count[p]   : 0
      r = (p in refs_count)   ? refs_count[p]   : 0
      d = s + w
      score = 10 * s + 3 * w + r
      if (!first) printf ",\n"
      first = 0
      # Convert match_lines CSV to JSON array.
      lines = match_lines[p]
      n = split(lines, lns, ",")
      ml = "["
      for (i = 1; i <= n; i++) {
        ml = ml (i == 1 ? "" : ",") lns[i]
      }
      ml = ml "]"
      gsub(/\\/, "\\\\", p)
      gsub(/"/, "\\\"", p)
      printf "    {\"path\": \"%s\", \"score\": %d, \"definitions\": %d, \"references\": %d, \"match_lines\": %s}", p, score, d, r, ml
    }
    printf "\n  ],\n"

    # Top directories
    printf "  \"dirs\": [\n"
    first = 1
    # Compute file_count per top.
    for (key in dir_files_seen) {
      split(key, kp, "|")
      dir_filecount[kp[1]]++
    }
    for (d in dir_hits) {
      if (!first) printf ",\n"
      first = 0
      fc = (d in dir_filecount) ? dir_filecount[d] : 0
      dd = d
      gsub(/\\/, "\\\\", dd)
      gsub(/"/, "\\\"", dd)
      printf "    {\"path\": \"%s\", \"file_count\": %d, \"total_hits\": %d}", dd, fc, dir_hits[d]
    }
    printf "\n  ]\n"
    printf "}\n"
  }
')"

# ---- finalize with jq: sort, slice, attach metadata ------------------------

jq -n \
  --argjson scored "$SCORED_JSON" \
  --argjson keywords "$(printf '%s\n' "${KEYWORDS[@]}" | jq -R . | jq -s .)" \
  --argjson exclusions "$(printf '%s\n' "${EXCLUSIONS[@]}" | jq -R . | jq -s .)" \
  --argjson duration "$DURATION_MS" \
  '{
    keywords: $keywords,
    total_hits: $scored.total_hits,
    ranked_files: ($scored.files | sort_by(-.score, -.references, .path)),
    top_directories: ($scored.dirs | sort_by(-.total_hits, .path)),
    exclusions_applied: $exclusions,
    search_duration_ms: $duration
  }'
