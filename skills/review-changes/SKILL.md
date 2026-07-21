---
name: review-changes
description: Review a pull/merge request or local branch diff against its originating issue's acceptance criteria and against the code itself. Groups findings by sub-project in a monorepo, anchors every finding to the diff line it is about, and writes a ready-to-paste draft comment for each one. Emits a recommendation (`approve` / `request_changes` / `comment`). Reuses `triage` for issue context. Supports `[show-fix]` to add proposed fixes and `[reproduce]` to verify findings by running them.
when_to_use: When the user pastes a PR URL (`github.com/.../pull/N`), an MR URL (`gitlab.com/.../-/merge_requests/N`), a branch name to compare against the default branch, or says "review this PR", "review this MR", "code review for X", "look at these changes", "review the diff on branch X", "what do you think of #123", "review the diff", or "audit this PR". SKIP for pure style/lint pointers (use a linter) or when the user wants you to write the code, not review it.
---

# review-changes

Review a PR/MR (or a branch diff) against the linked issue's acceptance criteria and against the code. Group findings by sub-project. Anchor every finding to the diff line it is about. Give every finding a comment the author can paste into the thread.

Depends on `triage` (`[[triage]]`) for issue context. `references/github.md` and `references/gitlab.md` cover the PR/MR commands.

## Flags

Read these from the user's message. They can appear anywhere in it.

| Flag | Default | Effect |
| --- | --- | --- |
| `[show-fix]` | off | Add a proposed-fix diff to each finding. |
| `[reproduce]` | off | Verify findings by running them, and paste the real output. |

Without `[show-fix]`: say what is wrong and let the author choose the fix. Do not sketch one in prose instead — that is the same thing, longer.

Without `[reproduce]`: never write repro steps. Point at the diff. If a finding only holds when something is true at runtime, say which part you could not check.

## Inputs accepted

In priority order:
1. PR URL — `https://github.com/owner/repo/pull/N`
2. MR URL — `https://gitlab.com/group/project/-/merge_requests/N`
3. Branch name — diffed against the default branch, or a base the user names
4. Raw unified diff — fallback when no PR/MR exists

## How to invoke

1. Run `scripts/fetch-pr-context.sh <input>`. It writes normalized context to stdout and to `.claude/reviews/<id>.context.json`. Read-only — it never comments or approves.
2. For each `linked_issues[].id`, invoke `triage` to produce or reuse `.claude/triage/<issue-id>.json`. You invoke triage; the script does not.
3. If triage fails, say so and ask whether to continue without AC checks.
4. Auth errors from `gh` / `glab` surface verbatim and halt.

## Workflow

### 1. Fetch context

Capture `linked_issues`, `ci`, `is_draft`, `size_metrics`, `depends_on`, `diff`, `files_changed`.

### 2. Resolve the issue

Read each triage JSON's `acceptance_criteria[]` and `prior_attempts[]`. No linked issue — skip AC checks and say so in the header.

### 3. Pre-flight

Flag these before reading code. One line each, no diagnosis.

| Condition | What to say |
| --- | --- |
| CI failing | Fix CI first. Do not debug it here. |
| Draft PR | Review is preliminary. Ask rather than prescribe. |
| `depends_on` non-empty | Review the dependency first; findings may shift. |
| `size_class` is `large` / `xlarge` | State what you read closely and what you skimmed. See `references/pr-size-heuristics.md`. |
| Path matches `auth`, `payment`, `migration`, `security`, `iam`, `crypto`, `secret` | Read those files line by line. |
| Author is the requesting user | Continue, but ask for a second reviewer on any blocker. |
| Linked issue closed or duplicate | Surface it and ask before continuing. |

Skip the whole section if none apply.

### 4. Split by sub-project

Group `files_changed[]` by the project that owns each path:

1. Walk up from the file and take the first directory holding a project manifest — `package.json`, `pubspec.yaml`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `pom.xml`, `build.gradle`, `composer.json`, `Gemfile`, `*.csproj`.
2. No manifest anywhere above it — use the first path segment.
3. Files at the repo root (CI config, lockfiles, docs) — group them as `repo root`, listed last.

One group means a single-project repo: drop the grouping and never mention it.

Name each group by its directory (`web/bereich-a`, `backend/API`), not by framework. Give each a short prefix from the path so findings get a referenceable ID: `backend/API` → `BE-1`, `web/bereich-a` → `BA-1`. Order groups by their worst severity, then by file count.

**Generated files.** Paths under `__generated__/`, or matching `*.generated.*`, `*.g.dart`, `*.pb.go`, exported `schema.graphql`, and lockfiles: do not read line by line. Check only that they match their source and were produced by the project's own codegen command. At most one finding for all of them, in the group that owns them.

**Cross-project findings.** When a change in one project breaks another, the finding belongs to the project that breaks, and names the other one in the first sentence.

### 5. Review the diff

Walk the diff against the seven dimensions in `references/review-checklist.md`: correctness, error handling, security, performance, tests, style consistency, scope creep.

Then check each acceptance criterion and classify it:

- **Met** — the diff clearly does it.
- **Partial** — done, with gaps. Name the gap.
- **Missing** — no evidence in the diff.
- **Can't tell from the diff** — needs a runtime check or context you do not have.

Cite `file:line` or "no evidence in diff" for every row.

**Scope guard.** A finding's file must appear in `files_changed[]`. Files you opened for context — callers, helpers, imports — are there to help you judge the diff, not to be reviewed. If something outside the diff looks wrong, drop it; it is a separate conversation. The one exception: a diff line that depends on broken out-of-diff behaviour. Then the finding sits on the diff line, not the other file.

### 6. Reproduce — only with `[reproduce]`

Skip this phase entirely unless the flag is set.

With it: start what the change needs, trigger the path, and capture the real output — the command and its response, the log line, the DOM node, the row count. Then undo any test data you created and confirm the working tree is clean.

If you cannot run it, say which finding is unverified and why. Do not write steps you did not execute.

### 7. Write the findings

Every finding carries:

| Part | When | Rule |
| --- | --- | --- |
| ID | always | `<group-prefix>-<n>`, numbered worst-first within the group |
| Severity | always | `references/severity-levels.md` |
| `file:line` | always | must be in `files_changed[]` |
| What's wrong | always | 1–2 sentences, 40 words max |
| Diff | always | the hunk from the PR this is about, unedited |
| Draft comment | always | 60 words max, ends with a question |
| Proposed fix | `[show-fix]` | a diff, never prose |
| Reproduction | `[reproduce]` | output you actually captured |

**The diff is the anchor.** Show the changed lines the finding is about, straight from the PR. If you cannot point at a changed line, it is not a finding on this PR — drop it.

**Draft comment.** Written as you, speaking to the author, ready to paste with no edits. Name what breaks, then ask for what you want. No opener ("Nice work, but…"), no summary of the code they wrote, no instruction voice. Two or three sentences.

Good:

> `fetch` resolves on 4xx, so the `.catch` fallback never runs — a 404 body gets parsed and rendered instead. I hit this on every Antrag with the current dump. Can you check `res.ok` before reading the body?

Bad:

> It is worth noting that the current implementation of the icon fetching logic does not perform any validation of the HTTP response status prior to consuming the response body, which could potentially lead to unexpected behaviour in certain edge cases. It might be beneficial to consider adding appropriate error handling.

### 8. Recommendation and outputs

Pick one, per the table in `references/severity-levels.md`:

- Any Blocker, or a Missing AC on a non-draft PR → `request_changes`
- Unresolved Majors or ambiguous AC → `comment`
- Neither, and all AC Met or can't-tell-with-a-note → `approve`

**Scope check before writing.** Walk every finding and confirm its file is in `files_changed[]`. Drop the ones that are not — do not relocate them, do not soften them. If `files_changed[]` is empty (raw diff), build the set from the `+++ b/<path>` lines.

Then:

- Write `.claude/reviews/<pr-id>.md`.
- Append to each linked issue's `.claude/triage/<issue-id>.json` under `reviews[]`:
  `{ "pr_url": "...", "review_path": "...", "recommendation": "...", "at": "ISO-8601" }`
- Render the artifact (below).
- Print one line in chat: recommendation, counts by severity, artifact link.

## Writing rules

The reader is skimming to decide what to do next. Give them that and stop.

- Lead with the problem. The first sentence names what breaks.
- One idea per sentence. Cut any clause that does not change what the reader does.
- Plain words: *sends* not *dispatches*, *breaks* not *is non-functional*, *before* not *prior to*, *use* not *leverage*, *about* not *regarding*, *so* not *thereby*, *lets you* not *facilitates*.
- Do not describe code the diff already shows.
- Do not stack hedges. "might possibly potentially" → "might".
- Cut fillers: *It is worth noting that*, *As mentioned above*, *In order to*, *At the end of the day*, *This is a good opportunity to*, *Please be aware that*.
- Say "I could not check X" rather than writing around it.
- No emojis anywhere.

Budgets: finding prose 40 words, draft comment 60 words, summary 3 sentences, recommendation reason 1 line. Over budget means the diff should be carrying it.

## Review markdown structure

1. **Summary** — what the PR does. Three sentences max.
2. **Recommendation** — the call plus one line of reason.
3. **Pre-flight** — only if something is flagged.
4. **Acceptance criteria** — table: criterion, status, evidence. Or "no linked issue".
5. **Findings by sub-project** — one section per group, findings worst-first, each with its diff and draft comment.
6. **Open questions** — anything the diff left ambiguous.
7. **Coverage** — for large PRs: read closely vs. skimmed.

## Render artifact

Follow the routing rule in `${CLAUDE_SKILL_DIR}/../../.claude-plugin/references/rendering-artifacts.md`: run the detector, then use Claude Code's native Artifact (guided by `artifact-design`) when enabled, or the bundled `render-artifact.py` when it is not.

On the native path, build the page so each sub-project is its own tab or section, and each finding shows its diff and its draft comment as separate blocks — the draft comment should be copyable on its own.

```bash
python3 ${CLAUDE_SKILL_DIR}/../../.claude-plugin/scripts/render-artifact.py <<'ARTIFACT_EOF'
{
  "kind": "review",
  "payload": {
    "pr_title": "feat: add X",
    "pr_url": "https://github.com/.../pull/N",
    "issue_ref": "ENG-123",
    "branch": "feat/x",
    "files_changed": 14,
    "recommendation": "approve|request_changes|comment",
    "summary": "What the PR does.",
    "acceptance_criteria": [
      {"criterion": "AC text", "status": "met|partial|missed", "note": "file:line or why not"}
    ],
    "subprojects": [
      {
        "name": "web/bereich-a",
        "files_changed": 3,
        "findings": [
          {
            "id": "BA-1",
            "severity": "high|medium|low|info",
            "title": "Short title",
            "file": "web/bereich-a/src/x.tsx",
            "line": 118,
            "detail": "What breaks, in one or two sentences.",
            "diff": [
              {"type": "context", "text": "fetch(url)"},
              {"type": "remove", "text": "  .then((res) => res.text())"},
              {"type": "add", "text": "  .then((res) => { if (!res.ok) throw new Error(); return res.text(); })"}
            ],
            "draft_comment": "Ready-to-paste comment, ending in a question.",
            "fix": [{"type": "add", "text": "only when [show-fix] is set"}],
            "repro": "only when [reproduce] is set; real captured output"
          }
        ]
      }
    ],
    "open_questions": ["Question for the author"]
  }
}
ARTIFACT_EOF
```

Severity map: Blocker → `high`, Major → `medium`, Minor → `low`, Nit → `info`.

Single-project repo: emit one `subprojects` entry with no `name`. The renderer drops the header. A flat top-level `findings[]` also still works.

Omit `fix` and `repro` unless their flag was set. Omit any field that does not apply. No emojis in any value.

## Edge cases

| Case | Do |
| --- | --- |
| No linked issue | Skip AC checks, say so, focus on the code. |
| CI failing | Surface it. Do not diagnose. |
| Draft PR | Mark preliminary, ask instead of prescribe. |
| Very large PR | Declare coverage; prioritise per `references/pr-size-heuristics.md`. |
| Depends on unmerged PR | Flag it; note findings may shift. |
| Sensitive paths | Read line by line. |
| Self-review | Continue, ask for a second reviewer on blockers. |
| Issue closed or duplicate | Surface and ask first. |
| No diff available | Halt with a clear error. |
| Raw diff, no PR | No `ci` / `linked_issues` / `depends_on`. Skip AC unless the user gives an issue ID. |
| Diff is only generated files | One finding at most: are they in sync with their source? |

## Testing

Set `FETCH_PR_MODE=fixture` and the script reads `tests/fixtures/<source>/<id>.json` instead of calling `gh` / `glab` / `git`. Run `tests/test-fetch-pr-context.sh` from the repo root.
