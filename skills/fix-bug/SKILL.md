---
name: fix-bug
description: Drive a bug fix end-to-end with the discipline of reproduce → failing test (when test infra exists) → minimal fix → atomicity check → handoff to `commit-changes`. Accepts a triage report path, an issue ID/URL (will invoke `triage` first), or a free-form bug description.
when_to_use: When the user says "fix this bug", "fix the bug in ENG-123 / #42", "reproduce and fix X", "debug and fix Y", "X is broken — fix it", "this is crashing — patch it", "investigate and fix Z", or when a prior `triage` report classifies the issue as `bug`. Also fires on phrases like "why does X fail" combined with an ask to repair. SKIP for feature work, refactors, or behavior changes — route those to `ship-change`. SKIP for pure investigation with no fix expected — route to `explain-codebase`.
---

# fix-bug

Enforce the bug-fix discipline: reproduce first, write a failing test when test infrastructure exists, fix, verify atomicity, then hand off to `commit-changes`. Takes a triage report and ends with a clean, scoped fix and verification trail.

## Inputs accepted

In priority order:
1. A triage report path — `.claude/triage/<id>.json` (the normal flow after `triage`).
2. An issue ID or URL — invoke `triage` first, then read its output.
3. A free-form bug description — skip triage. The user owns the missing context.

## Workflow

### 1. Acquire context
Load `.claude/triage/<id>.json`. If only an ID/URL was given, run the `triage` skill first. If only a description was given, hold a minimal in-memory equivalent (title, description, suspected files if any) so later phases can rely on the same shape.

### 2. Reproduce
Produce a deterministic repro before any fix attempt:
- command(s) to run,
- expected behavior,
- actual behavior.

If reproduction fails after reasonable attempts, halt and escalate to the user with the hypotheses tried. **Never proceed to fix without a confirmed repro.** See `references/reproduction-strategies.md` for patterns by bug type.

### 3. Detect test infrastructure
Run `scripts/detect-test-infra.sh` from the target repo root. It emits JSON to stdout:

```
{
  "exists": true,
  "framework": "vitest",
  "test_command": "pnpm test",
  "single_test_command": "pnpm test -- <pattern>",
  "test_dir": "src/__tests__",
  "confidence": "high|medium|low",
  "evidence": ["package.json:devDependencies.vitest", "..."]
}
```

If `exists` is false, skip phase 4 and fall back to manual repro verification in phase 6. See `references/test-frameworks.md` for per-framework single-test invocation.

### 4. Write failing test (conditional)
Write a test that fails specifically because of the bug. Run it once and confirm it fails for the **right** reason — assertion message, not a setup error. The failing test is the contract for the fix.

### 5. Implement the fix
Minimum change that makes the test pass (or the manual repro stop reproducing). No drive-by refactors, no unrelated formatting, no cleanup outside touched code. If the fix would require a broader change, halt and ask before proceeding. See `references/atomicity-rules.md`.

### 6. Verify
- The new test passes.
- The original repro no longer reproduces.
- The broader test suite (or a relevant subset) still passes.

If no test infrastructure was detected, verification is the manual repro plus any smoke checks the user calls out.

### 7. Verify atomicity
Run `scripts/verify-atomic.sh <triage-id>` from the target repo root. It reads `.claude/triage/<id>.json` for scope hints and diffs the working tree against the merge base. JSON output:

```
{
  "files_touched": ["..."],
  "test_files": ["..."],
  "source_files": ["..."],
  "unrelated_candidates": ["..."],
  "lockfile_changes": ["package-lock.json"],
  "warnings": ["..."],
  "stats": { "added": 12, "removed": 4, "files": 3 }
}
```

The script does not block — it surfaces. The agent decides whether each `unrelated_candidate` is actually unrelated and asks the user about the ambiguous ones.

### 8. Update triage state
Write the fix metadata back into `.claude/triage/<id>.json` so `review-changes` can pick up the link later:

```
"fix": {
  "report_path": ".claude/fixes/<id>.md",
  "test_added": true,
  "files_touched": ["..."],
  "verified_at": "<ISO-8601>"
}
```

### 9. Render artifact

Pipe a JSON envelope to the shared renderer to produce a visual fix report. The renderer writes the HTML and opens it in the browser itself — do NOT run `open`, `xdg-open`, `webbrowser`, or any other browser command afterwards, or the artifact will open twice.

```bash
python3 ${CLAUDE_SKILL_DIR}/../../.claude-plugin/scripts/render-artifact.py <<'ARTIFACT_EOF'
{
  "kind": "bugfix",
  "payload": {
    "title": "Short bug title",
    "issue_ref": "ENG-123",
    "status": "fixed|in_progress|blocked",
    "reproduction": {
      "description": "What goes wrong.",
      "steps": ["Step 1", "Step 2"],
      "command": "optional repro command"
    },
    "test": {
      "description": "Why this test pins the bug.",
      "file": "tests/x.spec.ts",
      "code": "the test source",
      "lang": "ts"
    },
    "fix": {
      "summary": "What the fix does and why.",
      "changes": [
        {"file": "src/x.ts", "lang": "ts",
         "diff": [{"type": "context|add|remove", "text": "line content"}]}
      ]
    },
    "atomicity": {
      "description": "Scope of the change.",
      "checks": ["No unrelated edits", "Single concern"]
    },
    "callouts": [{"type": "warning|tip", "text": "Anything the user should know"}]
  }
}
ARTIFACT_EOF
```

**Do not include emojis in any payload text** (titles, summaries, descriptions, callouts, atomicity checks). The renderer styles content with typography and color.

### 10. Handoff
Hand off to `commit-changes`. If the user's convention separates test commits from fix commits, stage them as separate logical groups.

## Outputs

1. `.claude/fixes/<id>.md` — repro recipe, test added (file + name), fix description, verification results, atomicity check summary.
2. Visual HTML artifact opened in the user's browser.
3. The actual code changes (test + fix) in the working tree, ready for `commit-changes`.
4. Updated triage JSON with the `fix` field linked.

## Edge cases

- **No test infrastructure** — skip phase 4, document the manual repro carefully, and note this clearly in the fix report.
- **Bug not reproducible** — halt, present the hypotheses tried, ask for more info or a reproduction recipe from the issue author.
- **Fix requires a breaking change** — flag and ask before implementing; this is `ship-change` territory.
- **Multiple plausible root causes** — diagnose first, present options with tradeoffs, let the user pick.
- **Fix touches generated/vendored files** — flag explicitly; never modify generated files without acknowledgment.
- **Repro requires production data or external services** — halt, document the limitation, ask for a test fixture or staging access.
- **Test infra exists but is broken on main** — surface this; the failing-test contract is unreliable until the suite is green.

## Related skills

- `triage` — produces the triage report this skill consumes.
- `commit-changes` — handoff target after verification (not yet implemented).
