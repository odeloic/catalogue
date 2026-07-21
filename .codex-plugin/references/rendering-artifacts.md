# Rendering artifacts

Skills in this catalogue that produce visual reports share one runtime-neutral
routing rule:

1. If the current agent exposes a native Artifact publishing tool, use it.
2. Otherwise, use the bundled local HTML renderer at
   `.claude-plugin/scripts/render-artifact.py` in the plugin root.

Do not infer native Artifact support from environment variables or configuration
files. The tool must actually be present in the current session. This prevents
Codex from being routed into a Claude Code-only publishing workflow.

## Native path

When a native Artifact tool is available, follow that tool's current design and
publishing instructions. Populate the page from the calling skill's artifact
payload. Keep it self-contained, make no external requests, and do not also run
the local renderer.

If native publishing fails, continue with the local path.

## Local path

Resolve the renderer path from the installed plugin root, then pipe the calling
skill's JSON envelope to it:

```bash
python3 <plugin-root>/.claude-plugin/scripts/render-artifact.py <<'ARTIFACT_EOF'
{ "kind": "...", "payload": { ... } }
ARTIFACT_EOF
```

The renderer writes a self-contained HTML file to the temporary directory and
attempts to open it. Do not run a second browser-opening command. If the current
environment cannot open a browser, surface the generated file path instead.

The kind (`triage` | `review` | `bugfix` | `plan` | `explain`) and payload shape
are defined by each calling skill.

## Surface

Finish with the calling skill's one-line summary and the artifact URL or local
path. Keep payload text free of emojis; the renderer provides the visual
hierarchy.
