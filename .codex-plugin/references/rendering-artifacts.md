# Rendering artifacts

Skills in this catalogue that produce visual reports share one rendering rule:
pipe the calling skill's JSON envelope to the bundled renderer. There is **one
path and one design system** — no native/fallback branching.

Resolve the renderer path from the installed plugin root, then pipe the envelope:

```bash
python3 <plugin-root>/.claude-plugin/scripts/render-artifact.py <<'ARTIFACT_EOF'
{ "kind": "...", "payload": { ... } }
ARTIFACT_EOF
```

The renderer writes a self-contained HTML file to the temporary directory and
opens it itself. Do not run a second browser-opening command. If the environment
cannot open a browser, surface the generated file path instead.

The renderer inlines the shared design tokens
(`.claude-plugin/scripts/artifact/tokens.css`, kept in sync with the
`catalogue-design-system` Storybook) plus the component styles, so every artifact
reads as one product. All markup and CSS live in
`.claude-plugin/scripts/artifact/` — change the look there once and every skill's
output follows. It is pure Python stdlib: no virtualenv, no dependencies, no
network.

The kind (`triage` | `review` | `bugfix` | `plan` | `explain`) and payload shape
are defined by each calling skill.

## Surface

Finish with the calling skill's one-line summary and the artifact's file path.
Keep payload text free of emojis; the renderer provides the visual hierarchy.
