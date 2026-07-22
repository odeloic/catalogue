# Review artifact payload

Rendering follows the shared rule in
`../../../.codex-plugin/references/rendering-artifacts.md`, resolved relative to
this file. This file only defines what the `review` artifact contains. The
renderer groups each sub-project into its own section and shows every finding's
diff and draft comment as separate blocks (the draft comment stays copyable on
its own).

Pipe this envelope to the renderer:

```bash
python3 <plugin-root>/.claude-plugin/scripts/render-artifact.py <<'ARTIFACT_EOF'
{
  "kind": "review",
  "payload": {
    "pr_title": "feat: add X",
    "pr_url": "https://github.com/.../pull/N",
    "issue_ref": "ENG-123",
    "branch": "feat/x",
    "files_changed": 14,
    "recommendation": "approve|request_changes|comment",
    "summary": "What the PR does.",
    "acceptance_criteria": [
      {"criterion": "AC text", "status": "met|partial|missed|unknown", "note": "file:line or why not"}
    ],
    "subprojects": [
      {
        "name": "web/bereich-a",
        "files_changed": 3,
        "findings": [
          {
            "id": "BA-1",
            "severity": "high|medium|low|info",
            "title": "Short title",
            "file": "web/bereich-a/src/x.tsx",
            "line": 118,
            "detail": "What breaks, in one or two sentences.",
            "diff": [
              {"type": "context", "text": "fetch(url)"},
              {"type": "remove", "text": "  .then((res) => res.text())"},
              {"type": "add", "text": "  .then((res) => { if (!res.ok) throw new Error(); return res.text(); })"}
            ],
            "draft_comment": "Ready-to-paste comment, ending in a question.",
            "fix": [{"type": "add", "text": "only when show-fix is set"}],
            "repro": "only when reproduce is set; real captured output"
          }
        ]
      }
    ],
    "open_questions": ["Question for the author"]
  }
}
ARTIFACT_EOF
```

## Rules

- Severity map: Blocker → `high`, Major → `medium`, Minor → `low`, Nit → `info`.
- Acceptance-criterion status map: Met → `met`, Partial → `partial`, Missing → `missed`, Can't tell from the diff → `unknown`. Never collapse a can't-tell into `partial` — that reports uncertainty as partial completion. The fallback renderer shows `unknown` as a muted "Unknown" chip.
- Single-project diff: emit one `subprojects` entry with no `name`. The renderer drops the header. A flat top-level `findings[]` also still works.
- Omit `fix` unless `show-fix` was set, and `repro` unless `reproduce` was set.
- Omit any field that does not apply. No emojis in any value.
