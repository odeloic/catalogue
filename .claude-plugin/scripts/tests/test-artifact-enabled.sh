#!/usr/bin/env bash
# Unit tests for artifact-enabled.sh. Uses temp CLAUDE_CONFIG_DIR /
# CLAUDE_PROJECT_DIR so real user/project settings never leak in.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/artifact-enabled.sh"

pass=0
fail=0

# Run the detector in a clean env and assert its exit code.
#   assert_exit <expected> <label> [ENV=VAL ...]
assert_exit() {
  local expected="$1" label="$2"
  shift 2
  local out rc
  out="$(env -i HOME="$TMP/home" PATH="$PATH" "$@" bash "$SCRIPT" 2>&1)"
  rc=$?
  if [ "$rc" -eq "$expected" ]; then
    echo "ok   - $label (exit $rc)"
    pass=$((pass + 1))
  else
    echo "FAIL - $label: expected exit $expected, got $rc"
    echo "       output: $out"
    fail=$((fail + 1))
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.claude" "$TMP/proj/.claude" "$TMP/empty"

CFG="CLAUDE_CONFIG_DIR=$TMP/home/.claude"
PROJ="CLAUDE_PROJECT_DIR=$TMP/proj"

# 1. Nothing set -> enabled.
assert_exit 0 "clean env is enabled" "$CFG" "$PROJ"

# 2. Env var disables.
assert_exit 1 "CLAUDE_CODE_DISABLE_ARTIFACT=1 disables" "$CFG" "$PROJ" CLAUDE_CODE_DISABLE_ARTIFACT=1
assert_exit 1 "CLAUDE_CODE_DISABLE_ARTIFACT=true disables" "$CFG" "$PROJ" CLAUDE_CODE_DISABLE_ARTIFACT=true
assert_exit 0 "CLAUDE_CODE_DISABLE_ARTIFACT=0 stays enabled" "$CFG" "$PROJ" CLAUDE_CODE_DISABLE_ARTIFACT=0

# 3. Nonessential-traffic env disables.
assert_exit 1 "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 disables" "$CFG" "$PROJ" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# 4. disableArtifact in project settings.
echo '{"disableArtifact": true}' >"$TMP/proj/.claude/settings.json"
assert_exit 1 "project disableArtifact:true disables" "$CFG" "$PROJ"
echo '{"disableArtifact": false}' >"$TMP/proj/.claude/settings.json"
assert_exit 0 "project disableArtifact:false stays enabled" "$CFG" "$PROJ"
rm -f "$TMP/proj/.claude/settings.json"

# 5. local settings outrank project settings.
echo '{"disableArtifact": true}' >"$TMP/proj/.claude/settings.json"
echo '{"disableArtifact": false}' >"$TMP/proj/.claude/settings.local.json"
assert_exit 0 "settings.local.json:false overrides settings.json:true" "$CFG" "$PROJ"
rm -f "$TMP/proj/.claude/settings.json" "$TMP/proj/.claude/settings.local.json"

# 6. disableArtifact in user settings.
echo '{"disableArtifact": true}' >"$TMP/home/.claude/settings.json"
assert_exit 1 "user disableArtifact:true disables" "$CFG" "$PROJ"
rm -f "$TMP/home/.claude/settings.json"

# 7. Artifact in permissions.deny.
echo '{"permissions": {"deny": ["Artifact"]}}' >"$TMP/proj/.claude/settings.json"
assert_exit 1 "permissions.deny [Artifact] disables" "$CFG" "$PROJ"
echo '{"permissions": {"deny": ["Bash(rm:*)", "WebFetch"]}}' >"$TMP/proj/.claude/settings.json"
assert_exit 0 "unrelated deny rules stay enabled" "$CFG" "$PROJ"
rm -f "$TMP/proj/.claude/settings.json"

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
