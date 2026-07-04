# Rendering artifacts

Every skill in this catalogue that surfaces a visual report shares one routing
rule so that artifacts follow Claude Code's own conventions wherever they can.
There are two rendering paths — pick per session:

1. **Native path (preferred)** — Claude Code's built-in Artifact publishing,
   guided by the built-in `artifact-design` skill. Produces a live page at a
   private `claude.ai` URL with the same design rules as every other Claude Code
   artifact.
2. **Fallback path** — the bundled `render-artifact.py` renderer, used only when
   native artifacts are unavailable.

## Step 1 — decide the path

Run the shared detector once, before rendering:

```bash
bash ${CLAUDE_SKILL_DIR}/../../.claude-plugin/scripts/artifact-enabled.sh
```

- **Exit 0** → native Artifact publishing is available. Use the **native path**.
- **Exit 1** → native artifacts are disabled for this session. Use the
  **fallback path**. The detector prints the reason on stderr.

The detector mirrors Claude Code's own disable knobs
(<https://code.claude.com/docs/en/artifacts#disable-artifacts>): the
`disableArtifact` setting, the `CLAUDE_CODE_DISABLE_ARTIFACT` /
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` environment variables, and an
`Artifact` rule in `permissions.deny`.

## Step 2a — native path

1. **Load the `artifact-design` skill** before writing any HTML — it carries the
   current palette, typography, and layout rules. Do not skip this.
2. **Write a self-contained HTML file** for the report. Populate it from the
   calling skill's "Artifact content" schema (the same fields the fallback
   envelope carries). Follow the design skill: theme-aware, inline everything,
   no external requests, no emojis as section markers.
3. **Publish with the `Artifact` tool**, passing the file path plus a `favicon`
   and a one-line `description`. The tool returns the private URL and opens it.

Do **not** also run `render-artifact.py`, `open`, `xdg-open`, or `webbrowser`
after publishing — that would double-render.

If the `Artifact` tool reports it cannot publish (e.g. wrong plan, not signed in
with `/login`, or an unsupported surface such as the Agent SDK), treat it exactly
like Exit 1 and use the fallback path instead.

## Step 2b — fallback path

Pipe the kind's JSON envelope to the bundled renderer. It writes a
self-contained HTML file to `/tmp` and opens it in the browser itself — do **not**
run any browser command afterwards.

```bash
python3 ${CLAUDE_SKILL_DIR}/../../.claude-plugin/scripts/render-artifact.py <<'ARTIFACT_EOF'
{ "kind": "...", "payload": { ... } }
ARTIFACT_EOF
```

The kind (`triage` | `review` | `bugfix` | `plan` | `explain`) and the payload
shape are defined in each calling skill.

## Step 3 — surface

Whichever path ran, finish with the skill's one-line chat summary (classification
/ recommendation / answer plus the artifact URL or path). Keep payload/content
text free of emojis — both renderers style content with typography and color.
