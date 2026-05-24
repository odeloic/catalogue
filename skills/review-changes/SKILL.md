---
name: review-changes
description: Review a pull/merge request or local branch diff against its originating issue. Use when the user provides a PR/MR URL, a branch name, or says "review this PR", "look at these changes", "review the diff on branch X". Reuses `triage` for issue context. Produces a structured review with AC verification, quality findings grouped by severity, and a recommendation.
when_to_use: When the user provides a PR/MR URL (`github.com/.../pull/N`, `gitlab.com/.../-/merge_requests/N`), a branch name, a raw diff, or says "review this PR", "look at these changes", "review the diff on branch X".
---

# review-changes

Review a PR/MR (or a local branch's diff) against the originating issue's acceptance criteria, run a code-quality pass over the diff, and emit a structured review grouped by severity with a single recommendation: `approve`, `request_changes`, or `comment`.

Depends on `triage` (referenced as `[[triage]]`) for issue context. The two reference files `references/github.md` and `references/gitlab.md` overlap with the triage skill's `[[github]]` / `[[gitlab]]` references but stay focused on PR/MR commands.

## Inputs accepted

In priority order:
1. A PR URL — `https://github.com/owner/repo/pull/N`.
2. An MR URL — `https://gitlab.com/group/project/-/merge_requests/N`.
3. A branch name — diffed against the default branch (or a user-specified base).
4. A raw unified diff piped in or written to a file — last-resort fallback when no PR/MR exists.

## How to invoke

1. Run `scripts/fetch-pr-context.sh <input>`.
   - Writes the normalized PR context JSON to stdout and to `.claude/reviews/<id>.context.json`.
   - Read-only: never comments, approves, or changes labels on the PR.
2. For each `linked_issues[].id` in the returned context, invoke the `triage` skill to produce or reuse `.claude/triage/<issue-id>.json`. The agent invokes triage — the script does not.
3. If `triage` fails (e.g. Linear MCP unavailable), surface the error and ask the user whether to continue without AC verification.
4. Auth failures surface verbatim from `gh` / `glab` and halt — the user must fix them before re-running.

## Workflow (8 phases)

### 1. Fetch PR context
Call `fetch-pr-context.sh`. Capture `linked_issues`, `ci`, `is_draft`, `size_metrics`, `depends_on`, `diff`, and `files_changed`.

### 2. Resolve issue context
For each linked issue, invoke `triage`. Read each triage JSON's `acceptance_criteria[]` and `prior_attempts[]`. If `linked_issues` is empty, skip AC verification and flag this in the review header.

### 3. Pre-flight checks
Surface blockers *before* the quality pass:
- **CI failing** — prominent header note; recommend fixing CI first. Do not diagnose CI failures.
- **Draft PR** — mark review preliminary; adjust tone from prescriptive to exploratory.
- **Depends on unmerged PR** (`depends_on` non-empty) — flag, recommend reviewing in dependency order.
- **Large PR** — when `size_class` is `large` or `xlarge`, declare review coverage explicitly. See `references/pr-size-heuristics.md` for the focus areas (auth, payments, migrations, public APIs, data integrity).
- **Sensitive files touched** — `files_changed[]` paths matching `auth`, `payment`, `migration`, `security`, `iam`, `crypto`, `secret` — extra scrutiny flag.
- **Self-review** — PR author equals the requesting user — proceed but suggest a second reviewer for blockers.
- **Linked issue is closed/duplicate** — surface and ask before proceeding.

### 4. Code quality pass
Walk the diff and identify findings across the seven dimensions in `references/review-checklist.md`:
correctness, error handling, security, performance, tests, style consistency, scope creep.

Each finding records: `file:line`, what's wrong, why it matters, and a concrete suggestion.

### 5. AC verification
For each acceptance criterion pulled from triage, classify as:
- **Met** — diff clearly satisfies it.
- **Partial** — addressed but with gaps.
- **Missing** — no evidence in the diff.
- **Not verifiable from diff** — needs runtime check, manual test, or external context.

Cite evidence (file:line or "no evidence in diff") for each row.

### 6. Run tests (optional)
Only if the user opts in. Don't auto-run — the env may not be set up and tests may be slow. If run, surface failures by file:line; otherwise note "tests not run as part of this review".

### 7. Compose review
Group findings by severity per `references/severity-levels.md`:
- **Blocker** — must be fixed before merge.
- **Major** — should be fixed, not strictly blocking.
- **Minor** — worth addressing, defer is acceptable.
- **Nit** — purely stylistic.

Pick the recommendation:
- Any Blocker, or any unmet AC marked Missing on a non-draft PR → `request_changes`.
- No Blockers but unresolved Majors or ambiguous AC → `comment`.
- No Blockers/Majors, all AC Met or Not-verifiable-from-diff with a note → `approve`.

### 8. Write outputs
- Write `.claude/reviews/<pr-id>.md` (full review).
- For each linked issue, append a record to `.claude/triage/<issue-id>.json` under `reviews[]`:
  ```
  { "pr_url": "...", "review_path": "...", "recommendation": "...", "at": "ISO-8601" }
  ```
- Print a condensed chat summary: recommendation + reasoning, AC tally, top 3 Blockers/Majors, link to the review file.

## Output review markdown structure

Sections, in order:
1. **Summary** — one paragraph: what the PR does.
2. **Recommendation** — `approve` / `request_changes` / `comment` with a one-line reason.
3. **Pre-flight** — CI status, draft state, dependency PRs, sensitive-file flags. Skip the section entirely if nothing to flag.
4. **AC verification** — table of criterion → status → evidence. Replace with "No linked issue — AC verification skipped" if none.
5. **Findings** — grouped by severity. Each finding: `path:line`, problem, why it matters, suggestion.
6. **Open questions for the author** — anything ambiguous in the diff.
7. **Coverage note** — for `large` / `xlarge` PRs: what was reviewed in depth vs. skimmed.

## Edge cases

- **No linked issue** — skip AC verification, note explicitly. Focus on quality.
- **CI failing** — surface prominently; do not diagnose.
- **Draft PR** — mark preliminary, exploratory tone.
- **Very large PR** — declare coverage; focus on high-risk areas per `references/pr-size-heuristics.md`.
- **Depends on unmerged PR** — flag dependency; note findings may shift once it lands.
- **Sensitive files** (auth, payments, migrations, public APIs, data integrity) — flag for extra scrutiny.
- **Self-review** — proceed, suggest a second reviewer for blockers.
- **Issue closed or duplicated** — surface and ask the user before AC verification.
- **No diff available** (already merged, force-pushed without local) — halt with a clear error.
- **Raw diff input with no PR** — proceed without `ci`, `linked_issues`, or `depends_on`. Mark AC verification as skipped unless the user supplies an issue ID separately.

## Testing

Set `FETCH_PR_MODE=fixture` and the script reads from `tests/fixtures/<source>/<id>.json` instead of calling `gh` / `glab` / `git`. Use this for unit tests of source detection, JSON shape, and size-class classification. Run `tests/test-fetch-pr-context.sh` from the repo root.
