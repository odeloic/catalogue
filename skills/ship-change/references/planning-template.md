# Planning template

The structure of a good plan written to `.claude/plans/<issue-id>.md`. The plan is the artifact the user reviews at the gate, so it has to be skimmable, concrete, and free of code-not-yet-written.

## Required sections

1. **Title and ID** — issue ID, one-line summary.
2. **Context** — one paragraph drawn from the triage report. What the issue is, why it matters, who asked.
3. **Success criteria** — bulleted list. Each criterion is verifiable. Pulled from acceptance criteria where present; otherwise written from the description and flagged for confirmation.
4. **Affected areas** — short summary of what `analyze-affected-areas.sh` returned. Name the top 3–5 directories and what lives there.
5. **Migration / backward-compat** — **only if** `detect-migration-needs.sh` flagged anything. Otherwise omit the section entirely. See `migration-considerations.md`.
6. **Steps** — ordered list. Each step has four fields: Goal, Expected outcome, Verification, Touch surface. See verification-strategies.md for verification patterns.
7. **Risks and open questions** — anything the agent is unsure about, anything that depends on user input, anything that could derail the plan.

## What each step looks like

Each step is small enough to verify standalone, large enough to be a meaningful unit of work. If a step has no standalone verification, merge it with the next step.

```
### Step N — short imperative title

- Goal: One sentence describing what this step does.
- Expected outcome: What's different after this step. Concrete, observable.
- Verification: How the agent confirms the step is done. Name the command or check.
- Touch surface: Files / directories expected to change.
```

## Example plan

```markdown
# ENG-142 — Add per-user rate limiting to the API

## Context

Two enterprise customers hit our shared rate limit during peak loads last week, taking down the public dashboard. The team agreed to introduce per-user token buckets keyed on API key. Triage classified as `feature`, label `api`, AC present.

## Success criteria

- [ ] Each API key has its own rate-limit bucket, configurable per plan tier.
- [ ] Existing global rate limit remains as a backstop.
- [ ] Limit headers (`X-RateLimit-Remaining`, `X-RateLimit-Reset`) are returned on every response.
- [ ] Integration test covers: a single key hitting its limit does not affect other keys.
- [ ] No change to behavior for unauthenticated traffic.

## Affected areas

`analyze-affected-areas.sh` keywords: `rate`, `limit`, `apiKey`, `middleware`.

- `src/api/middleware` — existing rate-limit middleware lives here.
- `src/services/auth` — API key resolution.
- `src/config` — limit values per plan tier.
- `tests/integration/api` — existing rate-limit tests to extend.

## Migration / backward-compat

`detect-migration-needs.sh` flagged `prisma/schema.prisma`. New `RateLimitBucket` table required.

- Add table behind a feature flag; backfill from existing global counters on first request.
- Roll out gradually — read from new table only when flag is on, dual-write during rollout.
- See `migration-considerations.md` § Schema additions.

## Steps

### Step 1 — Add `RateLimitBucket` table and migration

- Goal: Schema in place for per-key buckets.
- Expected outcome: `prisma migrate dev` runs clean, new table exists, no data lost.
- Verification: `pnpm prisma migrate dev --name add_rate_limit_buckets` succeeds, `pnpm prisma studio` shows the empty table.
- Touch surface: `prisma/schema.prisma`, `prisma/migrations/<new>/`.

### Step 2 — Add `RateLimiter` service with dual-write behind feature flag

- Goal: Service that can read/write per-key buckets, gated by `PER_USER_RATE_LIMITS` flag.
- Expected outcome: When the flag is off, behavior is unchanged. When on, each request increments per-key bucket.
- Verification: New unit tests for `RateLimiter` pass; existing integration tests pass with the flag off.
- Touch surface: `src/services/rate-limiter/`, `src/config/feature-flags.ts`.

### Step 3 — Wire `RateLimiter` into API middleware

- Goal: Middleware consults the new service when the flag is on.
- Expected outcome: Headers reflect per-key remaining; global limit still applies.
- Verification: New integration test in `tests/integration/api/rate-limit.spec.ts` covers per-key isolation.
- Touch surface: `src/api/middleware/rate-limit.ts`, `tests/integration/api/rate-limit.spec.ts`.

### Step 4 — Configure per-tier limits

- Goal: Config keyed on plan tier surfaces correct limits.
- Expected outcome: Free tier = 60/min, Pro = 600/min, Enterprise = 6000/min. Values come from config, not hardcoded.
- Verification: Config snapshot test passes; manual curl with different keys hits expected ceilings.
- Touch surface: `src/config/rate-limits.ts`, snapshot test.

## Risks and open questions

- Backfill strategy for existing high-traffic keys — do we seed buckets at zero, or at the last-known global usage? Default: zero. Confirm at gate.
- Redis vs. database for bucket storage — current global limiter uses Redis. Plan assumes same. Confirm the team is fine adding bucket keys to Redis.
- Should rate-limit headers be sent on 429 responses too? Current middleware suppresses them. Open question for the AC author.
```

## Writing-quality checks

Before surfacing the plan at the gate, the agent should:

- Re-read each success criterion and ask: can I tell this is met by running a specific command or check?
- Re-read each step's Verification: is it concrete? "Run tests" is not enough — name the test.
- Confirm there are no Phase 2 actions hidden in Phase 1 sections.
- Confirm the Migration section exists if and only if `detect-migration-needs.sh` flagged something.
