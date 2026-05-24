# Duplicate search

Before drafting, look for existing issues that already cover the same ground.

## Keyword extraction

From the user's one-line summary, pull 3-5 search keywords:

- Drop stop words (`the`, `a`, `is`, `to`, `for`, `on`, `in`, `of`, etc.).
- Drop generic tech filler (`bug`, `issue`, `error`, `crash`, `problem`) — the tracker label already covers those.
- Prefer nouns and proper nouns (component names, file paths, error codes, feature names).
- If the summary mentions an HTTP code, exception class, or function name, include it verbatim.

Example: "login page crashes when SSO token expires"
Keywords: `login`, `SSO`, `token`, `expires`.

## Search by tracker

### GitHub

```
gh issue list --search "<keyword> <keyword>" --state all --limit 10 [-R owner/repo]
```

For substring matches across title and body, `gh` uses GitHub's search syntax; quote multi-word phrases.

### GitLab

```
glab issue list --search "<keyword>" --all --per-page 10 [-R group/project]
```

`glab` searches title and description by default.

### Linear

Use the Linear MCP search tool (typically `mcp__linear__list_issues` or `mcp__linear__search_issues`, depending on the MCP build). Filter by team if known. Search both title and description.

## What to surface

- Top 3 matches, each with: id, title, status, URL.
- Order by relevance if the tracker returns a score, else recency.
- Pause before drafting and ask the user one of:
  - "Proceed and create a new issue."
  - "Link this one to #N and close out."
  - "Update #N instead."

**Don't auto-decide.** Even a high-similarity match might be intentionally distinct (regression of a closed bug, follow-up to a shipped feature). Always let the user choose.

## When the search is empty or fails

- Empty result set: proceed to drafting; mention in the report that no duplicates were found.
- Auth / network error: surface verbatim, ask whether to skip the duplicate check and proceed anyway.
