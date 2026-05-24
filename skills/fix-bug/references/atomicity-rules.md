# Atomicity rules

A bug fix is atomic when its diff contains only the changes necessary to make the failing test pass (or, with no test infra, make the manual repro stop reproducing). Everything else is a drive-by.

## In scope

- The line(s) implementing the bug.
- The new test (or modified test) that proves the fix.
- A type / signature change forced by the fix.
- A new helper extracted only if the fix would otherwise be unreadable, and the helper has no other call sites.
- Imports added or removed as a direct consequence of the above.

## Out of scope (defer or ask)

- Renames that aren't required by the fix.
- Formatting changes outside touched lines.
- Refactors of nearby code that "while I'm here" could be improved.
- Comment cleanup, log-level changes, dead code removal in unrelated functions.
- Dependency upgrades. Lockfile changes that aren't a deliberate dependency update are usually accidental — surface them.
- Reordering imports, sorting object keys, alphabetizing exports.
- Auto-fixes from a linter or formatter that touch files you didn't otherwise change.

## Gray areas (always ask)

- The fix exposes a second, related bug in the same function. Fix one, file the other.
- The test framework requires a configuration change to run the new test. Acceptable if minimal; explain why in the commit.
- A type annotation is wrong nearby but not part of the fix. If the type system blocks you, fix only the line that blocks you.
- The fix is a one-line revert of a recent commit. Acceptable if you confirm the revert is correct in isolation — but explain the original intent and why the revert is safe.

## How `verify-atomic.sh` classifies

- **test_files** — anything matching common test path conventions (`__tests__/`, `*.test.*`, `*_test.go`, `*_spec.rb`, `tests/test_*.py`, etc.).
- **source_files** — touched files that aren't tests or lockfiles or generated.
- **lockfile_changes** — `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `Cargo.lock`, `Gemfile.lock`, `composer.lock`, `poetry.lock`, `uv.lock`, `go.sum`, `mix.lock`, etc. Always surfaced as a warning.
- **unrelated_candidates** — source files that don't match any triage hint, and don't have a one-hop import relationship with a file that does.

The script does not block. It surfaces. The agent reads the JSON and:
1. For each `unrelated_candidate`, decide whether it's actually in scope (the import-graph heuristic misses dynamic imports, reflection, and string-based lookups) and explain the reasoning.
2. For each `warning`, surface it to the user before commit.
3. If `lockfile_changes` is non-empty, confirm with the user whether the dependency change was intentional.

## When the rule should bend

Sometimes the minimum change is genuinely intrusive — a shared helper has the bug and ten call sites are affected. In that case, atomicity means "every file you touched is justified by the fix", not "you touched one file". Be explicit in the fix report about why the scope is what it is.
