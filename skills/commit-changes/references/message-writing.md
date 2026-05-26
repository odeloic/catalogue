# Writing commit messages

**Be terse.** The subject line is the contract; body and trailers are exceptions, not defaults. Most commits should be a single line. Match the repo's convention exactly — never invent prefixes or scopes the history doesn't already use.

## Subject

- **Aim for ~50 chars, hard cap 72.** Shorter is better. If you need more, you probably need a different split.
- **Match the detected convention exactly.** If `extract-commit-style.sh` reports `prefix_style: conventional` and `scope_used: true`, write `feat(scope): ...`. If it reports `prefix_style: none`, do not add a prefix.
- **Match the case.** If recent commits are lowercase, write lowercase. If sentence-case, capitalise the first word after the prefix.
- **Imperative mood.** "add idempotency key", not "added" or "adds".
- **No trailing period.**
- **No filler.** Drop "this commit", "this change", "in order to", "as requested", "various improvements", "small refactor". They add length without information.
- **Be specific but compact.** "fix bug" is useless. "fix: null deref in /v1/users when X-Trace-Id missing" works. Don't pad it.

## Body

**Default: no body.** A subject line is enough for the vast majority of commits. Include a body **only** when one of these is true:
- The motivation isn't obvious from the diff.
- There's a breaking implication (then yes, write it).
- A future reader doing `git blame` would be stuck without it.

When you do write one:
- Blank line between subject and body.
- Wrap at 72 characters.
- **Describe the why, not the what.** The diff is the what.
- Two to three sentences. No bullet lists recapping files. No restating the subject.
- If you're tempted to write "this change adds X by modifying Y" — stop. Delete the body.

If the motivation is "user asked for X and the implementation is straightforward" — skip the body. Always.

## Trailers

`extract-commit-style.sh` reports which trailers the repo uses. Honour them:

- **`Signed-off-by: Name <email>`** — DCO. If recent history has it, every new commit needs it. `git commit -s` does this.
- **`Co-authored-by: Name <email>`** — when pairing or when the user provided substantial guidance.
- **Issue references.** Match the detected `issue_reference.pattern` and `location`:
  - If `location: trailer`, put refs as a trailer (`Refs: ENG-123`).
  - If `location: body`, in-prose at the end of the body.
  - If `location: subject`, in the subject (rare; usually a `[ENG-123]` prefix).

Trailers go at the very end, separated from the body by a blank line. Each on its own line, `Key: value` format.

## Worked examples

### Good — subject only (the default)

```
fix(auth): handle expired refresh token race
```

```
feat(api): add idempotency key support
```

```
chore(deps): bump typescript to 5.4
```

```
refactor(parser): extract token lookahead into helper
```

### Good — body justified (rare)

Body explains a non-obvious motivation:
```
feat(api): add idempotency key support

Stripe-style retries were creating duplicate charges when the
client's network blipped between request and response.

Refs: ENG-412
```

Breaking change — the body is required:
```
feat(api)!: drop deprecated /v1/users endpoint

BREAKING CHANGE: clients must migrate to /v2/users before 3.0.0.
```

### Other repo conventions (still subject-only)

Ticket-prefix repo:
```
[ENG-123] handle expired refresh token race
```

No-prefix repo:
```
Handle expired refresh token race
```

### Bad — what to avoid

Too long, recaps the diff, includes filler:
```
feat(api): add new idempotency key support to the API endpoints (refs ENG-412)

This commit adds support for idempotency keys to our API. It modifies
the request handler in src/api/handler.ts to check for the
Idempotency-Key header, adds a new cache module in src/api/cache.ts
to store responses for 24 hours, and updates the tests in
tests/api.test.ts to cover the new behavior. This change was requested
by the user in order to improve reliability.

- Added Idempotency-Key header check
- Added cache module
- Updated tests
```

Why it's bad: subject too long and noisy; body restates the diff (the *what*) instead of the *why*; bullet list recaps files; "this commit", "in order to", "as requested" are filler. The subject-only `feat(api): add idempotency key support` says everything the reader needs.
