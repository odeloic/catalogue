# Spec: `ship-change` skill

## Purpose
Deliver a feature, improvement, or change request using a plan-then-implement discipline with an explicit review gate between the two phases. The skill takes a triage report, produces a reviewable plan, waits for user approval, then executes the plan step by step with per-step verification before handing off to `commit-changes`.

## Skill frontmatter description (the trigger contract)
> Plan and implement a feature, improvement, or change request given a triage report or issue ID. Use when triage classification is "feature", "improvement", or "change", or the user says "implement X", "ship Y", or "build the thing in ENG-123". Produces a reviewable plan, waits for approval, then executes step-by-step with verification. Depends on `triage-issue` for context, hands off to `commit-changes` per logical commit cluster.

## Inputs
1. A triage report path — `.claude/triage/<issue-id>.json`.
2. An issue ID or URL — invokes `triage-issue` first.
3. A free-form change spec — skips triage; user takes responsibility for context.

## Workflow

### Phase 1 — PLAN

**1. Acquire context**
Load triage report. If acceptance criteria are present, they anchor the plan's success criteria. If absent, the agent defines success criteria from the issue description and confirms them with the user.

**2. Analyze affected code areas**
Call `analyze-affected-areas.sh` with keywords extracted from the triage report. The script returns files grouped by directory with hit counts; the agent uses this to ground the plan in real code rather than guesses.

**3. Detect migration / backward-compat needs**
Call `detect-migration-needs.sh`. If schema migrations, public API surfaces, or contract files are touched, the plan must include an explicit migration strategy section and a backward-compat assessment.

**4. Define success criteria**
A short list of conditions that, when all met, mean the change is done. Pulled from the issue's AC where present; otherwise written from the description and made explicit. Success criteria must be verifiable — each one needs a clear way to check it.

**5. Break into verifiable steps**
Each step has:
- A goal (one sentence)
- Expected outcome (what's different after this step)
- Verification method (how the agent confirms the step is done — run test, hit endpoint, lint, type check, visual)
- Estimated touch surface (files / areas)

Steps are ordered so each can be verified independently before the next begins. If a step can't be verified standalone, it gets merged with the next.

**6. Write plan**
Save to `.claude/plans/<issue-id>.md`. Structure:
- Context (1 paragraph, drawn from triage)
- Success criteria (list)
- Affected areas (summary from the script)
- Migration / backward-compat (section only if `detect-migration-needs.sh` flagged anything)
- Steps (ordered, with the four fields above)
- Risks and open questions

**7. Gate — present plan to user**
Halt and surface the plan. Wait for explicit approval before Phase 2. Acceptable outcomes:
- Approved → proceed to Phase 2.
- Revisions requested → revise the plan once, re-surface, wait again.
- Rejected → halt entirely, ask for redirection.

### Phase 2 — IMPLEMENT (only after plan approval)

For each step in order:
1. Execute the step.
2. Run the verification method declared in the plan.
3. If verification passes → continue to next step.
4. If verification fails → halt, surface the failure, present options (retry, skip with caveat, escalate, revise plan).

After all steps complete:
5. Run a final acceptance check against the success criteria. Each criterion must be demonstrably met.
6. Hand off to `commit-changes`. For large changes, hand off per logical cluster of steps rather than as one giant commit.

## Script: `scripts/analyze-affected-areas.sh <keywords...>`
Takes a list of search terms (extracted by the agent from the triage report — symbol names, feature names, file hints). Runs ripgrep across the repo. Returns JSON to stdout.

```json
{
  "keywords": ["..."],
  "matches": [
    {
      "directory": "src/services/auth",
      "files": [
        { "path": "src/services/auth/session.ts", "hits": 14 },
        { "path": "src/services/auth/index.ts", "hits": 7 }
      ],
      "total_hits": 21
    }
  ],
  "top_directories": ["src/services/auth", "src/api/middleware"],
  "exclusions_applied": ["node_modules", "dist", ".git", "vendored"]
}
```

The script respects `.gitignore` and excludes common vendor/build directories. Returns top N directories sorted by total hits.

## Script: `scripts/detect-migration-needs.sh`
Single call. Returns JSON to stdout. Read-only.

Detection sources:
- Schema files: `prisma/schema.prisma`, `db/schema.rb`, SQLAlchemy models, `alembic/versions/`, `migrations/` directories, Knex, Sequelize, Drizzle, GORM struct tags.
- API contracts: `openapi.yaml`, `openapi.json`, `*.graphql`, `*.proto`, `swagger.yaml`.
- Public type surfaces: top-level `index.ts`, `lib.rs`, `__init__.py` exports, package `exports` field.
- Config schemas: `config/schema.*`, env var documentation.

Output:
```json
{
  "has_migration_system": true,
  "migration_paths": ["prisma/migrations", "db/migrate"],
  "schema_files": ["prisma/schema.prisma"],
  "api_contract_files": ["openapi.yaml"],
  "public_api_surfaces": ["src/index.ts", "packages/sdk/src/index.ts"],
  "warnings": [
    "Public API surface detected — changes here require deprecation strategy",
    "Production migration system detected — verify backward-compat of schema changes"
  ]
}
```

The agent uses this to decide whether the plan needs a migration section.

## Outputs
1. The plan markdown at `.claude/plans/<issue-id>.md` — the artifact reviewed at the gate.
2. Implementation commits per logical step cluster, via `commit-changes`.
3. An implementation summary at `.claude/changes/<issue-id>.md` after Phase 2 completes — records which steps ran, verification results, deviations from the plan.
4. Updated triage JSON:
```json
"change": {
  "plan_path": ".claude/plans/<issue-id>.md",
  "summary_path": ".claude/changes/<issue-id>.md",
  "status": "planned|in_progress|done|halted",
  "commits": ["sha1", "sha2"]
}
```

## Directory layout
```
skills/implementation/ship-change/
├── SKILL.md
├── scripts/
│   ├── analyze-affected-areas.sh
│   └── detect-migration-needs.sh
├── references/
│   ├── planning-template.md            # the markdown structure of a good plan
│   ├── migration-considerations.md     # patterns: schema, API, public types, configs
│   └── verification-strategies.md      # how to verify a step: test, endpoint, lint, type, visual
└── tests/
    └── fixtures/                        # sample triage JSONs + repo states across ecosystems
```

## Edge cases
- **Plan reveals work much larger than expected** — halt at the gate, ask whether to slice into smaller issues or proceed.
- **Migration affects production data** — require explicit confirmation in the gate, not just plan approval.
- **Step verification fails mid-implementation** — halt; do not silently continue. Present recovery options to the user.
- **Plan rejected by user** — revise once. If still rejected, halt and ask for redirection rather than guessing.
- **Mid-implementation discovery invalidates plan** — halt, surface the discovery, ask to revise the plan before continuing.
- **Public API change without deprecation strategy** — refuse to proceed past the gate until a deprecation strategy is in the plan.
- **No acceptance criteria, no clear success definition** — define success criteria in the plan and surface them prominently at the gate for confirmation.
- **Triage report missing or stale** — re-run `triage-issue` rather than working from outdated context.

## Testing approach
Fixture-based: sample triage JSONs spanning the three types (feature, improvement, change) and a few ecosystems. Assert that `analyze-affected-areas.sh` returns expected hit clusters against a known repo state, and `detect-migration-needs.sh` correctly flags schema-bearing fixtures. The plan generation itself is harder to test — keep it to snapshot tests of the markdown structure against a frozen triage input.
