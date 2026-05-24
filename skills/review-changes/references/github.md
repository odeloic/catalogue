# GitHub

Commands `fetch-pr-context.sh` runs against the `gh` CLI for PR review, plus auth and enterprise host notes. See `[[triage/github]]` for the issue-side commands; this file covers PRs only.

## Auth

`gh auth status` is checked before any fetch. If it fails:

```
GitHub auth missing. Run: gh auth login
```

For GitHub Enterprise hosts, `gh auth login --hostname <host>`. `gh` picks the right token based on the remote URL.

## Commands

All commands take `-R owner/repo` when the input is a URL. When the input is a bare PR number, `gh` falls back to the cwd repo.

| Purpose | Command |
| --- | --- |
| PR metadata | `gh pr view <n> [-R owner/repo] --json number,title,url,author,isDraft,state,baseRefName,baseRefOid,headRefName,headRefOid,files,additions,deletions,body` |
| Unified diff | `gh pr diff <n> [-R owner/repo]` |
| CI checks | `gh pr checks <n> [-R owner/repo] --json name,state,link` |
| Linked issues | `gh pr view <n> [-R owner/repo] --json closingIssuesReferences` |

## JSON -> normalized shape

| Output field | Source |
| --- | --- |
| `source` | `"github"` |
| `id` | PR number as string |
| `url` | `pr.url` |
| `title` | `pr.title` |
| `author` | `pr.author.login` |
| `is_draft` | `pr.isDraft` |
| `base.ref` / `base.sha` | `pr.baseRefName` / `pr.baseRefOid` |
| `head.ref` / `head.sha` | `pr.headRefName` / `pr.headRefOid` |
| `diff` | `gh pr diff` raw output |
| `files_changed[]` | `pr.files[]` mapped to `{path, added, removed, status}` |
| `linked_issues[]` | `closingIssuesReferences[]` mapped to `{id, source: "github", url}` |
| `ci.status` | derived: `failure` if any check failed, `pending` if any in-flight, `success` if all neutral/success/skipped, `none` if no checks |
| `ci.checks[]` | `{name, status (lowercased), url}` |
| `ci.failures[]` | names of checks where `state == "failure"` |
| `depends_on[]` | regex `[Dd]epends on|[Bb]locked by` against `pr.body` |

## Linked issues

`closingIssuesReferences` covers issues the PR will close (the `Closes #123` / `Fixes #123` convention). It does *not* cover loose references in the body. If you need those, parse the body for `#N` and ask the user to confirm before treating them as linked.

## CI status mapping

`gh pr checks` returns check runs and status checks together with a `state` field. The script maps:

| `gh` state | Normalized |
| --- | --- |
| `SUCCESS` / `NEUTRAL` / `SKIPPED` | `success` |
| `FAILURE` / `CANCELLED` / `TIMED_OUT` / `ACTION_REQUIRED` | `failure` (treated as failure for any) |
| `PENDING` / `IN_PROGRESS` / `QUEUED` | `pending` |

Mixed states are resolved by precedence: failure > pending > success > none.

## GitHub Enterprise host config

Set the remote to the enterprise host (e.g. `git@github.example.com:org/repo.git`). `gh` picks the right token automatically once you've run `gh auth login --hostname github.example.com`. No skill-side flag is needed.

## Known gotchas

- `gh pr diff` returns empty for PRs with no diff (closed-without-merge, or against a deleted base). Treat empty diff as a halt condition.
- `gh pr checks` returns `[]` for PRs older than 30 days where check runs have been GC'd. Treat as `none` rather than `success`.
- `closingIssuesReferences` is GraphQL-only — older `gh` versions (< 2.4) silently drop it. The script tolerates a missing field.
