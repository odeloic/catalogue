#!/usr/bin/env bash
#
# render-mermaid.sh <diagram-source-file> [--title "..."] [--explanation "..."]
#
# Reads a .mmd diagram source, wraps it in the single-file HTML template
# (references/html-template.html) with mermaid.js from CDN, and prints the
# resulting HTML to stdout.
#
# Title defaults to "Codebase Explanation". Explanation defaults to empty.
# Title and explanation are HTML-escaped before injection.
#
# Exit codes:
#   0  success — HTML on stdout
#   1  missing source file, template not found, or bad usage

set -euo pipefail

err() { printf '%s\n' "$*" >&2; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$SKILL_DIR/references/html-template.html"

SOURCE_FILE=""
TITLE="Codebase Explanation"
EXPLANATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      shift; TITLE="${1:-}"; shift
      ;;
    --explanation)
      shift; EXPLANATION="${1:-}"; shift
      ;;
    --help|-h)
      err "usage: render-mermaid.sh <diagram-source-file> [--title \"...\"] [--explanation \"...\"]"
      exit 0
      ;;
    *)
      if [[ -z "$SOURCE_FILE" ]]; then
        SOURCE_FILE="$1"; shift
      else
        err "unexpected argument: $1"
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$SOURCE_FILE" ]]; then
  err "usage: render-mermaid.sh <diagram-source-file> [--title \"...\"] [--explanation \"...\"]"
  exit 1
fi

if [[ ! -f "$SOURCE_FILE" ]]; then
  err "diagram source file not found: $SOURCE_FILE"
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  err "html template not found: $TEMPLATE"
  exit 1
fi

DIAGRAM_SOURCE="$(cat "$SOURCE_FILE")"

html_escape() {
  python3 - "$1" <<'PY' 2>/dev/null || printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
import sys, html
print(html.escape(sys.argv[1]), end='')
PY
}

ESC_TITLE="$(html_escape "$TITLE")"
ESC_EXPLANATION="$(html_escape "$EXPLANATION")"

# Diagram source must NOT be HTML-escaped — mermaid.js parses raw text inside
# <pre class="mermaid">. But we do need to be careful with the substitution:
# write each value to a temp file and use awk to inject so shell metacharacters
# in the values don't break anything.

TMPDIR_OUT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_OUT"' EXIT
printf '%s' "$ESC_TITLE"       > "$TMPDIR_OUT/title"
printf '%s' "$ESC_EXPLANATION" > "$TMPDIR_OUT/explanation"
printf '%s' "$DIAGRAM_SOURCE"  > "$TMPDIR_OUT/diagram"

awk -v title_file="$TMPDIR_OUT/title" \
    -v expl_file="$TMPDIR_OUT/explanation" \
    -v diag_file="$TMPDIR_OUT/diagram" '
  function slurp(f,    line, out) {
    out = ""
    while ((getline line < f) > 0) {
      out = (out == "" ? line : out "\n" line)
    }
    close(f)
    return out
  }
  BEGIN {
    TITLE = slurp(title_file)
    EXPL  = slurp(expl_file)
    DIAG  = slurp(diag_file)
  }
  {
    line = $0
    gsub(/\{\{TITLE\}\}/, TITLE, line)
    gsub(/\{\{EXPLANATION_HTML\}\}/, EXPL, line)
    # Diagram source goes in last because it can be multi-line.
    if (index(line, "{{DIAGRAM_SOURCE}}") > 0) {
      n = index(line, "{{DIAGRAM_SOURCE}}")
      print substr(line, 1, n-1) DIAG substr(line, n + length("{{DIAGRAM_SOURCE}}"))
    } else {
      print line
    }
  }
' "$TEMPLATE"
