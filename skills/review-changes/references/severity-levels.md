# Severity levels

Each finding gets one of four severity levels. The choice drives the final recommendation, so picking the right level matters more than the wording of the finding itself.

## Blocker

**Definition**: must be addressed before merge. Merging as-is risks correctness, security, or losing user trust.

Examples:
- A correctness bug that produces wrong results for valid input.
- A security vulnerability — auth bypass, SQL injection, secret exposure, missing IDOR check.
- A data-loss path — destructive migration without backup, dropped writes under concurrency.
- A missing acceptance criterion on a non-draft PR — the PR doesn't satisfy what was asked.
- Breaks an existing public API or contract relied on by callers.
- Tests fail or are missing for a code path that's clearly the intent of the change.
- Adds a dependency on an unmerged PR without flagging it.

## Major

**Definition**: should be addressed but not strictly blocking. The PR can ship without it, but it's a clear smell that will bite later.

Examples:
- An N+1 query on a path that's not yet hot but will be.
- Missing tests for a non-critical new path.
- Error handling that swallows failures silently rather than logging or surfacing them.
- Significant inconsistency with the rest of the codebase (a new pattern when the existing one would do).
- A finding that *might* be a correctness bug — the reviewer isn't certain, and it deserves the author's attention.
- Scope creep that bundles unrelated work — recommend splitting, but not blocking.

## Minor

**Definition**: worth addressing, but deferring is acceptable.

Examples:
- Refactoring opportunity — the diff works, but there's a cleaner factoring.
- A mild duplication that could be DRY'd up but isn't load-bearing.
- A comment that could be clearer.
- A test that could be more thorough but covers the main case.
- An import order that's slightly off.

## Nit

**Definition**: purely stylistic — take it or leave it. Use sparingly.

Examples:
- Variable naming preferences (`i` vs `index`).
- Whitespace, blank lines, trailing commas.
- Wording in a string or log message.
- A spelling typo in a non-public string.

Nits should never accumulate to the point where they drown out real findings. If a PR has more than ~3 nits, fold them into a single "minor style notes" entry.

## Choosing the recommendation

After categorizing every finding, pick the recommendation:

| Condition | Recommendation |
| --- | --- |
| Any Blocker, or any unmet AC marked `Missing` on a non-draft PR | `request_changes` |
| No Blockers, but unresolved Majors or AC marked `Partial` / ambiguous | `comment` |
| No Blockers / Majors; all AC `Met` or `Not verifiable from diff` (with note) | `approve` |
| Draft PR | always `comment` (review is preliminary regardless of findings) |
| CI failing | always `comment` with a note: "fix CI first, then re-request review" |
| Self-review | downgrade `approve` to `comment` and suggest a second reviewer |

The recommendation is one line. Reasoning is one sentence. Findings carry the detail; the recommendation summarizes.

## Anti-patterns when choosing severity

- **Severity inflation** — calling style preferences "Major" because they bother you. If reverting the finding wouldn't change behavior, it's probably Minor or Nit.
- **Severity deflation** — soft-pedaling a correctness bug as "Minor" because the author is senior. Severity tracks impact, not relationship.
- **Findings without severity** — every finding gets exactly one severity. "I'm not sure if this is a Blocker or a Major" is itself useful information — ask the author and mark it Major with a note.
