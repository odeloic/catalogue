# Spec: `fix-bug` skill

## Purpose
Enforce the bug-fix discipline: reproduce first, write a failing test (when test infrastructure exists), fix, verify atomicity, then hand off to `commit-changes`. The skill takes a triage report and ends with a clean, scoped fix and verification trail.

## Skill frontmatter description (the trigger contract)
> Fix a bug end-to-end given a triage report or issue ID. Use when a triage classification is "bug", or the user says "fix this bug", "reproduce and fix", or "the bug in ENG-123". Enforces reproduce → failing test → fix → atomicity verification. Depends on `triage-issue` for context, hands off to `commit-changes` when done.

## Inputs
The skill accepts, in priority order:
1. A triage report path — `.claude/triage/<issue-id>.json` (the normal flow after `triage-issue`).
2. An issue ID or URL — the skill invokes `triage-issue` first to produce the report.
3. A free-form bug description — skips triage; the user takes responsibility for context.

## Workflow phases

### 1. Acquire context
Load the triage report. If only an issue ID is provided, invoke `triage-issue` and read its output. If only a description is provided, generate a minimal in-memory equivalent so the rest of the workflow can rely on the same shape.

### 2. Reproduce
Establish a deterministic reproduction before any fix attempt. Produce a repro recipe with: command(s) to run, expected behavior, actual behavior. If reproduction fails after reasonable attempts, halt and escalate to the user with the hypotheses tried. **Never proceed to fix without a confirmed repro.**

### 3. Detect test infrastructure
Call `detect-test-infra.sh`. If a framework is present, the skill writes a failing test next. If absent, the skill records this and falls back to manual repro verification at the end.

### 4. Write failing test (conditional)
Write a test that fails specifically because of the bug. Run it to confirm it fails for the right reason (assertion message, not a setup error). The failing test is the contract for the fix.

### 5. Implement the fix
The minimum change that makes the test pass (or the repro stop reproducing). No drive-by refactors, no unrelated cleanup, no formatting passes outside touched code. If the fix would require a broader change, halt and ask before proceeding.

### 6. Verify
- The new test passes.
- The original repro no longer reproduces.
- The broader test suite (or relevant subset) still passes.

### 7. Verify atomicity
Call `verify-atomic.sh`. Confirms the diff scope is reasonable and lists files touched. Surface any files outside the suspected scope for explicit user confirmation.

### 8. Update triage state
Write fix metadata back into the triage JSON so `review-changes` can pick up the link later:
```json
"fix": {
  "report_path": ".claude/fixes/<issue-id>.md",
  "test_added": true,
  "files_touched": ["..."],
  "verified_at": "ISO-8601"
}
```

### 9. Handoff
Pass control to `commit-changes`. If the user's convention separates test commits from fix commits (some teams do), stage them as separate logical groups.

## Script: `scripts/detect-test-infra.sh`
Single call. Returns JSON to stdout. Read-only.

Detection sources, in order:
- `package.json` → look at `scripts.test` and `devDependencies` for jest, vitest, mocha, ava, playwright, cypress.
- `pyproject.toml`, `setup.cfg`, `pytest.ini`, `tox.ini` → pytest, unittest, nose.
- `go.mod` → `go test`.
- `Cargo.toml` → `cargo test`.
- `Gemfile` → rspec, minitest.
- `composer.json` → phpunit, pest.
- `mix.exs` → exunit.
- `.github/workflows/*.yml`, `.gitlab-ci.yml` → infer the test command from CI as a fallback.

Output:
```json
{
  "exists": true,
  "framework": "vitest",
  "test_command": "pnpm test",
  "single_test_command": "pnpm test -- <pattern>",
  "test_dir": "src/__tests__",
  "confidence": "high|medium|low",
  "evidence": ["package.json:devDependencies.vitest", "..."]
}
```
If nothing is detected: `{ "exists": false, "evidence": [...] }`.

## Script: `scripts/verify-atomic.sh <triage-id>`
Reads the triage JSON to learn the suspected scope (extracted file/area hints, related code). Diffs the working tree against the merge base. Returns JSON to stdout.

```json
{
  "files_touched": ["..."],
  "test_files": ["..."],
  "source_files": ["..."],
  "unrelated_candidates": ["..."],
  "lockfile_changes": ["package-lock.json"],
  "warnings": ["..."],
  "stats": { "added": 12, "removed": 4, "files": 3 }
}
```

`unrelated_candidates` lists files touched that don't match any of:
- Files mentioned in the triage report.
- Files imported by, or importing, the modified source files (one hop).
- Test files corresponding to modified source files.

The script does not block — it surfaces. The agent decides whether each "unrelated candidate" is actually unrelated and asks the user for the ambiguous ones.

## Outputs
1. A bug-fix report at `.claude/fixes/<issue-id>.md` containing: repro recipe, test added (file + name), fix description, verification results, atomicity check summary.
2. The actual code changes (test + fix) in the working tree, ready for `commit-changes`.
3. Updated triage JSON with the `fix` field linked.

## Directory layout
```
skills/implementation/fix-bug/
├── SKILL.md
├── scripts/
│   ├── detect-test-infra.sh
│   └── verify-atomic.sh
├── references/
│   ├── reproduction-strategies.md      # patterns by bug type (UI, API, race, data)
│   ├── test-frameworks.md              # per-framework specifics
│   └── atomicity-rules.md              # what counts as "in scope"
└── tests/
    └── fixtures/                       # sample triage JSONs + repo states
```

## Edge cases
- **No test infrastructure** — skip the failing-test step, document the manual repro carefully, and note this clearly in the fix report.
- **Bug not reproducible** — halt, present the hypotheses tried, ask for more info or a reproduction recipe from the issue author.
- **Fix requires a breaking change** — flag and ask before implementing; this is `ship-change` territory.
- **Multiple plausible root causes** — diagnose first, present options with tradeoffs, let the user pick.
- **Fix touches generated/vendored files** — flag explicitly; never modify generated files without acknowledgment.
- **Repro requires production data or external services** — halt, document the limitation, ask for a test fixture or staging access.
- **Test infra exists but is broken on main** — surface this; the failing-test contract isn't reliable until the suite is green.

## Testing approach
Fixture-based: a few small repos under `tests/fixtures/` (one per language ecosystem) with a planted bug and an expected fix shape. Run `detect-test-infra.sh` against each and assert the JSON output. For `verify-atomic.sh`, stage known-good and known-bad diffs and check the classification.
