#!/usr/bin/env bash
#
# detect-migration-needs.sh
#
# Scans the repo for files / directories that signal the change might touch
# durable contracts: database schemas, API contracts, public type surfaces,
# and config schemas. Emits JSON describing what was found and a list of
# warnings the agent should consider when writing the plan.
#
# Strictly read-only.
#
# Output JSON:
#   {
#     "has_migration_system": <bool>,
#     "migration_paths": [...],
#     "schema_files": [...],
#     "api_contract_files": [...],
#     "public_api_surfaces": [...],
#     "config_schemas": [...],
#     "warnings": [...]
#   }
#
# Exit codes:
#   0  success — JSON on stdout
#   1  missing dependency
#
# Env:
#   MIGRATION_SCAN_ROOT   Override repo root (default: git toplevel, or cwd).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

err() { printf '%s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required command: $1"; exit 1; }
}

require_cmd jq

if [[ -n "${MIGRATION_SCAN_ROOT:-}" ]]; then
  REPO_ROOT="$MIGRATION_SCAN_ROOT"
else
  REPO_ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Files / patterns relative to REPO_ROOT. Existence checks; no content reads.
SCHEMA_CANDIDATES=(
  "prisma/schema.prisma"
  "db/schema.rb"
  "schema.sql"
  "db/structure.sql"
  "ent/schema"
)

MIGRATION_DIR_CANDIDATES=(
  "prisma/migrations"
  "db/migrate"
  "migrations"
  "alembic/versions"
  "drizzle"
  "src/migrations"
  "supabase/migrations"
  "knex_migrations"
  "sequelize/migrations"
)

API_CONTRACT_GLOBS=(
  "openapi.yaml"
  "openapi.yml"
  "openapi.json"
  "swagger.yaml"
  "swagger.yml"
  "swagger.json"
  "api/openapi.yaml"
  "api/openapi.json"
)

API_CONTRACT_EXTS=("graphql" "proto")

PUBLIC_API_CANDIDATES=(
  "src/index.ts"
  "src/index.js"
  "src/lib.rs"
  "lib.rs"
  "src/__init__.py"
  "packages"
)

CONFIG_SCHEMA_CANDIDATES=(
  "config/schema.json"
  "config/schema.yaml"
  "config/schema.yml"
  "schema/config.json"
  ".env.example"
  ".env.sample"
  "env.example"
)

exists_rel() {
  [[ -e "$REPO_ROOT/$1" ]]
}

schema_files=()
for c in "${SCHEMA_CANDIDATES[@]}"; do
  if exists_rel "$c"; then schema_files+=("$c"); fi
done

# SQLAlchemy / ORM model heuristic: a `models.py` or `models/` near app code.
# Cheap and best-effort; the agent makes the final call.
while IFS= read -r f; do
  rel="${f#"$REPO_ROOT/"}"
  schema_files+=("$rel")
done < <(find "$REPO_ROOT" -maxdepth 4 \( -name node_modules -o -name .git -o -name dist -o -name build -o -name .venv -o -name venv -o -name __pycache__ -o -name target \) -prune -o \( -name 'models.py' -o -name 'schema.py' \) -print 2>/dev/null | head -50)

migration_paths=()
for c in "${MIGRATION_DIR_CANDIDATES[@]}"; do
  if [[ -d "$REPO_ROOT/$c" ]]; then migration_paths+=("$c"); fi
done

api_contract_files=()
for c in "${API_CONTRACT_GLOBS[@]}"; do
  if exists_rel "$c"; then api_contract_files+=("$c"); fi
done
for ext in "${API_CONTRACT_EXTS[@]}"; do
  while IFS= read -r f; do
    rel="${f#"$REPO_ROOT/"}"
    api_contract_files+=("$rel")
  done < <(find "$REPO_ROOT" -type d \( -name node_modules -o -name .git -o -name dist -o -name build -o -name .venv -o -name venv -o -name __pycache__ -o -name target \) -prune -o -type f -name "*.$ext" -print 2>/dev/null | head -50)
done

public_api_surfaces=()
for c in "${PUBLIC_API_CANDIDATES[@]}"; do
  if [[ "$c" == "packages" ]]; then
    # Monorepo: look one level into packages/*/src/index.{ts,js}
    while IFS= read -r f; do
      rel="${f#"$REPO_ROOT/"}"
      public_api_surfaces+=("$rel")
    done < <(find "$REPO_ROOT/packages" -maxdepth 4 \( -name 'index.ts' -o -name 'index.js' -o -name 'lib.rs' -o -name '__init__.py' \) 2>/dev/null | head -50)
  elif exists_rel "$c"; then
    public_api_surfaces+=("$c")
  fi
done

# package.json with an "exports" field also signals a public surface.
if exists_rel "package.json"; then
  if jq -e '.exports // empty' "$REPO_ROOT/package.json" >/dev/null 2>&1; then
    public_api_surfaces+=("package.json (exports field)")
  fi
fi

config_schemas=()
for c in "${CONFIG_SCHEMA_CANDIDATES[@]}"; do
  if exists_rel "$c"; then config_schemas+=("$c"); fi
done

# Deduplicate each list.
dedupe_to_json() {
  if [[ $# -eq 0 ]]; then
    echo '[]'
  else
    printf '%s\n' "$@" | awk '!seen[$0]++' | jq -R . | jq -s .
  fi
}

schema_json="$(dedupe_to_json "${schema_files[@]+"${schema_files[@]}"}")"
migration_json="$(dedupe_to_json "${migration_paths[@]+"${migration_paths[@]}"}")"
api_json="$(dedupe_to_json "${api_contract_files[@]+"${api_contract_files[@]}"}")"
surface_json="$(dedupe_to_json "${public_api_surfaces[@]+"${public_api_surfaces[@]}"}")"
config_json="$(dedupe_to_json "${config_schemas[@]+"${config_schemas[@]}"}")"

has_migration_system="false"
if [[ "$(jq 'length' <<<"$migration_json")" -gt 0 ]] || [[ "$(jq 'length' <<<"$schema_json")" -gt 0 ]]; then
  has_migration_system="true"
fi

# Build warnings list. Each warning is a single string the agent should
# consider when deciding whether to include a Migration section.
warnings=()
if [[ "$has_migration_system" == "true" ]]; then
  warnings+=("Production migration system detected — verify backward-compat of schema changes")
fi
if [[ "$(jq 'length' <<<"$api_json")" -gt 0 ]]; then
  warnings+=("API contract files detected — changes here are consumer-visible")
fi
if [[ "$(jq 'length' <<<"$surface_json")" -gt 0 ]]; then
  warnings+=("Public API surface detected — changes here require deprecation strategy")
fi
if [[ "$(jq 'length' <<<"$config_json")" -gt 0 ]]; then
  warnings+=("Config schemas / env templates detected — coordinate with deploy config")
fi

warnings_json="$(dedupe_to_json "${warnings[@]+"${warnings[@]}"}")"

jq -n \
  --argjson has "$has_migration_system" \
  --argjson migration_paths "$migration_json" \
  --argjson schema_files "$schema_json" \
  --argjson api_contract_files "$api_json" \
  --argjson public_api_surfaces "$surface_json" \
  --argjson config_schemas "$config_json" \
  --argjson warnings "$warnings_json" \
  '{
    has_migration_system: $has,
    migration_paths: $migration_paths,
    schema_files: $schema_files,
    api_contract_files: $api_contract_files,
    public_api_surfaces: $public_api_surfaces,
    config_schemas: $config_schemas,
    warnings: $warnings
  }'
