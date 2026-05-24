# GitHub

How to create an issue with the `gh` CLI.

## Auth

`gh auth status` is checked before any filing call. If it fails:

```
GitHub auth missing. Run: gh auth login
```

For GitHub Enterprise hosts: `gh auth login --hostname <host>`.

## Create an issue

```
gh issue create \
  --title "<title>" \
  --body-file <path-to-draft-body> \
  --label "<label1>,<label2>" \
  --assignee "<handle>" \
  --project "<project-name>" \
  [-R owner/repo]
```

Flags worth knowing:

| Flag | Purpose |
| --- | --- |
| `--title` | Issue title (required). |
| `--body` | Inline body string. Prefer `--body-file` for anything multi-line. |
| `--body-file` | Read body from a file. Use this with the saved draft. |
| `--label` | Comma-separated label names. Labels must already exist. |
| `--assignee` | Comma-separated GitHub handles, or `@me`. |
| `--project` | Add to a project (by title). |
| `--milestone` | Set milestone. |
| `-R` | Target repo (`owner/repo`). Omit to use the cwd repo. |

## Passing the body

Prefer `--body-file` pointing at the saved draft (`.claude/drafts/issue-<ts>.md`):

```
gh issue create --title "..." --body-file .claude/drafts/issue-20260524-153012.md --label bug
```

For ad-hoc bodies, a heredoc piped to a temp file is cleaner than `--body "$(...)"` since `gh` doesn't strip surrounding quotes well.

## After filing

`gh issue create` prints the new issue URL on stdout — surface it verbatim to the user.

## Errors to handle

- `HTTP 403` — token missing `repo` scope; surface and stop.
- `Label not found` — labels must exist on the repo; either drop the label or create it first (`gh label create`).
- `Could not resolve to a Repository` — wrong `-R` or no remote; ask for the target repo.
