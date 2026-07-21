---
name: commit-changes
description: >-
  Stage and commit changes in the current working tree using the repository's
  existing commit convention. Detects prefix style from recent history, decides
  whether to make one commit or split logical groups, and writes terse messages.
  Use when the user asks to commit, stage and commit, wrap up, or finalize edits,
  including after they say the work is ready to ship. Skip when the tree is clean
  or the user asks to leave changes uncommitted.
---

# commit-changes

Stage and commit the working tree using the repo's existing convention. Never invent prefixes the history doesn't use. Default to a single commit; split only with cause.

## Inputs
- Nothing — operates on the current working tree.
- Optional context: `.claude/fixes/<id>.md` (from `fix-bug`) or `.claude/changes/<id>.md` (from `ship-change`).
- Optional agent-side flags from the user: `--split` to force splitting, `--single` to force one commit.

## How to invoke

1. **Pre-flight.** Confirm we're in a git repo, not mid-rebase/merge/cherry-pick, and HEAD isn't detached. Check the branch — if it's `main`/`master`/`trunk`, warn and ask before continuing. Run `git status --porcelain`; if empty, exit cleanly.

2. **Detect convention.** Run `scripts/extract-commit-style.sh`. Reads the last 50 commits (or `--limit N`) and emits JSON with `prefix_style`, `scope_used`, `common_scopes`, `subject_case`, length stats, `body_usage_pct`, `issue_reference`, `trailers`, `confidence`, and `recent_examples`. If `confidence: low`, ask the user for the convention rather than guess.

3. **Decide split vs. single.** Default single. Split only if:
   - User asked (`--split`).
   - Changes span unrelated concerns (bug fix plus unrelated refactor).
   - Mechanical changes (lockfiles, generated code) mixed with substantive logic.
   - Upstream report defined separate logical steps.

   Surface the decision and rationale before staging. See `references/splitting-commits.md`.

4. **Group (only when splitting).** Cluster files by concern: tests with their source, generated files alone, docs alone if substantial, migrations with the code that uses them. If 3+ clusters, present them to the user before staging.

5. **Write messages.** Per cluster. **Keep it terse.** A single subject line is the goal; bodies are the exception, not the default.
   - **Subject only** in the overwhelming majority of cases. Aim for ~50 chars, hard cap 72. Matches detected convention exactly (prefix, scope syntax, case, punctuation).
   - **No body** unless one of these is true: motivation is non-obvious from the diff, there is a breaking change, or there is a non-trivial reason a future reader needs. "User asked, change is straightforward" is **not** a reason for a body. If you write one: blank line after subject, wrap at 72, describe **why**, not **what** (the diff is the what). Two or three sentences max — no bullet lists, no recap of files touched.
   - **No filler.** Skip phrases like "this commit", "this change", "in order to", "as requested". Drop the period.
   - **Imperative mood.** "add x", not "added x" / "adds x".
   - Issue refs: follow the detected pattern + location.
   - `Signed-off-by` / `Co-authored-by`: include if the repo uses them.

   Good examples (match the detected style — these assume conventional + lowercase):
   ```
   fix(auth): handle expired refresh token race
   feat(api): add idempotency key support
   chore(deps): bump typescript to 5.4
   ```

   Bad example — too verbose, recaps the diff, adds filler:
   ```
   feat(api): add new idempotency key support to the API endpoints

   This commit adds support for idempotency keys to our API. It modifies
   the request handler in src/api/handler.ts to check for the
   Idempotency-Key header, adds a new cache module in src/api/cache.ts
   to store responses, and updates the tests in tests/api.test.ts to
   cover the new behavior. This was requested by the user.
   ```

   See `references/message-writing.md` and `references/conventional-commits.md` for edge cases.

6. **Stage and commit.** Use explicit paths (`git add <files>`), not `git add -A`. Commit each cluster. If a pre-commit hook modifies files, re-add and retry once; if it modifies again or fails outright, halt and surface the hook output. Never `--no-verify`.

7. **Report.** List each commit's sha + subject + files. If the user mentioned pushing or opening a PR, hand off; otherwise stop.

## Edge cases
- **Pre-commit hooks rewrite the message** — accept it; don't fight.
- **Mixed staged + unstaged + untracked** — surface the state, ask about untracked. Never stage untracked silently.
- **Detached HEAD** — halt; commits would be lost.
- **Default branch** — warn and ask before committing.
- **Lockfile-only changes** — single commit, clear message (e.g. `chore: update lockfile`).
- **Signed commits** (`git config commit.gpgsign`) — respect; surface signing failures clearly.
- **DCO repo** — detect `Signed-off-by` in recent trailers and include it.
- **>50 files changed** — confirm split strategy before staging.

## Testing

Run from the repo root:

```
bash skills/commit-changes/tests/test-extract-style.sh
```

Fixtures under `tests/fixtures/<style>/commits.txt` exercise `extract-commit-style.sh` via its `--fixture <dir>` flag (or `EXTRACT_STYLE_FIXTURE_DIR=<dir>`) — no real git history needed.
