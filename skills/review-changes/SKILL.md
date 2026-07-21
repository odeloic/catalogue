---
name: review-changes
description: Review a pull/merge request or local branch diff against its originating issue's acceptance criteria and against the code itself. Anchors every finding to the diff line it is about, writes a ready-to-paste draft comment for each one, groups findings by sub-project when the diff spans several, and emits a recommendation (`approve` / `request_changes` / `comment`). Reuses `triage` for issue context.
when_to_use: When the user pastes a PR URL (`github.com/.../pull/N`), an MR URL (`gitlab.com/.../-/merge_requests/N`), a branch name to compare against the default branch, or says "review this PR", "review this MR", "code review for X", "look at these changes", "review the diff on branch X", "what do you think of #123", "review the diff", or "audit this PR". SKIP for pure style/lint pointers (use a linter) or when the user wants you to write the code, not review it.
argument-hint: "[pr-url | mr-url | branch] [show-fix] [reproduce]"
arguments: target
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/fetch-pr-context.sh *)
---

# review-changes

Review a PR/MR (or a branch diff) against the linked issue's acceptance criteria and against the code. Anchor every finding to the diff line it is about. Give every finding a comment the author can paste into the thread.

Depends on `triage` for issue context.

## Arguments

Flags are bare words (brackets optional) and may appear anywhere in the request, not just on the slash-command line.

| Argument | Default | Effect |
| --- | --- | --- |
| `$target` | current branch vs. the default branch | PR URL, MR URL, branch name, or path to a raw unified diff |
| `show-fix` | off | Add a proposed-fix diff to each finding. |
| `reproduce` | off | Verify findings by running them, and paste the real output. |

Without `show-fix`: say what is wrong and let the author choose the fix. Do not sketch one in prose instead — that is the same thing, longer.

Without `reproduce`: never write repro steps. Point at the diff. If a finding only holds when something is true at runtime, say which part you could not check.

## Workflow

### 1. Fetch context

```bash
${CLAUDE_SKILL_DIR}/scripts/fetch-pr-context.sh $target
```

The script resolves the input in priority order (PR URL → MR URL → branch → raw diff) and writes normalized context to stdout and to `.claude/reviews/<id>.context.json`. It is read-only — it never comments or approves. Auth errors from `gh` / `glab` surface verbatim and halt. `references/github.md` and `references/gitlab.md` cover the underlying commands.

Capture `linked_issues`, `ci`, `is_draft`, `size_metrics`, `depends_on`, `diff`, `files_changed`.

### 2. Resolve the issue

For each `linked_issues[].id`, invoke `triage` to produce or reuse `.claude/triage/<issue-id>.json` — you invoke it, the script does not. Read each report's `acceptance_criteria[]` and `prior_attempts[]`. If triage fails, say so and ask whether to continue without AC checks.

### 3. Pre-flight

Check the fetched context against `references/preflight-and-edge-cases.md` before reading code. One line per match, no diagnosis. Skip the whole section if none apply.

### 4. Group by sub-project

Only when the diff spans more than one project — see `references/subproject-grouping.md`. Otherwise skip this step entirely and never mention grouping.

### 5. Review the diff

Walk the diff against the seven dimensions in `references/review-checklist.md`: correctness, error handling, security, performance, tests, style consistency, scope creep.

Then classify each acceptance criterion, citing `file:line` or "no evidence in diff" for every row:

- **Met** — the diff clearly does it.
- **Partial** — done, with gaps. Name the gap.
- **Missing** — no evidence in the diff.
- **Can't tell from the diff** — needs a runtime check or context you do not have.

**Scope guard.** A finding's file must appear in `files_changed[]`. Files you opened for context — callers, helpers, imports — are there to help you judge the diff, not to be reviewed. If something outside the diff looks wrong, drop it; it is a separate conversation. The one exception: a diff line that depends on broken out-of-diff behaviour. Then the finding sits on the diff line, not the other file.

### 6. Reproduce — only with `reproduce`

Skip this step entirely unless the flag is set.

With it: start what the change needs, trigger the path, and capture the real output — the command and its response, the log line, the DOM node, the row count. Then undo any test data you created and confirm the working tree is clean.

If you cannot run it, say which finding is unverified and why. Do not write steps you did not execute.

### 7. Write the findings

Severity comes from `references/severity-levels.md`. Finding anatomy, draft-comment voice, prose budgets, and the document outline are in `references/writing-the-review.md`.

**Scope check before writing.** Walk every finding and confirm its file is in `files_changed[]`. Drop the ones that are not — do not relocate them, do not soften them. If `files_changed[]` is empty (raw diff), build the set from the `+++ b/<path>` lines.

### 8. Recommend and emit

Pick one, per the table in `references/severity-levels.md`:

- Any Blocker, or a Missing AC on a non-draft PR → `request_changes`
- Unresolved Majors or ambiguous AC → `comment`
- Neither, and all AC Met or can't-tell-with-a-note → `approve`

Then:

- Write `.claude/reviews/<pr-id>.md`.
- Append to each linked issue's `.claude/triage/<issue-id>.json` under `reviews[]`:
  `{ "pr_url": "...", "review_path": "...", "recommendation": "...", "at": "ISO-8601" }`
- Render the artifact — content per `references/artifact-payload.md`, routing per `${CLAUDE_SKILL_DIR}/../../.claude-plugin/references/rendering-artifacts.md`.
- Print one line in chat: recommendation, counts by severity, artifact link.

## Testing

**Script.** `FETCH_PR_MODE=fixture` makes `fetch-pr-context.sh` read `tests/fixtures/<source>/<id>.json` instead of calling `gh` / `glab` / `git`. Run `tests/test-fetch-pr-context.sh` from the repo root.

**Skill.** `evals/evals.json` holds five graded cases with their input diffs in `evals/files/`. Run them with `skill-creator` — with-skill against a no-skill baseline — and grade against each case's `expectations[]`.
