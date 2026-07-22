# Rendering artifacts

Every skill in this catalogue that surfaces a visual report renders it the same
way: pipe the skill's JSON envelope to the bundled renderer. There is **one path
and one design system** — the renderer inlines the shared design tokens
(`.claude-plugin/scripts/artifact/tokens.css`, kept in sync with the
`catalogue-design-system` Storybook) plus the component styles, so every artifact
reads as one product.

## Render

```bash
python3 ${CLAUDE_SKILL_DIR}/../../.claude-plugin/scripts/render-artifact.py <<'ARTIFACT_EOF'
{ "kind": "...", "payload": { ... } }
ARTIFACT_EOF
```

The renderer writes a self-contained HTML file to `/tmp` and opens it in the
browser itself — do **not** run `open`, `xdg-open`, `webbrowser`, or any second
browser command afterward. If the environment cannot open a browser, surface the
printed file path instead.

The kind (`triage` | `review` | `bugfix` | `plan` | `explain`) and the payload
shape are defined by each calling skill. All markup and CSS live in
`.claude-plugin/scripts/artifact/` — change the look there once and every skill's
output follows. The renderer is pure Python stdlib: no virtualenv, no
dependencies, no network.

## Surface

Finish with the skill's one-line chat summary (classification / recommendation /
answer) plus the artifact's file path. Keep payload/content text free of emojis —
the renderer provides the visual hierarchy through typography and color.
