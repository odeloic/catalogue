# Reproduction strategies

How to get a deterministic repro before touching code. The strategy depends on the bug type.

## UI bugs

- Try to reproduce on the lowest-fidelity surface that still shows the bug: a Storybook story or a focused component test before the full app.
- Pin the route, props, and feature flags. Half of "intermittent" UI bugs are flag-state bugs.
- For visual bugs, capture before/after screenshots at the same viewport size. For interaction bugs, write down the exact event sequence (click x, then y, observe z).
- If the bug only shows up in production builds (minification, tree-shaking, CSS purging), reproduce against a prod build locally before fixing.

## API / backend bugs

- Reproduce with `curl` or an HTTP client first, not through the UI. Removes a layer of variables.
- Capture the full request: method, URL, headers, body, auth context. Capture the full response: status, headers, body.
- For state-dependent bugs (request N succeeds, N+1 fails) you need a fixture or seed script — record the steps to get to the failing state.
- For database-backed bugs, narrow to a minimal query that shows the wrong result before fixing the code that runs it.

## Race conditions / concurrency

- Add deterministic ordering before debugging: a sleep, a forced delay, a single-threaded mode. Confirm the bug is timing-dependent.
- If you can't reproduce reliably, write a stress loop (`for i in 1..1000`) that runs the operation in parallel. A race that fires 1% of the time will surface in seconds.
- Capture the failure with a stack trace from every involved thread/process. Logging the timing of each step in nanoseconds often makes the order of operations obvious.

## Data / migration bugs

- Find the smallest input that triggers the bug. A failing record id, a malformed row, an edge unicode character.
- Snapshot the input before the operation runs. If the operation is destructive, copy the row/file to a fixture before reproducing.
- For schema-shaped bugs, reproduce against an empty DB plus the minimum seed needed to fail. Don't debug against a 100GB production dump.

## "Works on my machine"

- Pin every variable that differs: OS, runtime version, package versions, env vars, locale, timezone, file system case sensitivity.
- A Dockerfile or `mise.toml` / `.nvmrc` / `.tool-versions` snapshot is the fastest way to get a shared environment.
- Once reproduced in a clean environment, narrow which variable matters by flipping them one at a time.

## When you cannot reproduce

Stop. Do not "fix" what you can't reproduce. Document the hypotheses you tried and what would let you make progress (a sample input, a log file, a staging environment, a flag setting). Escalate to the user.
