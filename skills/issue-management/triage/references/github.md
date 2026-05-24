# GitHub

Commands `fetch-issue.sh` runs against the `gh` CLI, and how to set up auth.

## Auth

`gh auth status` is checked before any fetch. If it fails:

```
GitHub auth missing. Run: gh auth login
```

For GitHub Enterprise hosts, `gh auth login --hostname <host>` and `gh` picks the right token based on the remote URL.

## Commands

All commands take `-R owner/repo` when the input is a URL. When the input is a bare number, `gh` falls back to the cwd repo.

| Purpose | Command |
| --- | --- |
| Issue body + metadata | `gh issue view <id> [-R owner/repo] --json number,title,author,assignees,state,labels,body,url,createdAt,updatedAt,closedAt` |
| Comments | `gh issue view <id> [-R owner/repo] --json comments` |
| Prior PRs | `gh pr list [-R owner/repo] --search "<id> in:title,body" --state all --json number,title,url,state,author,isDraft --limit 20` |

## JSON → normalized shape

| Output field | Source |
| --- | --- |
| `source` | `"github"` |
| `id` | `issue.number` as string |
| `url` | `issue.url` |
| `title` | `issue.title` |
| `author` | `issue.author.login` |
| `assignee` | first of `issue.assignees[].login`, or null |
| `status` | `issue.state` lowercased (`open` / `closed`) |
| `labels` | `[issue.labels[].name]` |
| `issue_type` | `null` (GitHub has no native field) |
| `description` | `issue.body` |
| `comments[]` | `{author: c.author.login, at: c.createdAt, body: c.body}` |
| `prior_attempts[]` | one per PR: `{type: "pr", url, title, state, author}`. `state` is `"draft"` if `isDraft`, else `state` lowercased. |

## Comment truncation

If `comments_total > 100`, keep `[0..5] + [-10..]` and set `comments_total` to the real count. Otherwise keep all.

## Related issues

GitHub doesn't expose typed relations (blocks / blocked_by / parent / child) via the public API in a way `gh` surfaces cleanly. We leave `related: []` for GitHub by default. If the user asks, parse the issue body and comments for `#N` mentions in a follow-up pass.

## Known gotchas

- Cross-repo PR references via `gh pr list --search` only return PRs in the same repo. Cross-repo links must be parsed from issue body.
- `gh issue view --comments` returns nothing for issues with `discussions` reactions only.
- `gh auth status` doesn't fail loudly if the token is scoped without `repo` access on private repos — the next `gh issue view` call returns the real error.
