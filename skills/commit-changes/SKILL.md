---
name: commit-changes
description: Stage and commit changes in the current working tree. Use at the end of an implementation task, or when the user says "commit", "commit these changes", "make a commit", or "commit and push". Detects the repo's commit convention from history, decides whether to make one commit or split into logical groups, and writes messages under 100 characters. Reads optional context from `fix-bug` or `ship-change` reports if present.
when_to_use: At the end of an implementation task, or when the user says "commit", "commit these changes", "make a commit", or "commit and push".
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

5. **Write messages.** Per cluster:
   - Subject: max 100 chars, matches detected convention exactly (prefix, scope syntax, case, punctuation).
   - Body: only when motivation is non-obvious or there's a breaking implication. Wrap at 72.
   - Issue refs: follow the detected pattern + location.
   - `Signed-off-by` / `Co-authored-by`: include if the repo uses them.

   See `references/message-writing.md` and `references/conventional-commits.md`.

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
