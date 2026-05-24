# Migration considerations

When `detect-migration-needs.sh` flags schema files, migration directories, API contract files, public API surfaces, or config schemas, the plan must include a Migration section. This document covers the patterns to apply.

The rule of thumb: **any contract a consumer depends on changes via expand → migrate → contract, not as a single replacement.**

## Schema changes (databases)

### Additive changes (new tables, new optional columns)

Lowest risk. Still requires care in production.

- Add the new table or column as nullable (or with a safe default).
- Deploy the schema change first; do not deploy code that depends on it in the same change.
- Backfill old rows in a separate step, not inline with the migration.

### Renames

A column rename is **two changes**, not one:

1. Add the new column. Dual-write to both. Backfill the new from the old.
2. Cut readers over to the new column. Confirm in metrics / logs.
3. (Later commit, different deploy) Drop the old column.

Never `ALTER COLUMN RENAME` in production if any code in flight reads the old name.

### Type changes

Treat as a rename: add a new column with the new type, dual-write, cut readers, drop the old column.

### Destructive changes (DROP, NOT NULL on existing, foreign key tightening)

Halt at the plan gate. These need:

- Explicit confirmation of data preservation strategy.
- A "rollback if X" criterion in the plan.
- A staging-environment dress rehearsal step before the production step.

### Backfills

- For tables under ~100k rows, an inline migration is usually fine.
- For larger tables, backfill in a background job with batching and progress logging. The migration itself only creates the empty column.

## API contract changes (OpenAPI, GraphQL, gRPC)

Contracts are public. Breaking them silently breaks consumers.

### Adding endpoints / fields

Safe. Generate the contract file change, regenerate clients (if any), proceed.

### Removing endpoints / fields

1. **Deprecate first.** Mark in the contract (`deprecated: true` in OpenAPI, `@deprecated` in GraphQL).
2. **Warn at runtime.** Log when the deprecated path is hit; include the consumer identifier where available.
3. **Communicate.** Surface the deprecation in release notes / changelog.
4. **Watch metrics** for a defined deprecation window (typical: one or two release cycles).
5. **Remove only when usage is zero.** Track this in the plan as a follow-up issue, not in the same change.

### Changing field types

Treat as remove + add: new field with new type, deprecate the old, cut consumers over, then remove.

### Changing behavior under the same shape

Hardest case — same request, different response semantics. Options:

- Versioned endpoint (`/v2/...`) — preferred when consumers are external.
- Behavior flag in the request — for internal callers.
- Hard cut after coordinated consumer update — only when consumers are fully controlled in-tree.

## Public type / API surface changes (libraries, SDKs)

When `detect-migration-needs.sh` flags `src/index.ts`, `lib.rs`, `__init__.py`, or a package `exports` field, the change is library-public.

### Adding exports

Safe. Add and proceed.

### Removing or renaming exports

Same shape as API deprecation:

1. Add the new export.
2. Keep the old export but mark deprecated (`@deprecated` JSDoc, `#[deprecated]` Rust, `DeprecationWarning` Python).
3. The plan must name the removal version / date.
4. Removal happens in a separate, future change — not in the same plan.

### Changing function signatures

If the change is in a library consumed externally, **refuse to proceed past the gate** until the plan declares one of:

- A new function name with the new signature (additive).
- A major version bump for the package.
- An overload that handles both old and new shapes.

Silent signature changes break downstream builds and are not acceptable for a public surface.

## Config schema changes

When `.env.example`, config schema files, or env-var documentation is touched:

- Adding a new env var: provide a sensible default in code; failure to read the var should not crash the app. Document the default in the example file.
- Removing an env var: deprecate, log a warning when the var is set, remove in a follow-up.
- Changing the format / parsing: same expand → migrate → contract — accept both formats for a window.

Coordinate with the deploy pipeline: a config-schema change often requires a parallel update to the secrets / config store before the code change deploys.

## What to put in the Migration section of the plan

When this section is needed, it must include:

1. **What contracts change** — name the schema files, contract files, or public surfaces.
2. **Strategy** — additive, expand-migrate-contract, deprecate-then-remove, versioned, or hard cut. Pick one and say why.
3. **Backward-compat window** — how long the old shape is supported. Concrete: "one release", "until 2026-06-01", "until consumer X is updated".
4. **Verification** — how the agent confirms backward-compat holds at each step. Usually a test that exercises the old shape.
5. **Rollback** — what undoes this if something breaks in production.

If any of those five are missing, the plan is not ready for the gate.
