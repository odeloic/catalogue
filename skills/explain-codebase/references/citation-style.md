# Citation style

How to reference code in the markdown explanation.

## Format

Always `path/to/file.ext:LINE` — repo-relative, with the line number after a colon. For a range, use a hyphen: `path/to/file.ext:42-58`.

Examples:
- `src/services/auth/session.ts:42`
- `app/api/routes/login.py:120-145`
- `lib/middleware/csrf.go:33`

Never:
- Absolute paths.
- File-only citations without a line number (lazy and unverifiable).
- Line numbers that don't correspond to the current state of the file. If you cite a line, you should have read it.

## When to quote, when to summarize

**Quote** (use a fenced code block) when:
- The exact wording matters — a regex, a constant, a config value.
- The reader needs to recognize the snippet to find it.
- The snippet is short (≤ 10 lines).

**Summarize** (prose + a citation) when:
- The logic is more than ~10 lines.
- The point is the shape of the function, not the specifics.
- A quote would obscure rather than clarify.

When you quote, always pair the block with the `file:line` citation immediately above or below it.

## Line ranges

Use a range (`file.ts:42-58`) when:
- The thing you're describing spans several lines (a function body, a switch).
- You want the reader to look at the surrounding context, not just one line.

Don't use a range when a single line suffices.

## The "Key files" section

Every markdown explanation ends with a section like:

```
## Key files

- `src/services/auth/session.ts:1-200` — session creation, refresh, expiry.
- `src/api/middleware/auth.ts:15-90` — request-level auth gate.
- `src/lib/cookies.ts:30-75` — cookie serialization helpers.
```

Three to five entries. Each entry: a file path with a line range, a one-line description. This section is the "where to look next" map for the reader. Put the file the user is most likely to open first at the top.

## Lookup answers

For lookup questions, the citation is the answer. Output structure:

```
The session is created in `src/services/auth/session.ts:42` by `createSession(userId)`.
```

That's it. No "Key files" section is needed for a lookup unless there's genuinely more than one file involved.

## Flow / trace answers

Each numbered step has a citation:

```
1. Request hits the auth middleware (`src/api/middleware/auth.ts:15`) which extracts the session cookie.
2. The middleware calls `validateSession()` (`src/services/auth/session.ts:120-145`) which checks signature and expiry.
3. If valid, the user object is attached to `req.user` (`src/api/middleware/auth.ts:67`).
```

One citation per step. If a step has multiple sub-references, pick the primary one and add the rest to **Key files**.
