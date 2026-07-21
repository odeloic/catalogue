---
name: triage
description: >-
  Fetch a Linear, GitHub, or GitLab issue and produce a normalized, read-only
  triage report with classification, context, related issues, and prior attempts.
  Use for issue URLs, bare ticket IDs, issue-like branch names, or requests to
  inspect, understand, classify, or triage an issue. Skip when a triage report
  already exists and the user only wants to act on it.
---

# triage

Normalize an issue from Linear, GitHub, or GitLab into a single JSON document that downstream skills (`fix-bug`, `ship-change`, `review-changes`) can consume without re-fetching.

## Inputs accepted
- Full URL (`linear.app/...`, `github.com/.../issues/N`, `gitlab.com/.../-/issues/N`, self-hosted variants).
- Bare ID (`ENG-123`, `#42`, `42`).
- Nothing — infer from the current branch (`eng-123-fix-thing` → `ENG-123`).

## How to invoke

1. Run `scripts/fetch-issue.sh <input-or-empty>`.
   - Writes the JSON document to `.claude/triage/<id>.json` and to stdout.
   - Strictly read-only: no comments, status changes, or assignments.
2. Linear path: the script exits `2` and prints `LINEAR:<id>` on stderr because it can't reach the MCP tool. When you see this:
   - Call the Linear MCP (`mcp__linear__get_issue` and related) for the issue, comments, and relations.
   - Build the same JSON shape (see schema below), write it to `.claude/triage/<id>.json` yourself.
   - If Linear MCP isn't connected, tell the user and stop.
3. Auth failure (`gh auth login` / `glab auth login` message on stderr): surface verbatim and stop.

## Classification (agent-side, after fetch)

Apply in order, stop at first hit, record which rule fired in `classification.rule`:
1. `issue_type` field (Linear has this natively).
2. Labels matching `bug`, `enhancement`, `feature`, `improvement`, `refactor`.
3. Title prefix: `fix:` → bug, `feat:` → feature, `refactor:` → improvement, `chore:` → change.
4. Description structure — "Steps to reproduce" / "Repro:" / "Expected vs Actual" → bug.
5. LLM judgment on title + description. Set `confidence: low`.

Then read the description and pull out acceptance criteria *with judgment*. They might be a checkbox list, a numbered list, a "Definition of done" section, a prose paragraph ("The user should be able to…"), or absent entirely. Don't try to parse — read it like a person and write each criterion as one entry in `acceptance_criteria[]`. If the issue has no AC, leave the array empty and add a note to the open-questions section.

## Output JSON shape

```
{
  source, id, url, title, author, assignee, status, labels,
  issue_type, description, acceptance_criteria[],
  comments[{author, at, body}],
  related[{relation, id, title, status, url}],
  prior_attempts[{type, url, title, state, author}],
  classification{type, rule, confidence}
}
```

Traversal: one hop only. Don't expand related-of-related unless the user explicitly asks.

Comment truncation: if `>100` comments, keep first 5 + last 10, set `comments_total` to the real count.

## Final report to the user

After writing the triage JSON, render a visual artifact. Follow the shared
routing rule in `../../.codex-plugin/references/rendering-artifacts.md`, resolved
relative to this `SKILL.md`.

### Artifact content

The report presents these fields — as designed HTML on the native path, or as the
`render-artifact.py` envelope below on the fallback path.

```bash
python3 <plugin-root>/.claude-plugin/scripts/render-artifact.py <<'ARTIFACT_EOF'
{
  "kind": "triage",
  "payload": {
    "id": "ENG-123",
    "title": "Issue title",
    "classification": "bug|feature|improvement|change|unknown",
    "confidence": "high|medium|low",
    "source": "Linear|GitHub|GitLab",
    "source_url": "https://...",
    "summary": "Two-sentence summary of what the issue is about.",
    "context": ["Concrete context bullet 1", "Bullet 2"],
    "acceptance_criteria": ["AC 1", "AC 2"],
    "related": [{"id": "ENG-100", "title": "...", "url": "..."}],
    "prior_attempts": [{"ref": "PR #42", "outcome": "closed", "notes": "..."}],
    "callouts": [{"type": "warning|danger|tip|info", "text": "..."}]
  }
}
ARTIFACT_EOF
```

Use `callouts` for: closed/duplicate issue warnings, missing AC, repro steps absent on a bug. Omit any field that doesn't apply.

**Do not include emojis in any content** (titles, summaries, descriptions, callouts, AC, notes). Both renderers style content with typography and color — emojis break the visual language.

Once the artifact is published/opened, print a one-line chat summary: classification + the artifact URL or path.

## Edge cases
- Closed or duplicate: surface prominently at the top of the summary — downstream skills may bail.
- Empty description: still classify (likely `low` confidence), flag in open questions.
- Cross-tracker link (Linear issue references a GitHub PR): record under `prior_attempts`, not `related`.

## Testing

Set `FETCH_ISSUE_MODE=fixture` and the script reads from `tests/fixtures/<source>/<id>.json` instead of hitting the network. Use this for unit tests of source detection and JSON shape.
