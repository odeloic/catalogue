# PR size heuristics

How `size_class` is computed and how review depth scales with it. The classification comes from `fetch-pr-context.sh` and lives at `size_metrics.size_class` in the context JSON.

## Thresholds

| Class | Lines added | Files changed |
| --- | --- | --- |
| `small` | <= 100 | <= 5 |
| `medium` | <= 300 | <= 10 |
| `large` | <= 500 | <= 20 |
| `xlarge` | anything beyond either threshold | |

A PR is bumped to the higher class if *either* dimension exceeds its threshold. A 50-line change across 12 files is `medium`, not `small`.

These are heuristics, not hard rules. The point is to calibrate the reviewer's depth, not to gatekeep PRs.

## Review depth by class

### `small`

Read every line. Every finding is fair game. Test coverage for the change should be expected.

Focus areas: the same as the seven quality dimensions, with full coverage.

### `medium`

Read every line, but prioritize hot paths. For a 250-line PR with 200 lines of test fixtures, the test fixtures get a skim; the 50 lines of real logic get full attention.

Focus areas: full coverage of the seven dimensions, with extra weight on tests (medium PRs often have a "core logic + tests + scaffolding" shape — flag if tests are missing for the logic).

### `large`

Declare coverage explicitly in the review. State which files were read in depth and which were skimmed. A 500-line PR can't get the same attention per line as a 50-line PR — pretending otherwise wastes the author's time.

Focus areas (read in depth):
- **Auth and authorization** — anything touching session, identity, permissions, role checks.
- **Payments and money** — anything moving currency, balances, invoices, billing.
- **Migrations** — schema changes, data backfills, anything that's hard to roll back.
- **Public APIs and contracts** — HTTP routes, gRPC services, library exports, webhooks emitted to consumers.
- **Data integrity** — transactions, idempotency keys, write paths with concurrency.
- **Security boundaries** — input validation, sanitization, sandboxing, file/path handling.

Skim (acknowledge in coverage note):
- Generated code, fixtures, snapshots.
- Pure config (renames, formatter changes).
- Test scaffolding that doesn't exercise the change.

### `xlarge`

Declare coverage explicitly *and* recommend splitting the PR if it's not already too late. Focus exclusively on the high-risk areas listed above. For everything else, flag broad concerns without line-by-line review.

Default recommendation bias: lean toward `comment` (asking the author for a split or a walkthrough) rather than `approve`, even if findings look clean — the chance of missing something at this size is high.

Focus areas: same as `large`, with an explicit note that you cannot meaningfully cover the rest.

## Coverage note shape

For `large` / `xlarge` PRs, append a `Coverage note` section to the review:

```
## Coverage note

Reviewed in depth:
- src/auth/session.ts (auth boundary)
- src/billing/invoice.ts (payment path)
- db/migrations/2026_05_24_add_orders.sql (schema change)

Skimmed:
- src/components/* (UI updates, mostly visual)
- tests/__snapshots__/* (regenerated snapshots)

Not reviewed:
- vendor/* (third-party, out of scope)
```

This makes coverage explicit so the author knows where to push back and where to ask for a second pair of eyes.

## Why size affects the recommendation

Large PRs that "look clean" should be a yellow flag, not a green light. Pattern: the bigger the diff, the more likely a subtle bug hides in code the reviewer skimmed. When in doubt on `large` / `xlarge`, pick `comment` with a request for a walkthrough or split, not `approve`.
