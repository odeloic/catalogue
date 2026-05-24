# Spec: `review-changes` skill

## Purpose
Review a PR/MR (or a local branch's diff) against the original issue context and acceptance criteria, producing a structured, actionable review. The skill reuses `triage-issue` to pull issue context, runs a code-quality pass over the diff, verifies acceptance criteria, and emits a review grouped by severity.

## Skill frontmatter description (the trigger contract)
> Review a pull/merge request or local branch diff against its originating issue. Use when the user provides a PR/MR URL, a branch name, or says "review this PR", "look at these changes", "review the diff on branch X". Reuses `triage-issue` for issue context. Produces a structured review with AC verification, quality findings grouped by severity, and a recommendation.

## Inputs
1. A PR/MR URL (`https://github.com/owner/repo/pull/N`, `https://gitlab.com/.../-/merge_requests/N`).
2. A branch name — compared against the default branch (or a user-specified base).
3. A raw diff piped in or written to a file — less common, supported as a fallback.

## Workflow

### 1. Fetch PR context
Call `fetch-pr-context.sh <input>`. Returns a normalized JSON with diff, metadata, linked issues, CI status, and size metrics. The script handles source detection (GitHub via `gh`, GitLab via `glab`) and produces the same shape regardless of source.

### 2. Resolve issue context
For each linked issue ID in the PR context:
- Invoke `triage-issue` to get the triage JSON. This produces (or reuses) `.claude/triage/<issue-id>.json`.
- Extract acceptance criteria and prior attempts for use later in the workflow.

If no issue is linked, skip AC verification and note this in the review explicitly.

### 3. Pre-flight checks
Before the quality pass, surface blockers that should be addressed before review:
- CI failing — surface prominently; recommend fixing CI before review proceeds. Don't try to debug CI for the user.
- PR is a draft — adjust tone to exploratory rather than prescriptive; mark the review as preliminary.
- PR depends on an unmerged PR — flag the dependency; recommend reviewing in order.
- PR is very large (>500 lines added, >20 files) — declare review coverage explicitly and focus on high-risk areas rather than line-by-line.

### 4. Code quality pass
Walk the diff and identify findings across these dimensions:
- **Correctness** — likely defects, off-by-one, null/undefined paths, race conditions.
- **Error handling** — unhandled rejections, swallowed errors, missing edge cases.
- **Security** — input validation, auth checks, secret handling, injection vectors.
- **Performance** — N+1 queries, unbounded loops, sync work on hot paths.
- **Tests** — coverage of new behavior, brittle assertions, missing failure-case tests.
- **Style consistency** — matches the codebase's conventions (not the agent's preferences).
- **Scope creep** — changes unrelated to the stated issue.

Each finding records: file:line, what's wrong, why it matters, a concrete suggestion.

### 5. AC verification
For each acceptance criterion from the triage report, classify as:
- **Met** — diff clearly satisfies the criterion.
- **Partial** — diff addresses the criterion but with gaps.
- **Missing** — no evidence in the diff.
- **Not verifiable from diff** — requires runtime verification, manual testing, or external context.

### 6. Run tests (optional, based on user preference)
If the user opts in, run the test suite locally and surface failures. Don't run tests by default — it's slow and the agent shouldn't assume the env is set up.

### 7. Compose review
Group findings by severity:
- **Blocker** — must be addressed before merge (correctness bugs, security issues, missing AC).
- **Major** — should be addressed but not strictly blocking (significant smells, missing tests for new behavior).
- **Minor** — worth addressing but acceptable to defer (refactoring opportunities, mild inconsistencies).
- **Nit** — purely stylistic, take it or leave it.

End with a recommendation: `approve`, `request_changes`, or `comment`.

### 8. Write outputs
Save the review markdown. Surface a condensed version in chat.

## Script: `scripts/fetch-pr-context.sh <url-or-branch>`
Single entry point. Detects source, dispatches, writes normalized JSON to stdout. Read-only.

Source detection:
- URL contains `github.com` (or configured GH Enterprise host) → GitHub via `gh`.
- URL contains `gitlab.com` (or self-hosted GitLab) → GitLab via `glab`.
- Bare branch name → use `git remote get-url origin` to determine source, then look up PR/MR by head ref.

Per-source behavior:
- **GitHub** — `gh pr view <n> --json ...`, `gh pr diff <n>`, `gh pr checks <n>` for CI, `gh pr view <n> --json closingIssuesReferences` for linked issues.
- **GitLab** — `glab mr view <n>`, `glab mr diff <n>`, CI status via `glab ci status`. Linked issues parsed from MR description.
- **Local branch fallback** — `git diff <base>...<head>`, plus regex-based extraction of issue IDs from commit messages and branch name.

Output JSON:
```json
{
  "source": "github|gitlab|local",
  "id": "string",
  "url": "string",
  "title": "string",
  "author": "string",
  "is_draft": false,
  "base": { "ref": "main", "sha": "..." },
  "head": { "ref": "feature/x", "sha": "..." },
  "diff": "unified diff string",
  "files_changed": [
    { "path": "src/foo.ts", "added": 12, "removed": 3, "status": "modified" }
  ],
  "linked_issues": [
    { "id": "ENG-123", "source": "linear", "url": "..." }
  ],
  "ci": {
    "status": "success|failure|pending|none",
    "checks": [
      { "name": "build", "status": "success", "url": "..." }
    ],
    "failures": ["..."]
  },
  "size_metrics": {
    "lines_added": 142,
    "lines_removed": 27,
    "files_count": 8,
    "size_class": "small|medium|large|xlarge"
  },
  "depends_on": ["#789"]
}
```

`size_class` thresholds (tune to your taste):
- small: ≤100 added, ≤5 files
- medium: ≤300 added, ≤10 files
- large: ≤500 added, ≤20 files
- xlarge: anything beyond

## Outputs
1. A review markdown at `.claude/reviews/<pr-id>.md` with sections:
   - Summary (1 paragraph, what the PR does)
   - Recommendation (approve / request_changes / comment) with one-line reasoning
   - AC verification table (criterion → status → evidence)
   - CI status (just surface, don't debug)
   - Findings grouped by severity, each with file:line and actionable suggestion
   - Open questions for the author
   - Coverage note (for large PRs: what was reviewed in depth vs. skimmed)
2. Updated triage JSON for each linked issue:
```json
"reviews": [
  { "pr_url": "...", "review_path": "...", "recommendation": "...", "at": "ISO-8601" }
]
```
3. Chat output: condensed version — recommendation, AC summary, top blockers/majors, link to the full review file.

## Directory layout
```
skills/code-review/review-changes/
├── SKILL.md
├── scripts/
│   └── fetch-pr-context.sh
├── references/
│   ├── github.md                       # gh commands, auth, enterprise host config
│   ├── gitlab.md                       # glab commands, self-hosted notes
│   ├── review-checklist.md             # quality dimensions in detail
│   ├── severity-levels.md              # blocker / major / minor / nit definitions
│   └── pr-size-heuristics.md           # how to scope review depth by size
└── tests/
    └── fixtures/                        # canned PR JSONs + diffs per source
```

The `github.md` and `gitlab.md` references duplicate content from `triage-issue`. Consider symlinking or extracting to a shared `skills/_shared/references/` if you want one source of truth.

## Edge cases
- **No linked issue** — skip AC verification, note explicitly in the review, focus on code quality.
- **CI failing** — surface prominently; recommend fixing CI first. The skill does not attempt to diagnose CI failures.
- **Draft PR** — mark review as preliminary, adjust tone to exploratory.
- **Very large PR** — focus on high-risk areas (auth, payments, migrations, public APIs, data integrity), declare coverage explicitly in the output.
- **PR depends on unmerged PR** — flag the dependency, recommend reviewing in dependency order, note that findings may shift once the dependency lands.
- **PR touches sensitive files** (auth, payments, migrations, security boundaries) — flag for extra scrutiny in the review header.
- **Self-review** (author requesting their own review) — proceed but note the self-review limitation; suggest a second reviewer for blockers.
- **Issue is closed or duplicated** — surface this and ask the user whether to proceed before doing AC verification.
- **No diff available** (branch already merged, force-pushed without local copy) — halt with a clear error.

## Testing approach
Fixture-based: canned PR responses per source (GitHub, GitLab) under `tests/fixtures/`, plus a few representative diffs (small bugfix, medium feature, large refactor). Run `fetch-pr-context.sh` with `FETCH_PR_MODE=fixture` and assert the JSON shape. For severity classification, snapshot-test against known diffs with annotated expected findings.
