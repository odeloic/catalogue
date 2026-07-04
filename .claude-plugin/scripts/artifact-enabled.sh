#!/usr/bin/env bash
# Detect whether Claude Code's native Artifact publishing is available for the
# current session. Mirrors the disable knobs documented at
# https://code.claude.com/docs/en/artifacts#disable-artifacts
#
#   exit 0  -> native artifacts available; render via the Artifact tool guided
#              by the built-in `artifact-design` skill.
#   exit 1  -> native artifacts disabled; skills fall back to render-artifact.py.
#
# A human-readable reason is always printed to stderr. Settings-file locations
# honour CLAUDE_CONFIG_DIR (user) and CLAUDE_PROJECT_DIR (project) so the script
# is testable and matches Claude Code's own resolution.

set -euo pipefail

is_truthy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

# 1. Environment variables ---------------------------------------------------
if is_truthy "${CLAUDE_CODE_DISABLE_ARTIFACT:-}"; then
  echo "disabled: CLAUDE_CODE_DISABLE_ARTIFACT is set" >&2
  exit 1
fi
if is_truthy "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"; then
  echo "disabled: CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC is set" >&2
  exit 1
fi

# 2. Settings files, highest precedence first --------------------------------
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
settings_files=(
  "/etc/claude-code/managed-settings.json"
  "/Library/Application Support/ClaudeCode/managed-settings.json"
  "$project_dir/.claude/settings.local.json"
  "$project_dir/.claude/settings.json"
  "$config_dir/settings.json"
)

if command -v jq >/dev/null 2>&1; then
  # `disableArtifact` is a scalar: the highest-precedence file that defines it
  # wins. Stop at the first definition either way.
  for f in "${settings_files[@]}"; do
    [ -f "$f" ] || continue
    val="$(jq -r 'if has("disableArtifact") then (.disableArtifact | tostring) else "null" end' "$f" 2>/dev/null || echo null)"
    if [ "$val" = "true" ]; then
      echo "disabled: \"disableArtifact\": true in $f" >&2
      exit 1
    elif [ "$val" = "false" ]; then
      break
    fi
  done

  # `permissions.deny` merges across levels: an Artifact deny at any level wins.
  for f in "${settings_files[@]}"; do
    [ -f "$f" ] || continue
    if jq -e '((.permissions.deny // [])[] | select(. == "Artifact" or startswith("Artifact(")))' "$f" >/dev/null 2>&1; then
      echo "disabled: Artifact is denied in permissions.deny in $f" >&2
      exit 1
    fi
  done
else
  echo "note: jq not found; skipped settings-file checks" >&2
fi

echo "enabled: native Artifact publishing available" >&2
exit 0
