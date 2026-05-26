#!/usr/bin/env bash
#
# extract-commit-style.sh [--limit N] [--fixture DIR]
#
# Reads the last N commits (default 50) from `git log` and emits a JSON
# document describing the repo's commit-message conventions. Read-only.
#
# Detects: prefix style (conventional / gitmoji / ticket / none), scope
# usage and common scopes, subject case, subject length stats, body usage,
# issue-reference pattern + location, trailers in use, confidence.
#
# Exit codes:
#   0  success — JSON on stdout
#   1  missing dependency (`jq` or `git`) or unreadable repo
#   2  fixture mode requested but fixture not found / malformed
#
# Env:
#   EXTRACT_STYLE_FIXTURE_DIR=<dir>  Same as --fixture <dir>. The fixture
#       dir must contain commits.txt. Each commit is a subject line followed
#       by an optional body; commits are separated by a line containing only
#       "---" (three dashes). Used by tests so no real git history is needed.
#   EXTRACT_STYLE_LIMIT=N            Same as --limit N.

set -euo pipefail

err() { printf '%s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required command: $1"; exit 1; }
}

# ---- args ------------------------------------------------------------------

LIMIT="${EXTRACT_STYLE_LIMIT:-50}"
FIXTURE_DIR="${EXTRACT_STYLE_FIXTURE_DIR:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="${2:?--limit requires a value}"; shift 2 ;;
    --limit=*) LIMIT="${1#*=}"; shift ;;
    --fixture) FIXTURE_DIR="${2:?--fixture requires a value}"; shift 2 ;;
    --fixture=*) FIXTURE_DIR="${1#*=}"; shift ;;
    -h|--help)
      sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) err "unknown arg: $1"; exit 1 ;;
  esac
done

require_cmd jq

# ---- load commits ----------------------------------------------------------
#
# Both paths populate two parallel arrays:
#   SUBJECTS[i]  — subject line of commit i
#   BODIES[i]    — full body (may be empty) of commit i, raw text
# And a single string TRAILERS_BLOB with all trailer lines concatenated,
# one per line, for trailer-key detection.

SUBJECTS=()
BODIES=()
TRAILERS_BLOB=""

# Use ASCII control characters as field/record separators since they can't
# appear in commit messages.
US=$'\x1f'  # unit (field) separator
RS=$'\x1e'  # record separator

load_from_git() {
  require_cmd git
  git rev-parse --git-dir >/dev/null 2>&1 || { err "not inside a git repository"; exit 1; }

  local raw
  raw="$(git log --no-merges -n "$LIMIT" --format="%s${US}%b${US}%(trailers:unfold,only)${RS}" 2>/dev/null || true)"

  if [[ -z "$raw" ]]; then
    return 0
  fi

  local rec subj body trailers
  while IFS= read -r -d "$RS" rec; do
    # Strip leading newline that git inserts between records.
    rec="${rec#$'\n'}"
    subj="${rec%%$US*}"
    rec="${rec#*$US}"
    body="${rec%%$US*}"
    trailers="${rec#*$US}"
    [[ -z "$subj" ]] && continue
    SUBJECTS+=("$subj")
    BODIES+=("$body")
    if [[ -n "$trailers" ]]; then
      TRAILERS_BLOB+="$trailers"$'\n'
    fi
  done <<<"$raw"
}

load_from_fixture() {
  local file="$FIXTURE_DIR/commits.txt"
  [[ -f "$file" ]] || { err "fixture not found: $file"; exit 2; }

  local subj="" body="" in_subject=1 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "---" ]]; then
      if [[ -n "$subj" ]]; then
        SUBJECTS+=("$subj")
        # Trim leading/trailing blank lines from body.
        body="${body#$'\n'}"
        body="${body%$'\n'}"
        BODIES+=("$body")
        # Pull trailer-shaped lines from the body for trailer detection.
        while IFS= read -r bline; do
          if [[ "$bline" =~ ^[A-Za-z][A-Za-z0-9-]+:[[:space:]] ]]; then
            TRAILERS_BLOB+="$bline"$'\n'
          fi
        done <<<"$body"
      fi
      subj=""; body=""; in_subject=1
      continue
    fi
    if (( in_subject )); then
      if [[ -n "$line" ]]; then
        subj="$line"
        in_subject=0
      fi
    else
      body+="$line"$'\n'
    fi
  done <"$file"

  # Flush the final commit (no trailing --- required).
  if [[ -n "$subj" ]]; then
    SUBJECTS+=("$subj")
    body="${body#$'\n'}"
    body="${body%$'\n'}"
    BODIES+=("$body")
    while IFS= read -r bline; do
      if [[ "$bline" =~ ^[A-Za-z][A-Za-z0-9-]+:[[:space:]] ]]; then
        TRAILERS_BLOB+="$bline"$'\n'
      fi
    done <<<"$body"
  fi

  # Cap by --limit just like git would.
  if (( ${#SUBJECTS[@]} > LIMIT )); then
    SUBJECTS=("${SUBJECTS[@]:0:LIMIT}")
    BODIES=("${BODIES[@]:0:LIMIT}")
  fi
}

if [[ -n "$FIXTURE_DIR" ]]; then
  load_from_fixture
else
  load_from_git
fi

SAMPLE=${#SUBJECTS[@]}

if (( SAMPLE == 0 )); then
  jq -n '{
    sample_size: 0,
    prefix_style: "none",
    prefix_examples: [],
    scope_used: false,
    common_scopes: [],
    subject_case: "lower",
    subject_median_length: 0,
    subject_max_length: 0,
    body_usage_pct: 0,
    issue_reference: {pattern: null, location: "none"},
    trailers: [],
    confidence: "low",
    recent_examples: []
  }'
  exit 0
fi

# ---- detection -------------------------------------------------------------

CONV_RE='^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)(\([^)]+\))?!?:'
GITMOJI_RE='^:[a-z_]+:'
TICKET_RE='^\[?[A-Z][A-Z0-9]+-[0-9]+\]?[: ]'

conv_count=0
gitmoji_count=0
ticket_count=0
scope_count=0
declare -a scopes=()
declare -a prefix_examples=()
# bash 3.2 has no associative arrays. Track seen prefixes as a delimited
# string: every recorded key is surrounded by NUL-safe sentinels "|key|".
prefix_seen_blob="|"

upper=0; lower=0; sentence=0
total_len=0
declare -a lengths=()
max_len=0

body_count=0

# bash 3.2: track per-location issue-ref counts as plain integers. The set
# of locations is fixed (subject/body/trailer).
issue_loc_subject=0
issue_loc_body=0
issue_loc_trailer=0
issue_patterns=()

for i in "${!SUBJECTS[@]}"; do
  s="${SUBJECTS[$i]}"
  b="${BODIES[$i]}"
  len=${#s}
  lengths+=("$len")
  total_len=$((total_len + len))
  (( len > max_len )) && max_len=$len

  # Prefix classification.
  if [[ "$s" =~ $CONV_RE ]]; then
    conv_count=$((conv_count+1))
    pfx="${BASH_REMATCH[1]}:"
    if [[ "$prefix_seen_blob" != *"|$pfx|"* ]]; then
      prefix_seen_blob="${prefix_seen_blob}${pfx}|"
      prefix_examples+=("$pfx")
    fi
    if [[ -n "${BASH_REMATCH[2]:-}" ]]; then
      scope_count=$((scope_count+1))
      sc="${BASH_REMATCH[2]}"
      sc="${sc#(}"; sc="${sc%)}"
      scopes+=("$sc")
    fi
  elif [[ "$s" =~ $GITMOJI_RE ]]; then
    gitmoji_count=$((gitmoji_count+1))
    pfx="$(printf '%s' "$s" | awk '{print $1}')"
    if [[ "$prefix_seen_blob" != *"|$pfx|"* ]]; then
      prefix_seen_blob="${prefix_seen_blob}${pfx}|"
      prefix_examples+=("$pfx")
    fi
  elif [[ "$s" =~ $TICKET_RE ]]; then
    ticket_count=$((ticket_count+1))
    pfx="$(printf '%s' "$s" | grep -oE '^\[?[A-Z][A-Z0-9]+-[0-9]+\]?' || true)"
    if [[ -n "$pfx" && "$prefix_seen_blob" != *"|$pfx|"* ]]; then
      prefix_seen_blob="${prefix_seen_blob}${pfx}|"
      prefix_examples+=("$pfx")
    fi
  fi

  # Case detection — examine the subject AFTER any prefix.
  meaningful="$s"
  if [[ "$s" =~ $CONV_RE ]]; then
    meaningful="${s#*: }"
  elif [[ "$s" =~ $TICKET_RE ]]; then
    meaningful="$(printf '%s' "$s" | sed -E 's/^\[?[A-Z][A-Z0-9]+-[0-9]+\]?[: ] *//')"
  elif [[ "$s" =~ $GITMOJI_RE ]]; then
    meaningful="$(printf '%s' "$s" | sed -E 's/^:[a-z_]+: *//')"
  fi
  first_word="$(printf '%s' "$meaningful" | awk '{print $1}')"
  if [[ -n "$first_word" ]]; then
    first_char="${first_word:0:1}"
    if [[ "$first_char" =~ [A-Z] ]]; then
      # Title vs sentence: title-case = most words capitalized.
      caps=0; words=0
      for w in $meaningful; do
        words=$((words+1))
        [[ "${w:0:1}" =~ [A-Z] ]] && caps=$((caps+1))
      done
      if (( words >= 3 && caps * 2 > words )); then
        upper=$((upper+1))
      else
        sentence=$((sentence+1))
      fi
    elif [[ "$first_char" =~ [a-z] ]]; then
      lower=$((lower+1))
    fi
  fi

  # Body usage.
  body_trim="$(printf '%s' "$b" | tr -d '[:space:]')"
  if [[ -n "$body_trim" ]]; then
    body_count=$((body_count+1))
  fi

  # Issue references. Order matters — first match wins per commit.
  for hay_label in "subject:$s" "body:$b"; do
    loc="${hay_label%%:*}"
    hay="${hay_label#*:}"
    [[ -z "$hay" ]] && continue
    found=""
    if [[ "$hay" =~ (Closes|Fixes|Resolves|Refs|Ref|Related)[[:space:]]+\#?([A-Z][A-Z0-9]*-?[0-9]+) ]]; then
      kw="${BASH_REMATCH[1]}"
      ref="${BASH_REMATCH[2]}"
      if [[ "$ref" =~ ^[A-Z]+-[0-9]+$ ]]; then
        prefix="${ref%-*}"
        found="$kw $prefix-\\d+"
      else
        found="$kw #\\d+"
      fi
    elif [[ "$hay" =~ \#([0-9]+) ]]; then
      found="#\\d+"
    elif [[ "$hay" =~ ([A-Z][A-Z0-9]+-[0-9]+) ]]; then
      ref="${BASH_REMATCH[1]}"
      prefix="${ref%-*}"
      found="$prefix-\\d+"
    fi
    if [[ -n "$found" ]]; then
      issue_patterns+=("$found")
      # If the match came from a trailer-shaped line, label as trailer.
      if [[ "$loc" == "body" ]]; then
        # Check the body line that produced the match.
        while IFS= read -r bl; do
          if [[ "$bl" =~ ^(Closes|Fixes|Resolves|Refs|Ref|Related)[[:space:]] ]]; then
            loc="trailer"
            break
          fi
        done <<<"$b"
      fi
      case "$loc" in
        subject) issue_loc_subject=$((issue_loc_subject + 1)) ;;
        body)    issue_loc_body=$((issue_loc_body + 1)) ;;
        trailer) issue_loc_trailer=$((issue_loc_trailer + 1)) ;;
      esac
      break
    fi
  done
done

# ---- dominant prefix style -------------------------------------------------

dominant="none"; dominant_count=0
if (( conv_count > dominant_count )); then dominant="conventional"; dominant_count=$conv_count; fi
if (( gitmoji_count > dominant_count )); then dominant="gitmoji"; dominant_count=$gitmoji_count; fi
if (( ticket_count > dominant_count )); then dominant="ticket"; dominant_count=$ticket_count; fi

# If no prefix style hits >= 50% of sample, call it "none".
threshold=$(( (SAMPLE + 1) / 2 ))
if (( dominant_count < threshold )); then
  dominant="none"
fi

# ---- subject case ----------------------------------------------------------

subject_case="lower"
if (( upper >= lower && upper >= sentence )); then
  subject_case="title"
elif (( sentence >= lower )); then
  subject_case="sentence"
fi

# ---- length stats ----------------------------------------------------------

# Median.
sorted="$(printf '%s\n' "${lengths[@]}" | sort -n)"
mid_idx=$(( SAMPLE / 2 ))
if (( SAMPLE % 2 == 1 )); then
  median="$(printf '%s\n' "$sorted" | sed -n "$((mid_idx + 1))p")"
else
  a="$(printf '%s\n' "$sorted" | sed -n "${mid_idx}p")"
  b="$(printf '%s\n' "$sorted" | sed -n "$((mid_idx + 1))p")"
  median=$(( (a + b) / 2 ))
fi

# ---- body usage ------------------------------------------------------------

body_pct=$(( body_count * 100 / SAMPLE ))

# ---- scopes ----------------------------------------------------------------

scope_used="false"
common_scopes_json="[]"
if (( scope_count > 0 )); then
  scope_used="true"
  common_scopes_json="$(
    printf '%s\n' "${scopes[@]}" \
      | sort | uniq -c | sort -rn | head -10 \
      | awk '{$1=""; sub(/^ /,""); print}' \
      | jq -R . | jq -s .
  )"
fi

# ---- trailers --------------------------------------------------------------

trailers_json="[]"
if [[ -n "$TRAILERS_BLOB" ]]; then
  trailers_json="$(
    printf '%s' "$TRAILERS_BLOB" \
      | grep -oE '^[A-Za-z][A-Za-z0-9-]+:' \
      | sed 's/:$//' \
      | sort -u \
      | jq -R . | jq -s .
  )" || trailers_json="[]"
fi

# ---- issue reference -------------------------------------------------------

issue_pattern="null"
issue_location="none"
if (( ${#issue_patterns[@]} > 0 )); then
  issue_pattern="$(printf '%s\n' "${issue_patterns[@]}" | sort | uniq -c | sort -rn | head -1 | awk '{$1=""; sub(/^ /,""); print}')"
  # Pick most common location (bash 3.2: iterate fixed key set).
  best_loc_count=0
  for loc in subject body trailer; do
    case "$loc" in
      subject) c=$issue_loc_subject ;;
      body)    c=$issue_loc_body ;;
      trailer) c=$issue_loc_trailer ;;
    esac
    if (( c > best_loc_count )); then
      best_loc_count=$c
      issue_location="$loc"
    fi
  done
fi

# ---- confidence ------------------------------------------------------------

confidence="low"
if [[ "$dominant" != "none" ]]; then
  pct=$(( dominant_count * 100 / SAMPLE ))
  if (( SAMPLE >= 30 && pct >= 80 )); then
    confidence="high"
  elif (( SAMPLE >= 10 && pct >= 60 )); then
    confidence="medium"
  fi
fi

# ---- recent examples -------------------------------------------------------

examples_json="$(
  printf '%s\n' "${SUBJECTS[@]:0:5}" | jq -R . | jq -s .
)"

prefix_examples_json="$(
  if (( ${#prefix_examples[@]} > 0 )); then
    printf '%s\n' "${prefix_examples[@]:0:10}" | jq -R . | jq -s .
  else
    echo '[]'
  fi
)"

# ---- emit ------------------------------------------------------------------

jq -n \
  --argjson sample "$SAMPLE" \
  --arg style "$dominant" \
  --argjson prefix_examples "$prefix_examples_json" \
  --argjson scope_used "$scope_used" \
  --argjson common_scopes "$common_scopes_json" \
  --arg case "$subject_case" \
  --argjson median "$median" \
  --argjson max "$max_len" \
  --argjson body_pct "$body_pct" \
  --arg issue_pattern "$issue_pattern" \
  --arg issue_location "$issue_location" \
  --argjson trailers "$trailers_json" \
  --arg confidence "$confidence" \
  --argjson examples "$examples_json" \
  '{
    sample_size: $sample,
    prefix_style: $style,
    prefix_examples: $prefix_examples,
    scope_used: $scope_used,
    common_scopes: $common_scopes,
    subject_case: $case,
    subject_median_length: $median,
    subject_max_length: $max,
    body_usage_pct: $body_pct,
    issue_reference: {
      pattern: (if $issue_pattern == "null" then null else $issue_pattern end),
      location: $issue_location
    },
    trailers: $trailers,
    confidence: $confidence,
    recent_examples: $examples
  }'
