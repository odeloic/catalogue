# Spec: `commit-changes` skill

## Purpose
Stage and commit changes in the working tree following the repo's existing commit conventions. Decide whether the change is one logical commit or multiple, write messages under the user's 100-char subject rule, and never invent conventions the repo doesn't use.

## Skill frontmatter description (the trigger contract)
> Stage and commit changes in the current working tree. Use at the end of an implementation task, or when the user says "commit", "commit these changes", "make a commit", or "commit and push". Detects the repo's commit convention from history, decides whether to make one commit or split into logical groups, and writes messages under 100 characters. Reads optional context from `fix-bug` or `ship-change` reports if present.

## Inputs
1. Nothing — operates on the current working tree.
2. Optional context: a fix report (`.claude/fixes/<id>.md`) or change summary (`.claude/changes/<id>.md`) to inform the message.
3. Optional flag — `--split` to force splitting, `--single` to force one commit.

## Workflow

### 1. Pre-flight checks
- Confirm we're inside a git repo and not in a conflicted state (no in-progress rebase/merge/cherry-pick).
- Check current branch — if it's the default branch (`main`, `master`, `trunk`), halt and warn before proceeding.
- Run `git status --porcelain` to see the working tree state.
- If there's nothing to commit, exit cleanly with a note.

### 2. Detect convention
Call `extract-commit-style.sh`. Returns the detected style with confidence and example commits. The agent uses this to write messages that fit; do not invent prefixes the repo doesn't use.

### 3. Decide split vs. single
Default to **single commit**. Split only when one of the following is true:
- The user explicitly requested splitting (`--split`).
- Changes span clearly unrelated concerns (e.g., a bug fix plus an unrelated refactor).
- Changes mix mechanical changes (lockfile bumps, generated code) with substantive logic.
- Upstream context (fix report or change summary) defined separate logical steps that should commit independently.

When in doubt, default to single and let the user ask for a split. Surface the decision and the rationale before staging.

### 4. Group changes (only when splitting)
Cluster files by concern:
- Test files + their corresponding source files → same cluster.
- Generated files (lockfiles, dist/, generated APIs) → their own cluster.
- Documentation-only changes → their own cluster if substantial, otherwise folded into the relevant code cluster.
- Migrations and the code that uses them → same cluster.

Present the proposed clusters to the user before staging if there are 3+ clusters.

### 5. Write message(s)
Per cluster:
- Subject line: max 100 chars, matches the detected convention exactly (prefix, scope syntax, case, trailing punctuation, all of it).
- Body: only if the change has non-obvious motivation, breaking implications, or references issues. Otherwise omit. Wrap at 72 chars.
- Issue/ticket references: include in the message body or trailer per repo convention (extracted from history).
- Co-authored-by trailers and sign-off (`Signed-off-by`): include if the repo uses them.

### 6. Stage and commit
- Stage explicitly per cluster (`git add <files>`) rather than `git add -A`.
- Commit each cluster.
- If pre-commit hooks modify files, re-add and retry once. If they fail outright, halt and surface the hook output.

### 7. Surface result
In chat: list the commits made (sha + subject), files per commit. If the user mentioned a PR in their request, hand off; otherwise end here.

## Script: `scripts/extract-commit-style.sh`
Single call. Reads the last N commits (default 50) and emits JSON to stdout. Read-only.

Detection dimensions:
- **Prefix pattern** — conventional commits (`feat:`, `fix:`, `chore:`...), gitmoji (`:sparkles:`, `:bug:`...), ticket prefix (`[ENG-123]`, `ENG-123:`), or none.
- **Scope pattern** — does the repo use `feat(scope):` syntax? If so, what are the common scopes (top 10)?
- **Subject case** — sentence case, lower case, title case.
- **Subject length** — median, max observed. Surface if the user's 100-char rule conflicts with repo norm.
- **Body usage** — what % of commits have a body? Average length.
- **Issue references** — pattern (`Refs ENG-123`, `Closes #42`, `Fixes GH-7`) and location (body, trailer, subject).
- **Trailers** — `Signed-off-by`, `Co-authored-by`, custom trailers.

Output:
```json
{
  "sample_size": 50,
  "prefix_style": "conventional|gitmoji|ticket|none",
  "prefix_examples": ["feat:", "fix:", "chore:"],
  "scope_used": true,
  "common_scopes": ["api", "ui", "auth", "db"],
  "subject_case": "lower|sentence|title",
  "subject_median_length": 52,
  "subject_max_length": 98,
  "body_usage_pct": 35,
  "issue_reference": {
    "pattern": "Refs ENG-\\d+",
    "location": "trailer|body|subject|none"
  },
  "trailers": ["Signed-off-by", "Co-authored-by"],
  "confidence": "high|medium|low",
  "recent_examples": [
    "feat(api): add idempotency key support",
    "fix(auth): handle expired refresh token race"
  ]
}
```

`confidence: low` means the history is short or inconsistent — the agent should ask the user rather than guess.

## Outputs
1. One or more commits on the current branch.
2. Chat summary: commits made (sha + subject), files per commit, any hook adjustments.
3. No file artifact — the commits themselves are the artifact.

## Directory layout
```
skills/version-control/commit-changes/
├── SKILL.md
├── scripts/
│   └── extract-commit-style.sh
├── references/
│   ├── conventional-commits.md         # the conventional commits spec
│   ├── splitting-commits.md            # when and how to split
│   └── message-writing.md              # subject/body/trailer rules
└── tests/
    └── fixtures/                        # repos with different commit styles
```

## Edge cases
- **Pre-commit hooks fail** — surface the output, halt. Don't bypass with `--no-verify`.
- **Pre-commit hooks modify files** — re-add and retry once; if it modifies again, halt and surface.
- **Hooks rewrite the message** — accept the rewrite, surface to user, don't fight it.
- **Mixed staged + unstaged + untracked** — surface the state, ask whether to include untracked, never stage untracked silently.
- **Detached HEAD** — halt with a clear message; commits would be lost.
- **On default branch** — warn and ask for confirmation; never silently commit to `main`/`master`/`trunk`.
- **Empty working tree** — exit cleanly, no error.
- **Repo has fewer than 5 commits** — `extract-commit-style.sh` returns low confidence; ask user for the convention.
- **Lockfile-only changes** — single commit with a clear message (e.g., `chore: update lockfile`).
- **Repo enforces signed commits** — detect via `git config commit.gpgsign` and respect; surface a clear error if signing fails.
- **Repo enforces signed-off-by** (DCO) — detect via recent commit trailers; add `Signed-off-by` automatically.
- **Massive diff (>50 files)** — surface size, ask for confirmation on the split strategy before staging.

## Relationship to existing tooling
Overlaps with the `/claude-ode:docs-commit` command from the original plugin. The skill version auto-triggers at end-of-task (when `fix-bug` or `ship-change` hands off). The command stays for explicit user invocation. Worth eventually consolidating — the skill can absorb the command's logic and the command becomes a thin wrapper that just invokes the skill.

## Testing approach
Fixture-based: a few small repos under `tests/fixtures/` with distinct commit styles (conventional, gitmoji, ticket-prefixed, plain). Run `extract-commit-style.sh` against each and assert the detected style. For message generation, snapshot-test the subject lines against frozen working-tree states with known conventions.
