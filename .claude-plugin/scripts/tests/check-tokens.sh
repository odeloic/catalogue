#!/usr/bin/env bash
#
# Drift guard for the shared design-system contract.
#
# The plugin vendors artifact/tokens.css from the catalogue-design-system
# Storybook. This checks the two are byte-identical so the artifact renderer and
# the component catalogue never drift on the foundation.
#
# The design-system repo lives in a separate checkout, so its path can't be
# hard-wired. The source tokens.css is resolved from, in order:
#   1. $DS_TOKENS_CSS (explicit path), or
#   2. the first existing candidate under common sibling locations.
# If none is found, skip cleanly (exit 0) — this is a dev-time guard, not CI.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_TOKENS="$SCRIPT_DIR/../artifact/tokens.css"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

candidates=(
  "${DS_TOKENS_CSS:-}"
  "$REPO_ROOT/../catalogue-design-system/src/tokens/tokens.css"
  "$REPO_ROOT/../design/catalogue-design-system/src/tokens/tokens.css"
  "$REPO_ROOT/../../design/catalogue-design-system/src/tokens/tokens.css"
)

SRC=""
for c in "${candidates[@]}"; do
  [ -n "$c" ] && [ -f "$c" ] || continue
  SRC="$c"; break
done

if [ -z "$SRC" ]; then
  echo "skip: design-system tokens.css not found (set DS_TOKENS_CSS to check drift)" >&2
  exit 0
fi

if diff -u "$SRC" "$PLUGIN_TOKENS" >/dev/null; then
  echo "ok: artifact/tokens.css matches $SRC"
  exit 0
fi

echo "DRIFT: $PLUGIN_TOKENS differs from the design system ($SRC)" >&2
diff -u "$SRC" "$PLUGIN_TOKENS" >&2 || true
echo "Re-vendor with: cp \"$SRC\" \"$PLUGIN_TOKENS\"" >&2
exit 1
