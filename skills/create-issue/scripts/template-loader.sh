#!/usr/bin/env bash
#
# template-loader.sh <type> <tracker>
#
# Prints the markdown template for a given issue type and tracker to stdout.
# Thin shim around references/templates/<type>-<tracker>.md so downstream
# callers don't re-implement the lookup.
#
# Exit codes:
#   0  success — template on stdout
#   1  invalid argument or missing template file (message on stderr)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

err() { printf '%s\n' "$*" >&2; }

if [[ $# -ne 2 ]]; then
  err "usage: template-loader.sh <type> <tracker>"
  err "  type    : bug | feature | improvement | change"
  err "  tracker : github | gitlab | linear"
  exit 1
fi

TYPE="$1"
TRACKER="$2"

case "$TYPE" in
  bug|feature|improvement|change) ;;
  *) err "invalid type: $TYPE (expected: bug | feature | improvement | change)"; exit 1 ;;
esac

case "$TRACKER" in
  github|gitlab|linear) ;;
  *) err "invalid tracker: $TRACKER (expected: github | gitlab | linear)"; exit 1 ;;
esac

TEMPLATE="$SKILL_DIR/references/templates/$TYPE-$TRACKER.md"

if [[ ! -f "$TEMPLATE" ]]; then
  err "template file not found: $TEMPLATE"
  exit 1
fi

cat "$TEMPLATE"
