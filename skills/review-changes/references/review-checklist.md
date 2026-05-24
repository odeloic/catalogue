# Review checklist

The seven quality dimensions the code-quality pass walks over the diff. Each dimension has concrete smells to look for — these are *examples*, not a checklist to mechanically apply. Read the diff with intent, then ask whether any of these patterns are present.

## 1. Correctness

Does the code do what it claims? Are the obvious defects present?

Example smells:
- **Off-by-one** — `for (i = 0; i <= arr.length; i++)`, `slice(0, n)` when `n` is `arr.length - 1`.
- **Null / undefined paths** — accessing `.foo.bar` after `findOne` without checking the find result.
- **Race conditions** — read-then-write without a lock, optimistic check before async-await, concurrent map writes.
- **Wrong operator** — `==` vs `===` in JS, `=` vs `==` in C-like languages.
- **Swapped arguments** — `transferFunds(from, to, amount)` called as `(to, from, amount)`.
- **Logic inversions** — `if (!authorized)` where `if (authorized)` was intended.
- **Truthy/falsy traps** — `if (count)` when `0` is a valid value.
- **Boundary conditions** — empty array, single element, max int, negative input, unicode in a byte-counted string.

## 2. Error handling

Are errors caught, surfaced, and recovered from sensibly?

Example smells:
- **Swallowed errors** — `catch (e) {}` or `catch (e) { console.log(e) }` with no rethrow / metric / user-visible signal.
- **Unhandled rejections** — async function called without `await` or `.catch`.
- **Over-broad catches** — `catch (Exception)` that hides bugs (`NullPointerException`, `TypeError`) along with the network failure you meant to handle.
- **Missing edge cases** — what happens when the API returns 500? When the input is empty? When the DB connection drops mid-transaction?
- **Inconsistent error shape** — half the endpoints return `{ error: "msg" }`, half throw, half return null.
- **No retry / backoff on transient failures** — network calls, queue publishes.

## 3. Security

Could this introduce a vulnerability?

Example smells:
- **Input validation missing** — user-supplied string interpolated into SQL, shell, or a path.
- **Auth checks bypassed** — endpoint added without the auth middleware; privilege check after the side effect.
- **IDOR** — accepting an ID without verifying the caller owns / can access the resource.
- **Secret handling** — secrets in source, secrets logged, secrets returned in API responses, secrets in error messages.
- **Injection vectors** — SQL, command, template, NoSQL, LDAP, XPath, regex (ReDoS).
- **Insecure crypto** — MD5/SHA1 for auth, ECB mode, hand-rolled crypto, non-constant-time comparison on tokens.
- **CORS / CSRF** — wildcard `Access-Control-Allow-Origin` on credentialed endpoints, state-changing GETs.
- **Deserialization of untrusted input** — `pickle.loads`, `Marshal.load`, `ObjectInputStream`.
- **Open redirect** — accepting a URL parameter for redirect without origin allowlist.

## 4. Performance

Will this scale, or is there a footgun on the hot path?

Example smells:
- **N+1 queries** — loop over rows then fire one query per row.
- **Unbounded loops / collections** — pagination missing, no limit on user-supplied size.
- **Sync work on a hot path** — file I/O, network calls, crypto inside a request handler that's hit on every request.
- **Repeated work** — recomputing the same expensive value inside a loop instead of hoisting.
- **Hidden quadratic** — `array.includes` inside a loop over the same array.
- **Unbatched writes** — one insert per row in a tight loop instead of bulk insert.
- **Eager loading too much** — `SELECT *` then discarding most columns; loading the world to render a list.
- **Memory leaks** — listeners added without removal, growing maps with no eviction.

## 5. Tests

Does the change come with tests that pin the new behavior?

Example smells:
- **No tests for new behavior** — new branch / function / endpoint with no corresponding test.
- **Brittle assertions** — `expect(output).toEqual(exactSnapshot)` for output that varies legitimately (timestamps, ordering, random IDs).
- **Tests pass without the change** — the test would still pass even if the production code change is reverted. Reviewer should imagine reverting and ask "would this test fail?"
- **Only happy-path tests** — no test for the failure case, the empty case, the boundary.
- **Test name doesn't match assertion** — `it('throws on empty input')` that asserts the function returns `[]`.
- **Mocks that lie** — mocking the thing under test instead of its collaborators; over-mocked tests that no longer exercise real logic.
- **Flaky-looking tests** — `setTimeout` for sync waits, ordering-dependent test setup.

## 6. Style consistency

Does the change match this codebase's conventions, not the reviewer's preferences?

Example smells:
- **Naming drift** — using `camelCase` where the file uses `snake_case`, or vice versa.
- **Pattern drift** — new module uses classes when the rest of the codebase is functional, or vice versa.
- **Imports / file organization** — putting helpers in a different place than the codebase's convention.
- **Logging shape** — `console.log` in a codebase that uses a structured logger.
- **Comment style** — adding obvious `// loops over items` comments in a codebase that doesn't comment that way.
- **Error type drift** — throwing strings in a codebase that uses typed Error subclasses.

The agent should *not* push its own preferences onto a codebase. If it would be a style change throughout the project, it's a separate refactor, not a review finding.

## 7. Scope creep

Is the diff doing only what the issue asked?

Example smells:
- **Unrelated refactors** — formatting changes, file moves, dependency upgrades bundled in.
- **Drive-by fixes** — unrelated bug fixes folded into a feature PR.
- **Dead code added** — helpers that aren't used yet "for later".
- **Configuration tweaks** — unrelated config or build changes.

Out-of-scope changes are not always wrong, but they make the PR harder to review and revert. Flag them and ask whether to split.
