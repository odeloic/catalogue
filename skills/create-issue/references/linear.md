# Linear

How to create an issue via the Linear MCP.

## Tool to call

The Linear MCP exposes a create-issue tool. The exact name depends on the MCP server build, but it's typically `mcp__linear__create_issue`. **Do not assume it's connected** — check the available MCP tool list in the current session before calling. If no Linear MCP create tool is available:

1. Save the draft as usual (`.claude/drafts/issue-<ts>.md`).
2. Tell the user the Linear MCP isn't connected; give them the draft path and the team/project metadata so they can paste it into Linear manually.
3. Do not attempt any other Linear API call.

## Payload shape

The tool generally expects something like:

```json
{
  "title": "<title>",
  "description": "<markdown body>",
  "team": "<team key or id>",
  "labels": ["<label>", "<label>"],
  "priority": 0,
  "assignee": "<user id or email>",
  "project": "<project id>"
}
```

Field notes:

| Field | Notes |
| --- | --- |
| `title` | Required. |
| `description` | Markdown. Linear doesn't run GitHub-style task lists the same way; checkboxes still render but quick actions don't apply. |
| `team` | Required. The team key (e.g. `ENG`) or team UUID. Without one, the call fails. |
| `labels` | Array of label names. Labels are team-scoped — ones that don't exist may be created or rejected depending on the MCP build. |
| `priority` | Integer 0-4: 0=no priority, 1=urgent, 2=high, 3=medium, 4=low. |
| `assignee` | User identifier the MCP accepts. Often email or UUID. |
| `project` | Optional project UUID. |

## Determining the team

If the user didn't say which team, ask. The detect step can surface a team key from branch / commit prefixes (e.g. `ENG-123`) but only as a suggestion — confirm with the user before filing.

## After filing

The MCP tool returns the issue URL (e.g. `https://linear.app/<workspace>/issue/ENG-456/...`). Surface it.

## Errors to handle

- MCP returns an auth or unknown-team error: keep the draft, surface the error.
- Label rejected: drop it and retry, or surface and stop. Don't silently rename labels.
