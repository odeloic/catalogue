# GitLab

Commands `fetch-issue.sh` runs against the `glab` CLI, plus self-hosted notes.

## Auth

`glab auth status` is checked before any fetch. If it fails:

```
GitLab auth missing. Run: glab auth login
```

For self-hosted instances:

```
glab auth login --hostname gitlab.your-company.com
```

Then `glab` uses the right token based on the remote URL.

## Commands

| Purpose | Command |
| --- | --- |
| Issue body + metadata | `glab issue view <id> [-R group/proj] -F json` |
| Prior MRs | `glab mr list [-R group/proj] --search "<id>" -F json` |

`glab` doesn't have a dedicated comments-only flag that matches `gh`'s shape. The `glab issue view -F json` response sometimes includes `discussions` or `notes`; if not, comments stay empty for now and we record the count from whichever field is present.

## JSON → normalized shape

| Output field | Source |
| --- | --- |
| `source` | `"gitlab"` |
| `id` | `issue.iid` (project-scoped) as string, or `issue.id` if `iid` is absent |
| `url` | `issue.web_url` |
| `title` | `issue.title` |
| `author` | `issue.author.username` |
| `assignee` | `issue.assignee.username` or first of `issue.assignees[].username`, or null |
| `status` | `issue.state` (`opened` / `closed`) |
| `labels` | `issue.labels` |
| `issue_type` | `issue.issue_type` (GitLab has this natively: `issue` / `incident` / `task`) |
| `description` | `issue.description` |
| `prior_attempts[]` | one per MR: `{type: "mr", url: mr.web_url, title, state, author}` |

## Self-hosted notes

- The script doesn't take a `--host` flag — it relies on `glab` being configured for the right host via `glab auth login`.
- `glab` infers the host from the cwd repo's `origin`. When passing `-R group/proj` without being inside the repo, set `GITLAB_HOST=gitlab.your-company.com` in the environment so `glab` resolves correctly.

## Known gotchas

- GitLab's `state` is `opened` (not `open`) — the normalized shape keeps the GitLab spelling for now to avoid lossy renames; downstream skills should accept both.
- `iid` vs `id`: `iid` is the project-scoped number you see in URLs; `id` is global. Always prefer `iid` for the normalized `id` field.
- `glab mr list --search` matches on title + description; cross-tracker links (e.g. Linear ID embedded in an MR description) work the same way as GitHub.
