# Source detection

How `fetch-issue.sh` decides which tracker an input belongs to and what ID to extract.

## Order of checks (first match wins)

1. URL contains `linear.app` → **Linear**.
2. URL contains `github.com` (or a configured GH Enterprise host) → **GitHub**.
3. URL contains `gitlab.com` or `/-/issues/` (self-hosted GitLab pattern) → **GitLab**.
4. Input contains `[A-Za-z]+-[0-9]+` anywhere (Linear team-prefix convention) → **Linear**. Matches:
   - bare `ENG-123`
   - branch input `user/eng-123-do-thing`
   - branch input `eng-123/fix`
5. Input matches `^#?[0-9]+$` → inspect `git remote get-url origin`:
   - remote contains `github` → GitHub
   - remote contains `gitlab` → GitLab
6. None of the above → exit `3` with a clear message.

## ID extraction

- **Linear**: first `[A-Za-z]+-[0-9]+` match, uppercased.
- **GitHub / GitLab**: the digits after `/issues/` in the URL, or the bare number.

## Repo extraction (URLs only)

For GitHub/GitLab URLs we also pull `owner/repo` so we can pass `-R owner/repo` to `gh` / `glab` and not depend on the cwd being inside the target repo.

- GitHub URL `https://github.com/odeloic/jonas/issues/26` → `odeloic/jonas`
- GitLab URL `https://gitlab.com/group/project/-/issues/42` → `group/project`

## Branch inference (no-input mode)

When called with no arguments, read `git rev-parse --abbrev-ref HEAD`:
1. Try `[A-Za-z]+-[0-9]+` first (Linear).
2. Fall back to the first `[0-9]+` (GitHub/GitLab — resolved by `origin`).

## Edge cases

- `gh`/`glab` is missing → exit `1` with `missing required command: <tool>`.
- Not in a git repo and input needs `origin` lookup → exit `3` ("could not determine source").
- URL with extra path segments (`.../issues/42/comments`) → still matches `/issues/([0-9]+)`.
- URL ending in `.git` for repo extraction → the `.git` suffix is stripped.
- Capitalization in the Linear team prefix → always normalized to uppercase.

## Examples

| Input | Source | ID | Repo |
| --- | --- | --- | --- |
| `https://github.com/odeloic/jonas/issues/26` | github | 26 | odeloic/jonas |
| `https://linear.app/team/issue/ENG-123/slug` | linear | ENG-123 | — |
| `https://gitlab.com/group/proj/-/issues/42` | gitlab | 42 | group/proj |
| `ENG-123` | linear | ENG-123 | — |
| `#42` (origin=github) | github | 42 | — (uses cwd repo) |
| `42` (origin=gitlab) | gitlab | 42 | — |
| `user/ode-18-feature` | linear | ODE-18 | — |
| (no input, branch=`eng-123-fix`) | linear | ENG-123 | — |
