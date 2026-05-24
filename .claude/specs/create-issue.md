# Spec: `create-issue` skill

## Purpose
Draft a well-formed issue (bug, feature, improvement, or change) for Linear, GitHub, or GitLab, gathering missing information conversationally before drafting, applying the right template, and optionally filing the issue after user approval.

## Skill frontmatter description (the trigger contract)
> Draft and optionally file an issue to Linear, GitHub, or GitLab. Use when the user says "create an issue for X", "file a bug about Y", "make a ticket", or "open an issue". Detects the target tracker from repo remote or user-provided context, classifies the issue type, gathers missing required info conversationally, applies the right template, and produces a draft for review. Files the issue only after explicit user approval.

## Inputs
1. A free-form description of what the issue is about (always required).
2. Optional: target tracker (`linear`, `github`, `gitlab`) — otherwise detected.
3. Optional: type hint (`bug`, `feature`, `improvement`, `change`) — otherwise classified.
4. Optional: target team/project/repo (e.g., Linear team `ENG`, GitHub repo `owner/name`) — otherwise inferred.

## Workflow

### 1. Classify the issue type
Apply the reverse of the `triage-issue` classification ladder:
- Explicit user hint wins.
- Language signals: "bug", "broken", "crashes", "throws" → bug. "Add", "build", "implement" → feature. "Improve", "make faster", "clean up" → improvement. "Change how X works", "switch from A to B" → change.
- Description structure: presence of "steps to reproduce" or "expected vs actual" → bug.
- Ask the user if all signals conflict or are absent.

### 2. Detect target tracker
Call `detect-tracker.sh`. Decision order:
- Explicit user input wins.
- `git remote get-url origin` → `github.com` host → GitHub; `gitlab.com` or self-hosted GitLab → GitLab.
- If the user mentions a Linear team prefix (e.g., "for ENG") → Linear.
- If multiple are configured (mixed-tracker workflow), ask which one.

### 3. Gather missing required information
Each type has required fields. If a field is missing from the user's input, ask for it conversationally (one question at a time, not a form dump).

**Bug — required:**
- One-line summary
- Steps to reproduce (numbered)
- Expected behavior
- Actual behavior
- Environment (OS, browser, version, etc. — only ask if relevant to the context)

**Bug — nice to have:**
- Screenshots / logs / stack traces
- Frequency (always / sometimes / once)
- Severity from user's perspective
- Workaround if known

**Feature — required:**
- One-line summary
- User story or motivation (who needs this and why)
- Acceptance criteria (at least one)
- Scope (what's in)
- Non-goals (what's explicitly out)

**Improvement — required:**
- One-line summary
- Current state (what's there now)
- Desired state (what should be there)
- Motivation (why it's worth doing)
- Acceptance criteria

**Change — required:**
- One-line summary
- What's changing
- Why
- Impact / who's affected
- Migration considerations (if any)
- Backward-compatibility stance

Stop asking once required fields are filled. Don't grill the user — if they refuse to provide something, note "not provided" and move on.

### 4. Search for duplicates
Before drafting, search the target tracker for similar issues:
- Extract 3-5 keywords from the summary.
- Search via `gh issue list --search`, `glab issue list --search`, or Linear MCP search.
- If matches with high similarity exist, surface them and ask whether to proceed, link to the existing issue, or update it instead.

### 5. Apply template
Call `template-loader.sh <type> <tracker>`. Returns the markdown template for the type, adjusted for tracker-specific syntax (GitHub task lists, Linear formatting, GitLab quick actions).

### 6. Draft the issue
Fill the template with gathered information. Save to `.claude/drafts/issue-<timestamp>.md`. The draft includes a header block with target tracker, team/repo, and proposed labels — not in the issue body, but as metadata for the filing step.

### 7. Surface for review
Present the draft in chat. Wait for one of:
- **Approve and file** → call the appropriate tracker tool.
- **Edits requested** → revise the draft, re-surface.
- **Draft only, don't file** → save draft, exit.

### 8. File the issue (only if approved)
- **GitHub** — `gh issue create --title ... --body-file ... --label ...`.
- **GitLab** — `glab issue create --title ... --description ... --label ...`.
- **Linear** — call the Linear MCP `create-issue` tool with parsed fields.

Surface the created issue URL.

## Script: `scripts/detect-tracker.sh`
Single call. Returns JSON to stdout. Read-only.

Inspection sources:
- `git remote get-url origin` (and `upstream` if present).
- `.git/config` for any tracker-specific URLs.
- Presence of tracker config files: `.github/`, `.gitlab/`, `linear.toml` (uncommon).
- Recent commit messages and branch names for issue ID patterns.

Output:
```json
{
  "primary_tracker": "github|gitlab|linear|unknown",
  "evidence": ["remote.origin.url=https://github.com/owner/repo"],
  "secondary_signals": [
    { "tracker": "linear", "reason": "commit message references ENG-123" }
  ],
  "repo_identifier": "owner/repo",
  "confidence": "high|medium|low"
}
```

`primary_tracker: unknown` means ask the user.

## Script: `scripts/template-loader.sh <type> <tracker>`
Outputs the markdown template for the given type and tracker to stdout. Templates live in `references/templates/`.

The script is a thin shim — it picks the right file and prints it. Keeping it as a script (rather than the agent reading the file directly) means downstream tools can call it and get consistent output without re-implementing the lookup logic.

## Outputs
1. A draft markdown at `.claude/drafts/issue-<timestamp>.md` always — even if filed, the draft is kept for reference.
2. If filed: the created issue URL surfaced in chat.
3. Optional: write a back-reference into `.claude/triage/<id>.json` if this issue was created from an investigation that produced a triage report.

## Directory layout
```
skills/issue-management/create-issue/
├── SKILL.md
├── scripts/
│   ├── detect-tracker.sh
│   └── template-loader.sh
├── references/
│   ├── templates/
│   │   ├── bug-github.md
│   │   ├── bug-gitlab.md
│   │   ├── bug-linear.md
│   │   ├── feature-github.md
│   │   ├── feature-gitlab.md
│   │   ├── feature-linear.md
│   │   ├── improvement-*.md
│   │   └── change-*.md
│   ├── github.md                       # gh issue create syntax, labels, projects
│   ├── gitlab.md                       # glab issue create syntax, quick actions
│   ├── linear.md                       # Linear MCP create-issue payload shape
│   └── duplicate-search.md             # search strategies per tracker
└── tests/
    └── fixtures/                        # sample inputs + expected drafts
```

## Edge cases
- **Insufficient info for a bug** — ask iteratively (one question per turn). If user provides no repro after asking twice, mark "not provided" and proceed.
- **No target tracker detectable** — ask the user; do not guess.
- **Multiple trackers configured** — ask which one; cache the choice per session.
- **Linear MCP not connected** but Linear is target — save draft, surface instructions for filing manually, do not attempt to file.
- **Auth missing** — surface clear `gh auth login` / `glab auth login` message; save the draft regardless.
- **Likely duplicate found** — surface and pause; let the user decide whether to proceed.
- **User wants a draft only** (no filing) — respect it; save and exit.
- **Description maps to multiple types** (e.g., "fix the slow query" is bug + improvement) — pick one as primary, mention the secondary in the body, surface the choice.
- **Tracker rejects the issue** (rate limit, permission denied, validation error) — keep the draft, surface the error verbatim.
- **Self-hosted GitHub/GitLab** — detect via remote URL host; require the corresponding CLI to be configured for that host.

## Testing approach
Fixture-based: a set of sample user inputs across all four types and three trackers under `tests/fixtures/`. Run `detect-tracker.sh` against repos with different remote configurations. Snapshot-test the generated draft markdown against expected templates. The conversational gather step is harder to test — keep it to unit tests of the "which required field is still missing" logic.
