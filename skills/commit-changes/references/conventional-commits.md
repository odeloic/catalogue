# Conventional Commits cheat sheet

Spec: https://www.conventionalcommits.org/en/v1.0.0/

## Shape

```
<type>(<scope>)<!>: <description>

<body>

<footer(s)>
```

## Types

| Type | Use for |
| --- | --- |
| `feat` | A new user-facing feature. |
| `fix` | A bug fix. |
| `chore` | Maintenance, deps, lockfile bumps, repo hygiene. |
| `docs` | Documentation only. |
| `style` | Formatting, whitespace, semicolons — no logic change. |
| `refactor` | Code change that isn't a feature or fix. |
| `perf` | Performance improvement. |
| `test` | Adding or fixing tests. |
| `build` | Build system / external deps (webpack, npm scripts, Docker). |
| `ci` | CI configuration changes. |
| `revert` | Reverts a previous commit. |

Some repos add custom types (e.g. `wip`, `release`). Match the history — don't invent.

## Scope

Optional. Parenthesised after the type: `feat(auth): ...`. Scope is a noun naming the area touched (`api`, `ui`, `db`, a package name, a module). Use it consistently if the repo uses it at all — `extract-commit-style.sh` reports the common scopes.

## Breaking changes

Two ways, either is accepted:

1. `!` after the type/scope: `feat(api)!: drop deprecated /v1/users endpoint`.
2. A `BREAKING CHANGE:` footer:
   ```
   feat(api): switch to OAuth 2.1

   BREAKING CHANGE: clients must migrate by v3.0.0.
   ```

Use both if the breaking nature is important — the `!` for scanning, the footer for detail.

## Footers

Standard footers used in the wild:

- `BREAKING CHANGE: <description>`
- `Refs: ENG-123`, `Refs #42`
- `Closes #42`, `Fixes #42`, `Resolves #42` (GitHub auto-closes the issue on merge)
- `Co-authored-by: Name <email>`
- `Signed-off-by: Name <email>` (DCO)
- `Reviewed-by: Name <email>`

## Subject rules

- Imperative mood: "add", not "added" or "adds".
- Lowercase by convention, but match the repo's case.
- No trailing period.
- Concise — under 72 chars is traditional; the user's cap here is 100.
