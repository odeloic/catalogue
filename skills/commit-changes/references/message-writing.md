# Writing commit messages

The subject line is the contract. Body and trailers are optional context. Match the repo's convention exactly — never invent prefixes or scopes the history doesn't already use.

## Subject

- **Max 100 characters.** Hard cap. Shorter is better; 72 is the traditional sweet spot.
- **Match the detected convention exactly.** If `extract-commit-style.sh` reports `prefix_style: conventional` and `scope_used: true`, write `feat(scope): ...`. If it reports `prefix_style: none`, do not add a prefix.
- **Match the case.** If recent commits are lowercase, write lowercase. If sentence-case, capitalise the first word after the prefix.
- **Imperative mood.** "Add idempotency key", not "Added" or "Adds". Reads as an instruction the commit performs.
- **No trailing period.**
- **Be specific.** "fix bug" is useless. "fix: null deref in /v1/users when X-Trace-Id missing" tells you what happened.

## Body

Include a body **only** when one of these is true:
- The motivation isn't obvious from the diff.
- There's a breaking implication.
- There's context a future reader (or `git blame`) will want.
- You're referencing an issue or prior commit.

When you do write one:
- Blank line between subject and body.
- Wrap at 72 characters.
- Describe the **why**, not the **what**. The diff is the what.

If the motivation is "user asked for X and the implementation is straightforward" — skip the body.

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

**Conventional, no body:**
```
fix(auth): handle expired refresh token race
```

**Conventional, with body and trailer:**
```
feat(api): add idempotency key support

Requests now accept an `Idempotency-Key` header. The key is stored
for 24 hours; duplicate requests return the cached response.

Refs: ENG-412
```

**Ticket-prefix repo:**
```
[ENG-123] handle expired refresh token race
```

**No-prefix repo:**
```
Handle expired refresh token race
```

**Breaking change:**
```
feat(api)!: drop deprecated /v1/users endpoint

BREAKING CHANGE: clients must migrate to /v2/users before 3.0.0.
```
