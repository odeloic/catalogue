# Verification strategies

Every step in the plan declares **how it will be verified**. "Run the tests" is not concrete enough — the agent needs to name the command, the test, the endpoint, or the visual outcome. This document covers the verification patterns to choose from.

## The bar

A verification method is acceptable if:

- It produces a binary pass / fail result.
- It can be re-run by the agent without user intervention (unless the step is genuinely visual and there's no automated alternative).
- It catches the failure modes the step could realistically introduce.

If a step has no good verification, the step is too small or too vague — merge or rewrite.

## Strategies by surface

### Unit tests

For pure functions, services, and self-contained modules.

- Name the test file and the case: `tests/services/rate-limiter.spec.ts :: "per-key isolation"`.
- Prefer adding a test that fails before the change and passes after. State that in the step.
- A unit test that only mocks everything around the change is weaker than one that exercises real collaborators.

### Integration / endpoint tests

For HTTP routes, queue handlers, scheduled jobs.

- Name the route and the test: `POST /api/v1/users :: returns 201 with new id`.
- For new endpoints, the test must cover at least the happy path and one failure mode (auth, validation, conflict).
- If the route touches a database, the test should assert on the database state, not just the response.

### Hit-the-endpoint check

Sometimes a test is overkill or not yet wired. The agent can verify by issuing an actual request.

- Name the exact command: `curl -s -X POST localhost:3000/api/v1/foo -d '{"x":1}' | jq .id`.
- Useful for confirming an endpoint exists, returns the right shape, or returns the right headers.
- Not sufficient for steps that introduce nontrivial logic — pair with a test.

### Type check

For TypeScript, Python (mypy / pyright), Rust, Go.

- Name the command: `pnpm tsc --noEmit`, `mypy src/`, `cargo check`, `go build ./...`.
- Useful as a baseline check on a step that changes types; not sufficient as the only verification for a logic change.

### Lint

- Name the command: `pnpm lint`, `ruff check`, `cargo clippy`, `golangci-lint run`.
- Useful for style / import / unused-symbol drift; not sufficient on its own.

### Schema migration check

When the step changes a schema:

- Name the migration command: `pnpm prisma migrate dev --name <name>`, `alembic upgrade head`, `rails db:migrate`.
- Verify the migration is reversible if downgrade exists in this ecosystem: `alembic downgrade -1`, then re-`upgrade head`.
- Verify a `prisma db pull` or equivalent does not produce a diff (the schema in code matches the database).

### Build check

- For library or package changes: `pnpm build`, `cargo build --release`, `python -m build`.
- Particularly useful for `exports` changes — a build is the easiest way to confirm an export resolves.

### Visual / manual

For UI changes, design polish, content tweaks.

- Name what the agent (or user) should see: "the new banner renders at the top of `/dashboard` on viewport widths 768px and up".
- Include the URL or screen the agent should view.
- For UI work in CI environments, pair with a snapshot test where possible.

### Performance verification

For perf-sensitive steps:

- Name the benchmark: `cargo bench --bench rate_limiter`, `pnpm bench`, k6 script path.
- Declare the threshold in the plan: "must complete 10k requests in under 2s on the bench harness".
- Compare before and after, not just absolute.

### Smoke / acceptance run

For the final acceptance check after all steps:

- Walk through each success criterion, name how it was verified.
- If a criterion was "no regression on existing X", explicitly run the existing tests for X.
- If a criterion was an external behavior, hit it directly.

## Language and ecosystem notes

### TypeScript / Node

- `pnpm tsc --noEmit` for types.
- `pnpm test -- <pattern>` for targeted tests.
- `pnpm lint` for ESLint / Biome.
- Prefer `vitest` / `jest` patterns: `test.only(...)` is **not** acceptable left in a verified step.

### Python

- `pytest tests/path/test_x.py::test_y` for targeted tests.
- `mypy src/` or `pyright` for types.
- `ruff check` / `ruff format --check` for lint and style.

### Rust

- `cargo test --package <pkg> <test_name>`.
- `cargo check` for fast type-only verification.
- `cargo clippy --all-targets -- -D warnings` to catch new lints.

### Go

- `go test ./path/to/pkg -run TestName`.
- `go vet ./...`.
- `golangci-lint run` if the project has it.

### Database

- `pnpm prisma migrate dev` for Prisma; check the generated SQL in `prisma/migrations/<n>/migration.sql`.
- `alembic upgrade head` for SQLAlchemy / Alembic.
- `rails db:migrate` and `rails db:rollback` for Rails.

## When verification fails

Per SKILL.md, the agent halts and surfaces:

1. What the step was supposed to do.
2. What command was run for verification.
3. The actual output / failure.
4. The options: retry, skip with caveat, escalate, revise plan.

Do not silently continue past a failed verification. Do not paper over the failure by tweaking the test until it passes.
