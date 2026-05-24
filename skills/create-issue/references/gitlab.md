# GitLab

How to create an issue with the `glab` CLI.

## Auth

`glab auth status` is checked before any filing call. If it fails:

```
GitLab auth missing. Run: glab auth login
```

For self-hosted GitLab: `glab auth login --hostname <host>`.

## Create an issue

```
glab issue create \
  --title "<title>" \
  --description "<body>" \
  --label "<label1>,<label2>" \
  --assignee "<username>" \
  --milestone "<milestone>" \
  [-R group/project]
```

Flags worth knowing:

| Flag | Purpose |
| --- | --- |
| `--title` | Issue title (required). |
| `--description` | Inline body. `glab` does not have `--body-file`; pass via `"$(cat draft.md)"` or stdin. |
| `--label` | Comma-separated label names. |
| `--assignee` | Comma-separated usernames. |
| `--milestone` | Set milestone. |
| `--confidential` | Mark issue confidential. |
| `-R` | Target project (`group/project`). |

## Passing the body

`glab issue create` doesn't take `--body-file`. Use:

```
glab issue create --title "..." --description "$(cat .claude/drafts/issue-20260524-153012.md)" --label bug
```

## Quick actions

GitLab parses `/command` lines inside the description body. Embed them at the bottom of the description rather than as CLI flags when you want labels / assignees / milestones applied with the issue:

```
/label ~bug ~regression
/assign @username
/milestone %"Next"
/confidential
/due 2026-06-01
```

Quick actions are stripped from the rendered body and applied as actions on creation.

## After filing

`glab issue create` prints the issue URL on stdout — surface it to the user.

## Errors to handle

- `401 Unauthorized` — token expired or missing scope; surface `glab auth login`.
- `Label does not exist` — labels are project-scoped; create them or drop them.
- `404 Project Not Found` — wrong `-R` or insufficient permission.
