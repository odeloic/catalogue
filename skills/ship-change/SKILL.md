---
name: ship-change
description: Plan-then-implement a feature, improvement, or change request with an explicit approval gate between plan and execution, then step-by-step verification, then handoff to `commit-changes`. Accepts a triage report, an issue ID/URL (will invoke `triage` first), or a free-form change spec.
when_to_use: When the user says "implement X", "build X", "ship X", "add X", "ship the thing in ENG-123", "let's build feature Y", "make X work like Z", "refactor X to do Y", "improve X", "let's tackle ABC-7", or when a prior `triage` report classifies the issue as `feature`, `improvement`, or `change`. SKIP for bug fixes — route to `fix-bug`. SKIP if classification is `unknown` with low confidence — confirm with the user first. SKIP for one-line tweaks the user clearly wants done immediately without a plan.
---

# ship-change

Deliver a feature, improvement, or change request using plan-then-implement discipline with an explicit review gate between the two phases. The skill produces a reviewable plan, **halts and waits for explicit user approval**, then executes the plan step by step with per-step verification before handing off to `commit-changes`.

## Inputs accepted

1. **Triage report path** — `.claude/triage/<issue-id>.json` (preferred, produced by `[[triage]]`).
2. **Issue ID or URL** — invoke `[[triage]]` first to produce the report, then proceed.
3. **Free-form change spec** — no triage report. The user takes responsibility for context completeness; the skill still produces a plan and gates on approval.

## When NOT to use this skill

- Triage classifies the issue as `bug` — route to `fix-bug` instead.
- Triage classification is `unknown` with `low` confidence — confirm classification with the user first.
- The issue is closed or marked duplicate — surface and stop.

## Workflow

### Phase 1 — PLAN

The goal of Phase 1 is a reviewable artifact at `.claude/plans/<issue-id>.md`. **Do not write code in Phase 1.**

1. **Acquire context.** Load the triage report. If acceptance criteria are present, they anchor success criteria. If absent, define success criteria from the issue description and surface them at the gate for confirmation.
2. **Analyze affected areas.** Extract keywords from the triage report — symbol names, feature names, file hints, domain terms. Call:
   ```
   scripts/analyze-affected-areas.sh <keyword1> <keyword2> ...
   ```
   The script returns JSON on stdout: directories grouped by hit count, top N (default 10) sorted descending. Use this to ground the plan in real code.
3. **Detect migration / backward-compat needs.** Call:
   ```
   scripts/detect-migration-needs.sh
   ```
   The script returns JSON describing schema files, migration directories, API contracts, public API surfaces, and warnings. If anything is flagged, the plan **must** include a Migration section.
4. **Define success criteria.** A short list of conditions that, when all met, mean the change is done. Each criterion must be verifiable — pair it with a clear way to check.
5. **Break into verifiable steps.** Each step has four fields:
   - **Goal** — one sentence.
   - **Expected outcome** — what's different after this step.
   - **Verification** — how the agent confirms the step is done: run test, hit endpoint, lint, type check, visual.
   - **Touch surface** — files / areas expected to change.

   Order steps so each can be verified independently before the next begins. If a step can't be verified standalone, merge it with the next one. See `references/verification-strategies.md` for verification patterns.
6. **Write the plan.** Save to `.claude/plans/<issue-id>.md`. Use the structure in `references/planning-template.md`:
   - Context
   - Success criteria
   - Affected areas (summary from `analyze-affected-areas.sh`)
   - Migration / backward-compat (only if `detect-migration-needs.sh` flagged anything — see `references/migration-considerations.md`)
   - Steps (ordered, four fields each)
   - Risks and open questions

7. **GATE — render the plan artifact and HALT.**

   This is the critical part. After writing the plan:

   - **Render a visual plan artifact** with `kind: "plan"`, `stage: "plan"` (see schema in "Render artifact" section below) and open it in the browser.
   - Surface a one-line chat summary with the recommendation to review the artifact and respond.
   - **Stop. Do not write code. Do not proceed to Phase 2 without an explicit affirmative signal.**
   - Acceptable next moves:
     - **Approved** ("looks good", "go ahead", "ship it", "approved") → proceed to Phase 2.
     - **Revisions requested** → revise the plan once, save updated version, re-surface, wait again.
     - **Rejected** → halt entirely, ask the user for redirection. Do not silently retry.
   - Ambiguous signals ("hmm", "maybe", a question about the plan) are **not** approval. Treat as a question and continue waiting.
   - If the plan reveals work much larger than the triage suggested, name it at the gate and ask whether to slice into smaller issues before approval.
   - If migration affects production data, require **explicit confirmation of the migration step** in addition to plan approval.
   - If a public API change has no deprecation strategy in the plan, refuse to proceed past the gate until one is added.

### Phase 2 — IMPLEMENT (only after explicit approval)

For each step, in order:

1. Execute the step.
2. Run the verification method declared in the plan for that step.
3. **If verification passes** → continue to the next step.
4. **If verification fails** → halt. Surface the failure with what was tried and what broke. Present options: retry, skip with caveat, escalate to user, revise plan. Do **not** silently continue.

If a mid-implementation discovery invalidates the plan (a step turns out to need work that wasn't planned), halt, surface the discovery, and ask to revise the plan before continuing.

After all steps complete:

5. **Final acceptance check.** Walk through each success criterion from the plan. Each must be demonstrably met — name how it was verified.
6. **Write the implementation summary** to `.claude/changes/<issue-id>.md` recording which steps ran, verification results, and any deviations from the plan.
7. **Render the execution artifact** with `kind: "plan"`, `stage: "execution"`, populating each step's `status`. Open it in the browser.
8. **Hand off to `[[commit-changes]]`.** For large changes, hand off per logical cluster of steps rather than one giant commit. Provide the cluster description and the files in scope.
9. **Update the triage JSON** at `.claude/triage/<issue-id>.json` with:
   ```json
   "change": {
     "plan_path": ".claude/plans/<issue-id>.md",
     "summary_path": ".claude/changes/<issue-id>.md",
     "status": "done",
     "commits": ["sha1", "sha2"]
   }
   ```
   The `status` transitions: `planned` after Phase 1 approval, `in_progress` during Phase 2, `done` on success, `halted` on bail-out.

## Render artifact

Pipe a JSON envelope to the shared renderer at both gate points (after writing the plan, and after Phase 2 completes):

```bash
python3 ${CLAUDE_SKILL_DIR}/../../.claude-plugin/scripts/render-artifact.py <<'ARTIFACT_EOF'
{
  "kind": "plan",
  "payload": {
    "title": "Short change title",
    "issue_ref": "ENG-200",
    "classification": "feature|improvement|change",
    "stage": "plan|execution",
    "summary": "Goal in one sentence.",
    "approach": "High-level approach in 1-3 sentences.",
    "steps": [
      {"title": "Step title", "status": "pending|in_progress|done|blocked|skipped",
       "files": ["src/x.ts"], "description": "What this step does.",
       "verification": "How to confirm it's done."}
    ],
    "verification": {
      "description": "Final acceptance check.",
      "steps": ["Check A", "Check B"],
      "command": "optional command"
    },
    "risks": ["Risk 1", "Risk 2"],
    "callouts": [{"type": "warning|tip", "text": "..."}]
  }
}
ARTIFACT_EOF
```

`stage: "plan"` produces the gate artifact (all steps `pending`). `stage: "execution"` produces the final report with per-step status filled in.

**Do not include emojis in any payload text** (titles, summaries, approach, step descriptions, verifications, risks, callouts). The renderer styles content with typography and color.

## Outputs

1. `.claude/plans/<issue-id>.md` — the reviewable plan (gate artifact).
2. Implementation commits per logical cluster, via `[[commit-changes]]`.
3. `.claude/changes/<issue-id>.md` — implementation summary after Phase 2 completes.
4. Updated triage JSON with the `change` block above.

## Edge cases

- **Triage report missing or stale** — re-run `[[triage]]` rather than working from outdated context.
- **No acceptance criteria, no clear success definition** — define success criteria in the plan and surface them prominently at the gate for confirmation.
- **Plan reveals work much larger than expected** — halt at the gate, ask whether to slice into smaller issues.
- **Migration affects production data** — require explicit confirmation of the migration step at the gate, not just plan approval.
- **Public API change without deprecation strategy** — refuse to proceed past the gate until a deprecation strategy is in the plan. See `references/migration-considerations.md`.
- **Step verification fails mid-implementation** — halt; do not silently continue. Present recovery options.
- **Mid-implementation discovery invalidates the plan** — halt, surface, revise the plan before continuing.
- **Plan rejected by user** — revise once. If still rejected, halt and ask for redirection.

## Scripts

| Script | Purpose | Side effects |
| --- | --- | --- |
| `scripts/analyze-affected-areas.sh <keywords...>` | Group repo hits by directory, return top N. | Read-only. |
| `scripts/detect-migration-needs.sh` | Detect schema / API contract / public surface files. | Read-only. |

Both scripts emit JSON to stdout. Use `jq` to consume.

## References

- `references/planning-template.md` — the markdown structure of a good plan, with a concrete example.
- `references/migration-considerations.md` — schema, API contract, public type, and config change patterns.
- `references/verification-strategies.md` — concrete per-step verification methods by language and surface.

## Testing

Run from the repo root:

```
bash skills/ship-change/tests/test-analyze-affected-areas.sh
bash skills/ship-change/tests/test-detect-migration-needs.sh
```

Detection tests use fixtures under `tests/fixtures/` representing repos with prisma, with openapi, and with no migration system.
