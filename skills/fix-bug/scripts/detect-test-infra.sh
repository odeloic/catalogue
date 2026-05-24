#!/usr/bin/env bash
#
# detect-test-infra.sh [target-dir]
#
# Scans a repo for test-infrastructure signals across major ecosystems and
# emits a single JSON document on stdout describing what was found, with what
# confidence, and from which evidence.
#
# Read-only. Does not run any test command, only inspects files.
#
# Detection sources, in order of preference:
#   package.json    -> jest, vitest, mocha, ava, playwright, cypress
#   pyproject.toml  -> pytest (also tox.ini, setup.cfg, pytest.ini)
#   go.mod          -> go test
#   Cargo.toml      -> cargo test
#   Gemfile         -> rspec, minitest
#   composer.json   -> phpunit, pest
#   mix.exs         -> exunit
#   CI configs      -> .github/workflows/*.yml, .gitlab-ci.yml (fallback)
#
# Output (success):
#   {
#     "exists": true,
#     "framework": "vitest",
#     "test_command": "pnpm test",
#     "single_test_command": "pnpm test -- <pattern>",
#     "test_dir": "src/__tests__",
#     "confidence": "high|medium|low",
#     "evidence": ["package.json:devDependencies.vitest", "..."]
#   }
#
# Output (nothing found):
#   { "exists": false, "evidence": [...] }
#
# Exit codes:
#   0  always — emits JSON either way; `exists` field reports the outcome.
#   1  missing dependency (jq) or fatal IO.
#
# Env:
#   DETECT_TEST_INFRA_DIR  Overrides target dir (alternative to positional arg).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

err() { printf '%s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required command: $1"; exit 1; }
}

require_cmd jq

TARGET="${1:-${DETECT_TEST_INFRA_DIR:-$PWD}}"
if [[ ! -d "$TARGET" ]]; then
  err "target directory not found: $TARGET"
  exit 1
fi
TARGET="$(cd -- "$TARGET" && pwd)"

EVIDENCE=()
add_evidence() { EVIDENCE+=("$1"); }

FRAMEWORK=""
TEST_COMMAND=""
SINGLE_TEST_COMMAND=""
TEST_DIR=""
CONFIDENCE=""

file_exists() { [[ -f "$TARGET/$1" ]]; }

# Highest-priority source wins: language manifests before CI fallbacks.

# ---- Node / package.json ---------------------------------------------------

detect_node() {
  local pkg="$TARGET/package.json"
  [[ -f "$pkg" ]] || return 1

  local has_test_script
  has_test_script="$(jq -r '.scripts.test // empty' "$pkg" 2>/dev/null || true)"

  local fw=""
  local fw_key=""
  for cand in vitest jest mocha ava playwright cypress; do
    local found
    found="$(jq -r --arg c "$cand" '
      (.devDependencies[$c] // .dependencies[$c] // empty)
    ' "$pkg" 2>/dev/null || true)"
    if [[ -n "$found" ]]; then
      fw="$cand"
      fw_key="$cand"
      add_evidence "package.json:devDependencies.$cand"
      break
    fi
  done

  if [[ -z "$fw" && -n "$has_test_script" ]]; then
    # Test script exists but no recognizable framework dep; infer from the
    # script text.
    case "$has_test_script" in
      *vitest*)    fw="vitest" ;;
      *jest*)      fw="jest" ;;
      *mocha*)     fw="mocha" ;;
      *ava*)       fw="ava" ;;
      *playwright*) fw="playwright" ;;
      *cypress*)   fw="cypress" ;;
    esac
    if [[ -n "$fw" ]]; then
      add_evidence "package.json:scripts.test (inferred $fw)"
    fi
  fi

  if [[ -z "$fw" ]]; then
    return 1
  fi

  FRAMEWORK="$fw"

  local pm="npm"
  if [[ -f "$TARGET/pnpm-lock.yaml" ]]; then pm="pnpm"
  elif [[ -f "$TARGET/yarn.lock" ]]; then pm="yarn"
  elif [[ -f "$TARGET/bun.lockb" || -f "$TARGET/bun.lock" ]]; then pm="bun"
  fi

  if [[ -n "$has_test_script" ]]; then
    TEST_COMMAND="$pm test"
    add_evidence "package.json:scripts.test"
  else
    TEST_COMMAND="npx $fw"
  fi

  case "$fw" in
    vitest)     SINGLE_TEST_COMMAND="$pm test -- <pattern>" ;;
    jest)       SINGLE_TEST_COMMAND="$pm test -- <pattern>" ;;
    mocha)      SINGLE_TEST_COMMAND="$pm test -- --grep <pattern>" ;;
    ava)        SINGLE_TEST_COMMAND="$pm test -- --match <pattern>" ;;
    playwright) SINGLE_TEST_COMMAND="npx playwright test <pattern>" ;;
    cypress)    SINGLE_TEST_COMMAND="npx cypress run --spec <pattern>" ;;
  esac

  for d in tests test __tests__ src/__tests__ src/tests spec e2e; do
    if [[ -d "$TARGET/$d" ]]; then
      TEST_DIR="$d"
      add_evidence "test_dir:$d"
      break
    fi
  done

  if [[ -n "$has_test_script" && -n "$fw_key" ]]; then
    CONFIDENCE="high"
  elif [[ -n "$fw_key" ]]; then
    CONFIDENCE="medium"
  else
    CONFIDENCE="low"
  fi
  return 0
}

# ---- Python ----------------------------------------------------------------

detect_python() {
  local found_any=0
  local fw=""

  if file_exists "pyproject.toml"; then
    if grep -q -E '(^|[^A-Za-z])pytest([^A-Za-z]|$)' "$TARGET/pyproject.toml" 2>/dev/null; then
      fw="pytest"
      add_evidence "pyproject.toml:pytest"
      found_any=1
    fi
  fi

  if [[ -z "$fw" ]] && file_exists "pytest.ini"; then
    fw="pytest"
    add_evidence "pytest.ini"
    found_any=1
  fi

  if [[ -z "$fw" ]] && file_exists "tox.ini"; then
    if grep -q "pytest" "$TARGET/tox.ini" 2>/dev/null; then
      fw="pytest"
      add_evidence "tox.ini:pytest"
      found_any=1
    fi
  fi

  if [[ -z "$fw" ]] && file_exists "setup.cfg"; then
    if grep -q "pytest" "$TARGET/setup.cfg" 2>/dev/null; then
      fw="pytest"
      add_evidence "setup.cfg:pytest"
      found_any=1
    fi
  fi

  if [[ -z "$fw" ]]; then
    # Fallback: a tests/ dir with test_*.py is a strong pytest signal even
    # without a config file.
    if [[ -d "$TARGET/tests" ]] && ls "$TARGET/tests"/test_*.py >/dev/null 2>&1; then
      fw="pytest"
      add_evidence "tests/test_*.py"
      found_any=1
    fi
  fi

  [[ $found_any -eq 1 ]] || return 1

  FRAMEWORK="$fw"
  TEST_COMMAND="pytest"
  SINGLE_TEST_COMMAND="pytest <path::test_name>"
  for d in tests test; do
    if [[ -d "$TARGET/$d" ]]; then TEST_DIR="$d"; add_evidence "test_dir:$d"; break; fi
  done
  CONFIDENCE="high"
  return 0
}

# ---- Go --------------------------------------------------------------------

detect_go() {
  file_exists "go.mod" || return 1
  add_evidence "go.mod"
  FRAMEWORK="go test"
  TEST_COMMAND="go test ./..."
  SINGLE_TEST_COMMAND="go test -run <TestName> ./<pkg>"
  CONFIDENCE="high"
  return 0
}

# ---- Rust ------------------------------------------------------------------

detect_rust() {
  file_exists "Cargo.toml" || return 1
  add_evidence "Cargo.toml"
  FRAMEWORK="cargo test"
  TEST_COMMAND="cargo test"
  SINGLE_TEST_COMMAND="cargo test <test_name>"
  if [[ -d "$TARGET/tests" ]]; then TEST_DIR="tests"; add_evidence "test_dir:tests"; fi
  CONFIDENCE="high"
  return 0
}

# ---- Ruby ------------------------------------------------------------------

detect_ruby() {
  file_exists "Gemfile" || return 1

  local fw=""
  if grep -q "rspec" "$TARGET/Gemfile" 2>/dev/null; then
    fw="rspec"
    add_evidence "Gemfile:rspec"
  elif grep -q "minitest" "$TARGET/Gemfile" 2>/dev/null; then
    fw="minitest"
    add_evidence "Gemfile:minitest"
  else
    return 1
  fi

  FRAMEWORK="$fw"
  case "$fw" in
    rspec)
      TEST_COMMAND="bundle exec rspec"
      SINGLE_TEST_COMMAND="bundle exec rspec <path>:<line>"
      [[ -d "$TARGET/spec" ]] && { TEST_DIR="spec"; add_evidence "test_dir:spec"; }
      ;;
    minitest)
      TEST_COMMAND="bundle exec rake test"
      SINGLE_TEST_COMMAND="bundle exec ruby -Itest <path> -n <test_name>"
      [[ -d "$TARGET/test" ]] && { TEST_DIR="test"; add_evidence "test_dir:test"; }
      ;;
  esac
  CONFIDENCE="high"
  return 0
}

# ---- PHP -------------------------------------------------------------------

detect_php() {
  file_exists "composer.json" || return 1
  local fw=""
  if jq -e '(.["require-dev"] // {}) | has("pestphp/pest")' "$TARGET/composer.json" >/dev/null 2>&1; then
    fw="pest"
    add_evidence "composer.json:require-dev.pestphp/pest"
  elif jq -e '(.["require-dev"] // {}) | has("phpunit/phpunit")' "$TARGET/composer.json" >/dev/null 2>&1; then
    fw="phpunit"
    add_evidence "composer.json:require-dev.phpunit/phpunit"
  else
    return 1
  fi
  FRAMEWORK="$fw"
  case "$fw" in
    pest)    TEST_COMMAND="./vendor/bin/pest";    SINGLE_TEST_COMMAND="./vendor/bin/pest --filter <name>" ;;
    phpunit) TEST_COMMAND="./vendor/bin/phpunit"; SINGLE_TEST_COMMAND="./vendor/bin/phpunit --filter <name>" ;;
  esac
  [[ -d "$TARGET/tests" ]] && { TEST_DIR="tests"; add_evidence "test_dir:tests"; }
  CONFIDENCE="high"
  return 0
}

# ---- Elixir ----------------------------------------------------------------

detect_elixir() {
  file_exists "mix.exs" || return 1
  add_evidence "mix.exs"
  FRAMEWORK="exunit"
  TEST_COMMAND="mix test"
  SINGLE_TEST_COMMAND="mix test <path>:<line>"
  [[ -d "$TARGET/test" ]] && { TEST_DIR="test"; add_evidence "test_dir:test"; }
  CONFIDENCE="high"
  return 0
}

# ---- CI fallback -----------------------------------------------------------

detect_ci() {
  local found=0 ci_cmd=""
  if [[ -d "$TARGET/.github/workflows" ]]; then
    for f in "$TARGET"/.github/workflows/*.yml "$TARGET"/.github/workflows/*.yaml; do
      [[ -f "$f" ]] || continue
      local line
      line="$(grep -E '^\s*(run|cmd):\s*.*(test|pytest|go test|cargo test|rspec|phpunit|pest|mix test)' "$f" 2>/dev/null | head -1 || true)"
      if [[ -n "$line" ]]; then
        ci_cmd="$(printf '%s' "$line" | sed -E 's/^\s*(run|cmd):\s*//; s/^["'\'']//; s/["'\'']$//')"
        add_evidence ".github/workflows/$(basename "$f")"
        found=1
        break
      fi
    done
  fi
  if [[ $found -eq 0 && -f "$TARGET/.gitlab-ci.yml" ]]; then
    local line
    line="$(grep -E '^\s*-?\s*(test|pytest|go test|cargo test|rspec|phpunit|pest|mix test)' "$TARGET/.gitlab-ci.yml" 2>/dev/null | head -1 || true)"
    if [[ -n "$line" ]]; then
      ci_cmd="$(printf '%s' "$line" | sed -E 's/^\s*-\s*//')"
      add_evidence ".gitlab-ci.yml"
      found=1
    fi
  fi
  [[ $found -eq 1 ]] || return 1

  FRAMEWORK="ci-inferred"
  TEST_COMMAND="$ci_cmd"
  SINGLE_TEST_COMMAND=""
  CONFIDENCE="low"
  return 0
}

# ---- Dispatch --------------------------------------------------------------

detect_node       \
  || detect_python \
  || detect_go     \
  || detect_rust   \
  || detect_ruby   \
  || detect_php    \
  || detect_elixir \
  || detect_ci     \
  || true

emit_evidence_json() {
  if [[ ${#EVIDENCE[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "${EVIDENCE[@]}" | jq -R . | jq -s .
  fi
}

EV_JSON="$(emit_evidence_json)"

if [[ -z "$FRAMEWORK" ]]; then
  jq -n --argjson evidence "$EV_JSON" '{ exists: false, evidence: $evidence }'
  exit 0
fi

jq -n \
  --arg framework "$FRAMEWORK" \
  --arg test_command "$TEST_COMMAND" \
  --arg single_test_command "$SINGLE_TEST_COMMAND" \
  --arg test_dir "$TEST_DIR" \
  --arg confidence "$CONFIDENCE" \
  --argjson evidence "$EV_JSON" \
  '{
    exists: true,
    framework: $framework,
    test_command: $test_command,
    single_test_command: (if $single_test_command == "" then null else $single_test_command end),
    test_dir: (if $test_dir == "" then null else $test_dir end),
    confidence: $confidence,
    evidence: $evidence
  }'
