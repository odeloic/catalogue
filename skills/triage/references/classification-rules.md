# Classification rules

The ladder used to set `classification.type` and `classification.rule`. Apply in order, stop at the first hit. Record which rule fired so downstream skills can decide how much to trust the result.

## Types

- `bug` — something is broken, behaves wrong, or regresses.
- `feature` — new capability that didn't exist before.
- `improvement` — refinement of an existing feature (perf, UX polish, refactor that's user-visible).
- `change` — operational / config / docs / dependency work.
- `unknown` — no rule fired and even the LLM judgment was low-confidence.

## Ladder

### 1. Native `issue_type`

If the tracker has a typed field, trust it.

- Linear `issueType.name`: `Bug` → `bug`, `Feature` → `feature`, `Improvement` → `improvement`, `Task` → `change`.
- GitLab `issue_type`: `incident` → `bug`, `issue` → falls through to next rule, `task` → `change`.

Set `rule: "issue_type"`, `confidence: "high"`.

### 2. Labels

Match (case-insensitive) against known patterns:

| Type | Label patterns |
| --- | --- |
| `bug` | `bug`, `defect`, `regression`, `crash`, `error` |
| `feature` | `feature`, `enhancement`, `new` |
| `improvement` | `improvement`, `refactor`, `polish`, `tech debt`, `perf` |
| `change` | `chore`, `docs`, `deps`, `infra`, `ops` |

If multiple labels match different types, take the first one in the list above (bug > feature > improvement > change). Set `rule: "label"`, `confidence: "high"`.

### 3. Title prefix

Conventional-commit style at the start of the title:

| Prefix | Type |
| --- | --- |
| `fix:`, `bug:`, `hotfix:` | `bug` |
| `feat:`, `feature:` | `feature` |
| `refactor:`, `perf:`, `improve:` | `improvement` |
| `chore:`, `docs:`, `build:`, `ci:`, `deps:` | `change` |

Set `rule: "title_prefix"`, `confidence: "high"`.

### 4. Description structure

Look in the description body for these structural cues:

- Headings like `## Steps to reproduce`, `## Repro`, `## Expected vs actual`, `## Actual behavior` → `bug`.
- Headings like `## User story`, `## As a … I want …`, `## Motivation` → `feature`.

Set `rule: "description_structure"`, `confidence: "medium"`.

### 5. LLM judgment

Read title + description, decide best fit. Set `rule: "llm_judgment"`, `confidence: "low"`.

If even the LLM can't pick confidently, set `type: "unknown"` and add this to the "open questions for the author" section in the final summary.

## Examples

| Title | Labels | issue_type | Result | Rule |
| --- | --- | --- | --- | --- |
| "Login redirects to /404" | `bug` | — | `bug` | label |
| "feat: dark mode toggle" | — | — | `feature` | title_prefix |
| "Add dark mode" | `enhancement` | — | `feature` | label |
| "Improve search latency" | — | — | `improvement` | llm_judgment (low) |
| "Update README" | `docs` | — | `change` | label |
| "Steps to reproduce: open app, click X…" (no labels, no prefix) | — | — | `bug` | description_structure |
| "Architecture: Workflow → Agent" | `architecture` | — | `unknown` then `improvement` (low) | llm_judgment |

## Confidence guidance for downstream skills

- `high` — `fix-bug` / `ship-change` can dispatch without re-asking.
- `medium` — proceed, but flag in the PR description.
- `low` — `fix-bug` should confirm with the user before acting.
