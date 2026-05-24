# GitLab

Commands `fetch-pr-context.sh` runs against the `glab` CLI for MR review, plus self-hosted notes. See `[[triage/gitlab]]` for the issue-side commands; this file covers MRs only.

## Auth

`glab auth status` is checked before any fetch. If it fails:

```
GitLab auth missing. Run: glab auth login
```

For self-hosted instances:

```
glab auth login --hostname gitlab.your-company.com
```

`glab` then uses the right token based on the remote URL.

## Commands

| Purpose | Command |
| --- | --- |
| MR metadata + changes | `glab mr view <n> [-R group/proj] -F json` |
| Unified diff | `glab mr diff <n> [-R group/proj]` |
| CI status | `glab ci status --mr <n> [-R group/proj] -F json` |

## JSON -> normalized shape

| Output field | Source |
| --- | --- |
| `source` | `"gitlab"` |
| `id` | MR `iid` as string |
| `url` | `mr.web_url` |
| `title` | `mr.title` |
| `author` | `mr.author.username` |
| `is_draft` | `mr.draft` (fallback `mr.work_in_progress` for older GitLabs) |
| `base.ref` / `base.sha` | `mr.target_branch` / `mr.diff_refs.base_sha` |
| `head.ref` / `head.sha` | `mr.source_branch` / `mr.diff_refs.head_sha` |
| `diff` | `glab mr diff` raw output |
| `files_changed[]` | `mr.changes[]` mapped to `{path, added: 0, removed: 0, status}` (per-file counts aren't in the changes payload; status is `added` / `deleted` / `renamed` / `modified`) |
| `linked_issues[]` | regex-parsed from `mr.description` matching `Closes/Fixes/Resolves/Relates to #N` |
| `ci.status` | derived: `failure` if any pipeline job failed, `pending` if any running/created, `success` if all success/manual/skipped, `none` if empty |
| `ci.checks[]` | `{name, status (lowercased), url: web_url}` |
| `ci.failures[]` | names of jobs where `status == "failed"` |
| `depends_on[]` | regex `[Dd]epends on|[Bb]locked by` against `mr.description` matching `!N` or full URL |

## Linked issues from MR description

GitLab doesn't expose a `closingIssuesReferences`-equivalent through `glab mr view -F json` reliably. The script parses the description for the standard close-keyword pattern documented in GitLab's [closing issues automatically](https://docs.gitlab.com/ee/user/project/issues/managing_issues.html#closing-issues-automatically) conventions:

```
Closes #123
Fixes #456, #789
Resolves #42
Relates to #99
```

Cross-project references (`group/project#123`) are not currently parsed — the resulting `id` is just the number.

## CI status mapping

| GitLab `status` | Normalized |
| --- | --- |
| `success` / `manual` / `skipped` | `success` |
| `failed` | `failure` |
| `pending` / `running` / `created` | `pending` |
| `canceled` | treated as `failure` for safety (cancellations often mask flakes) |

## Self-hosted notes

- The script doesn't take a `--host` flag — it relies on `glab` being configured for the right host via `glab auth login`.
- `glab` infers the host from the cwd repo's `origin`. When passing `-R group/proj` without being inside the repo, set `GITLAB_HOST=gitlab.your-company.com` in the environment.

## Known gotchas

- `glab mr view -F json` field names drift across `glab` versions: `draft` vs `work_in_progress`, `iid` vs `id`. The script reads `iid` then `id`, and `draft` then `work_in_progress`.
- `glab mr diff` can return empty if the MR has been rebased and the remote diff cache is stale. Re-fetch in that case.
- `glab ci status --mr` only returns the latest pipeline. Earlier failed pipelines aren't surfaced; the latest pipeline status is what governs `ci.status`.
