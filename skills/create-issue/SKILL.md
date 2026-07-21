---
name: create-issue
description: >-
  Draft a well-formed issue for Linear, GitHub, or GitLab by detecting the
  tracker, classifying the request, gathering required fields, checking for
  duplicates, and applying a template. Files only after explicit approval. Use
  when the user asks to create, open, file, log, raise, draft, or write up an
  issue, bug, feature request, or ticket. Skip when acting on an existing issue
  or when the user only wants a code change.
---

# create-issue

Draft a well-formed issue, gather missing required info, surface for review, and file only after approval.

## Workflow

1. **Classify the type.** Reverse of `triage`'s ladder: explicit hint → language signals (`bug` / `broken` / `crashes` → bug; `add` / `build` → feature; `improve` / `cleanup` → improvement; `change how X works` → change) → description structure (repro steps → bug). Ask if signals conflict or are absent.
2. **Detect the tracker.** Run `scripts/detect-tracker.sh`. Decision order: explicit user input → `primary_tracker` from the script → ask if `unknown`. If the user mentions a Linear team prefix (e.g. "for ENG"), prefer Linear regardless of remote.
3. **Gather missing required fields** (one question per turn, not a form dump). Stop once required fields are filled. If the user refuses, note `not provided` and proceed.
4. **Search for duplicates.** Extract 3-5 keywords from the summary, search the tracker (see `references/duplicate-search.md`). Surface top 3 matches, pause for user decision before drafting.
5. **Apply template.** Run `scripts/template-loader.sh <type> <tracker>`. Fill it.
6. **Save draft.** Write to `.claude/drafts/issue-<timestamp>.md` (e.g., `issue-20260524-153012.md`). Include a metadata header with target tracker, repo/team, proposed labels — separate from the body.
7. **Surface for review.** Wait for one of: approve and file / edits requested / draft only.
8. **File** (only if approved):
   - GitHub: `gh issue create --title ... --body-file <draft> --label ...`
   - GitLab: `glab issue create --title ... --description ... --label ...`
   - Linear: call the Linear MCP create-issue tool with the parsed fields. If the MCP isn't connected, save the draft and surface manual filing instructions — do not attempt to file.

Always keep the draft on disk, even after filing.

## Required fields per type

- **bug**: summary, steps to reproduce (numbered), expected, actual, environment (when relevant).
- **feature**: summary, user story / motivation, acceptance criteria (>=1), scope, non-goals.
- **improvement**: summary, current state, desired state, motivation, acceptance criteria.
- **change**: summary, what's changing, why, impact, migration considerations, backward-compatibility stance.

Nice-to-haves for bugs: screenshots/logs, frequency, severity, workaround. Ask only if cheap.

## Tracker detection signals (from `detect-tracker.sh`)

- `git remote get-url origin` / `upstream` host (`github.com` → github, `gitlab.com` / self-hosted gitlab → gitlab).
- `.github/` or `.gitlab/` directory presence.
- Linear-style team prefix (`[A-Z]+-[0-9]+`) in last ~20 commit messages or the current branch name → secondary Linear signal.
- `primary_tracker` is `unknown` when nothing matches; ask the user.

## Edge cases

- **Multiple trackers configured** (e.g., GitHub remote + Linear commit prefixes) — ask which one, cache the choice for the session.
- **No tracker detected** — ask; do not guess.
- **Linear MCP not connected** but Linear is target — keep the draft, surface manual filing instructions.
- **Auth missing** (`gh auth login` / `glab auth login`) — surface verbatim; keep the draft.
- **Duplicate found** — pause, surface top matches, let the user choose (proceed / link / update).
- **Draft only** — respect, save, exit.
- **Description maps to multiple types** — pick one primary, mention the other in the body, surface the choice.
- **Tracker rejects the issue** (rate limit, validation) — keep the draft, surface the error verbatim.
- **Self-hosted GitHub/GitLab** — detect by host; require the corresponding CLI configured for that host.

## References

- `references/github.md` — `gh issue create` syntax and flags.
- `references/gitlab.md` — `glab issue create` syntax and quick actions.
- `references/linear.md` — Linear MCP create payload shape.
- `references/duplicate-search.md` — keyword extraction and per-tracker search.

## Testing

`tests/test-detect-tracker.sh` covers tracker detection via `DETECT_TRACKER_FIXTURE_REMOTE` and validates `template-loader.sh` argument handling.
