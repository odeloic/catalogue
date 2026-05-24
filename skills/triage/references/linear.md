# Linear

`fetch-issue.sh` cannot reach the Linear MCP — shell scripts have no path to MCP tools. When the script detects a Linear input it exits `2` with `LINEAR:<id>` on stderr. The agent then takes over.

## Handoff protocol

```
$ scripts/fetch-issue.sh ENG-123
LINEAR:ENG-123
$ echo $?
2
```

The agent must:

1. Call the Linear MCP for the issue, comments, and relations.
2. Build the same JSON shape documented in `SKILL.md`.
3. Write it to `.claude/triage/<id>.json` (same destination the script uses for GitHub/GitLab).
4. Continue with classification and the user-facing summary.

If Linear MCP isn't connected: report it to the user and stop. Don't fall back to a manual fetch — there's no equivalent CLI.

## MCP tools to use

Tool names depend on which Linear MCP server is connected. The standard `@modelcontextprotocol/server-linear` exposes:

| Tool | Purpose |
| --- | --- |
| `mcp__linear__get_issue` | Issue body, status, assignee, labels, `issueType`, relations |
| `mcp__linear__list_comments` (or `get_issue_comments`) | All comments |
| `mcp__linear__search_issues` | Prior implementation attempts — search by ID, branch name, or related keywords |

If the actual tool names differ (custom server, older version), check the system reminder for what's available and adapt. Don't guess names that aren't listed.

## Field mapping

Linear field → normalized shape:

| Normalized | Linear |
| --- | --- |
| `source` | `"linear"` |
| `id` | `issue.identifier` (e.g. `ENG-123`) |
| `url` | `issue.url` |
| `title` | `issue.title` |
| `author` | `issue.creator.name` |
| `assignee` | `issue.assignee.name` or null |
| `status` | `issue.state.name` |
| `labels` | `[issue.labels[].name]` |
| `issue_type` | `issue.issueType.name` if present, else `null` |
| `description` | `issue.description` (markdown) |
| `comments[]` | `{author: c.user.name, at: c.createdAt, body: c.body}` |
| `related[]` | from `issue.relations[]`: `{relation, id, title, status, url}` |
| `prior_attempts[]` | branches + PRs linked on the issue (Linear surfaces these under `attachments` or `gitBranches`) |

`relation` values map roughly: Linear's `blocks` → `blocks`, `blocked_by` → `blocked_by`, `duplicate_of` → `duplicate`, parent/sub-issue → `parent` / `child`, everything else → `related`.

## Edge cases

- Sub-issues: walk `parent` one hop only by default. Don't recursively expand unless the user asks.
- Cross-tracker: a Linear issue often links to a GitHub PR via `attachments[]`. Record those as `prior_attempts`, not `related`.
- Auto-close on merge: if the Linear status is `Done` and there's a merged PR in `prior_attempts`, surface this prominently — the issue may already be shipped.
