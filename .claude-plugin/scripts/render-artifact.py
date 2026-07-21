#!/usr/bin/env python3
"""Shared HTML artifact renderer for catalogue skills.

Fallback path only: skills prefer Claude Code's native Artifact publishing
(guided by the built-in `artifact-design` skill) and drop to this renderer when
native artifacts are disabled. See `../references/rendering-artifacts.md` and
`artifact-enabled.sh` for the routing rule.

Reads a JSON envelope from stdin or argv:
  {"kind": "triage"|"review"|"bugfix"|"plan"|"explain", "payload": {...}}

Writes a self-contained HTML file to /tmp/catalogue-<kind>-<ts>.html and opens it.
Model emits only payload content — template + CSS live here, off the token budget.
"""

from __future__ import annotations

import json
import re
import sys
import webbrowser
from datetime import datetime
from pathlib import Path


# ---------- helpers ----------

def _esc(text) -> str:
    if text is None:
        return ""
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def _esc_rich(text) -> str:
    """Escape HTML but render `code` spans, **bold**, and bare URLs."""
    if text is None:
        return ""
    s = _esc(text)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(
        r"(https?://[^\s<]+)",
        r'<a href="\1" target="_blank" rel="noopener">\1</a>',
        s,
    )
    return s


def _md_paragraphs(text) -> str:
    """Tiny markdown: split on blank lines, render `code`, **bold**, links per paragraph."""
    if not text:
        return ""
    blocks = [b.strip() for b in re.split(r"\n\s*\n", str(text)) if b.strip()]
    return "\n".join(f"<p>{_esc_rich(b)}</p>" for b in blocks)


def _callout(ctype: str, text: str) -> str:
    return (
        f'<div class="callout {_esc(ctype)}">'
        f'<span>{_esc_rich(text)}</span></div>'
    )


def _file_badge(path) -> str:
    return f'<span class="file-badge">{_esc(path)}</span>' if path else ""


def _chip(text: str, variant: str = "") -> str:
    cls = f"chip {variant}".strip()
    return f'<span class="{cls}">{_esc(text)}</span>'


def _diff_block(diff_lines, lang: str = "") -> str:
    if not diff_lines:
        return ""
    out = []
    for dl in diff_lines:
        t = dl.get("type", "context")
        prefix = {"add": "+ ", "remove": "- ", "context": "  "}.get(t, "  ")
        out.append(f'<span class="line-{t}">{_esc(prefix + dl.get("text", ""))}</span>')
    lang_label = f'<span class="lang-label">{_esc(lang)}</span>' if lang else ""
    return f'<pre>{lang_label}<code>{"".join(out)}</code></pre>'


def _code_block(code: str, lang: str = "") -> str:
    if not code:
        return ""
    lang_label = f'<span class="lang-label">{_esc(lang)}</span>' if lang else ""
    return f'<pre>{lang_label}<code>{_esc(code)}</code></pre>'


# ---------- per-kind renderers ----------

def render_triage(p: dict) -> tuple:
    """Returns ((badge, accent, body_html), title, source_url)."""
    classification = (p.get("classification") or "unknown").lower()
    color_map = {
        "bug": "danger",
        "feature": "accent",
        "improvement": "success",
        "change": "warning",
        "unknown": "muted",
    }
    accent = color_map.get(classification, "accent")
    confidence = p.get("confidence", "")

    chips = [_chip(classification.upper(), f"chip-{accent}")]
    if confidence:
        chips.append(_chip(f"confidence: {confidence}"))
    if p.get("id"):
        chips.append(_chip(p["id"], "chip-mono"))
    if p.get("source"):
        chips.append(_chip(p["source"]))

    parts = [f'<div class="chip-row">{"".join(chips)}</div>']

    if p.get("summary"):
        parts.append(_section("Summary", _md_paragraphs(p["summary"])))

    if p.get("context"):
        items = "".join(f"<li>{_esc_rich(c)}</li>" for c in p["context"])
        parts.append(_section("Context", f"<ul>{items}</ul>"))

    if p.get("acceptance_criteria"):
        items = "".join(f"<li>{_esc_rich(a)}</li>" for a in p["acceptance_criteria"])
        parts.append(_section("Acceptance Criteria", f"<ul>{items}</ul>"))

    if p.get("related"):
        rows = []
        for r in p["related"]:
            rid = _esc(r.get("id", ""))
            title = _esc(r.get("title", ""))
            url = r.get("url", "")
            link = f'<a href="{_esc(url)}" target="_blank" rel="noopener">{rid}</a>' if url else rid
            rows.append(f"<li>{link} — {title}</li>")
        parts.append(_section("Related Issues", f'<ul>{"".join(rows)}</ul>'))

    if p.get("prior_attempts"):
        out = []
        for a in p["prior_attempts"]:
            ref = _esc(a.get("ref", ""))
            outcome = _esc(a.get("outcome", ""))
            notes = _esc_rich(a.get("notes", ""))
            out.append(
                f'<div class="attempt"><strong>{ref}</strong> — '
                f'<em>{outcome}</em><p>{notes}</p></div>'
            )
        parts.append(_section("Prior Attempts", "".join(out)))

    for c in p.get("callouts", []):
        parts.append(_callout(c.get("type", "info"), c.get("text", "")))

    title = p.get("title") or p.get("id") or "Triage Report"
    return ("Triage Report", accent, "".join(parts)), title, p.get("source_url", "")


SEV_LABEL = {"high": "Blocker", "medium": "Major", "low": "Minor", "info": "Nit"}
SEV_CLASS = {"high": "danger", "medium": "warning", "low": "muted", "info": "muted"}
SEV_ORDER = ("high", "medium", "low", "info")


def _group_title(group: dict) -> str:
    """Section heading for a sub-project group; counts findings, notes file count."""
    total = len(group.get("findings") or [])
    name = group.get("name")
    if not name:
        return f"Findings ({total})"
    files = group.get("files_changed")
    suffix = f", {files} files" if files else ""
    return f"{name} ({total}{suffix})"


def _render_findings(findings: list) -> str:
    """One finding block: severity + location, what's wrong, the diff, the draft comment."""
    ordered = sorted(
        findings,
        key=lambda f: SEV_ORDER.index((f.get("severity") or "info").lower())
        if (f.get("severity") or "info").lower() in SEV_ORDER
        else len(SEV_ORDER),
    )

    out = []
    for f in ordered:
        sev = (f.get("severity") or "info").lower()
        head = []
        if f.get("id"):
            head.append(_chip(f["id"], "chip-mono"))
        head.append(_chip(SEV_LABEL.get(sev, "Nit"), f'chip-{SEV_CLASS.get(sev, "muted")}'))

        loc = f.get("file") or ""
        if loc and f.get("line"):
            loc = f'{loc}:{f["line"]}'
        loc_html = f'<div class="location">{_esc(loc)}</div>' if loc else ""

        blocks = [
            f'<div class="chip-row">{"".join(head)}</div>',
            f'<h3>{_esc(f.get("title", ""))}</h3>',
            loc_html,
            _md_paragraphs(f.get("detail", "")),
        ]

        if f.get("diff"):
            blocks.append('<div class="block-label">In the diff</div>')
            blocks.append(_diff_block(f["diff"]))

        if f.get("repro"):
            blocks.append('<div class="block-label">Reproduced</div>')
            blocks.append(_code_block(f["repro"]))

        if f.get("fix"):
            blocks.append('<div class="block-label">Proposed fix</div>')
            blocks.append(_diff_block(f["fix"]))

        if f.get("draft_comment"):
            blocks.append(
                '<div class="draft">'
                '<div class="draft-label">Draft comment</div>'
                f'{_md_paragraphs(f["draft_comment"])}'
                "</div>"
            )

        out.append(f'<div class="finding">{"".join(blocks)}</div>')

    return "".join(out)


def render_review(p: dict) -> tuple:
    recommendation = (p.get("recommendation") or "comment").lower()
    rec_color = {
        "approve": "success",
        "request_changes": "danger",
        "comment": "accent",
    }.get(recommendation, "accent")

    chips = [_chip(recommendation.replace("_", " ").upper(), f"chip-{rec_color}")]
    if p.get("issue_ref"):
        chips.append(_chip(p["issue_ref"], "chip-mono"))
    if p.get("branch"):
        chips.append(_chip(p["branch"], "chip-mono"))
    if p.get("files_changed") is not None:
        chips.append(_chip(f'{p["files_changed"]} files'))

    parts = [f'<div class="chip-row">{"".join(chips)}</div>']

    if p.get("summary"):
        parts.append(_section("Summary", _md_paragraphs(p["summary"])))

    if p.get("acceptance_criteria"):
        rows = []
        for ac in p["acceptance_criteria"]:
            status = (ac.get("status") or "unknown").lower()
            status_label = {"met": "Met", "partial": "Partial", "missed": "Missed"}.get(status, "Unknown")
            status_class = {"met": "success", "partial": "warning", "missed": "danger"}.get(status, "muted")
            status_chip = f'<span class="chip chip-{status_class}">{status_label}</span>'
            rows.append(
                f"<tr><td>{status_chip}</td>"
                f"<td>{_esc_rich(ac.get('criterion', ''))}</td>"
                f"<td>{_esc_rich(ac.get('note', ''))}</td></tr>"
            )
        table = (
            '<table class="ac-table"><thead>'
            '<tr><th>Status</th><th>Criterion</th><th>Note</th></tr>'
            f'</thead><tbody>{"".join(rows)}</tbody></table>'
        )
        parts.append(_section("Acceptance Criteria", table))

    # Findings arrive grouped by sub-project. A flat findings[] is treated as a
    # single unnamed group so older payloads keep rendering.
    groups = p.get("subprojects")
    if not groups:
        groups = [{"findings": p.get("findings", [])}] if p.get("findings") else []

    for g in groups:
        fs = g.get("findings") or []
        if not fs:
            continue
        parts.append(_section(_group_title(g), _render_findings(fs)))

    if p.get("open_questions"):
        items = "".join(f"<li>{_esc_rich(q)}</li>" for q in p["open_questions"])
        parts.append(_section("Open Questions", f"<ul>{items}</ul>"))

    title = p.get("pr_title") or p.get("branch") or "Code Review"
    return ("Code Review", rec_color, "".join(parts)), title, p.get("pr_url", "")


def render_bugfix(p: dict) -> tuple:
    chips = []
    if p.get("issue_ref"):
        chips.append(_chip(p["issue_ref"], "chip-mono"))
    if p.get("status"):
        status = p["status"].lower()
        col = {"fixed": "success", "in_progress": "warning", "blocked": "danger"}.get(status, "accent")
        chips.append(_chip(status.upper(), f"chip-{col}"))

    parts = [f'<div class="chip-row">{"".join(chips)}</div>'] if chips else []

    if p.get("reproduction"):
        body = _md_paragraphs(p["reproduction"].get("description") if isinstance(p["reproduction"], dict) else p["reproduction"])
        if isinstance(p["reproduction"], dict) and p["reproduction"].get("steps"):
            items = "".join(f"<li>{_esc_rich(s)}</li>" for s in p["reproduction"]["steps"])
            body += f"<ol>{items}</ol>"
        if isinstance(p["reproduction"], dict) and p["reproduction"].get("command"):
            body += _code_block(p["reproduction"]["command"], "bash")
        parts.append(_section("Reproduction", body))

    if p.get("test"):
        t = p["test"]
        body = ""
        if t.get("description"):
            body += _md_paragraphs(t["description"])
        if t.get("file"):
            body += f'<div class="location">{_esc(t["file"])}</div>'
        if t.get("code"):
            body += _code_block(t["code"], t.get("lang", ""))
        parts.append(_section("Failing Test", body))

    if p.get("fix"):
        f = p["fix"]
        body = _md_paragraphs(f.get("summary", "")) if isinstance(f, dict) else _md_paragraphs(f)
        if isinstance(f, dict):
            for change in f.get("changes", []):
                file_path = change.get("file", "")
                body += f'<div class="location">{_esc(file_path)}</div>'
                if change.get("diff"):
                    body += _diff_block(change["diff"], change.get("lang", ""))
                elif change.get("code"):
                    body += _code_block(change["code"], change.get("lang", ""))
        parts.append(_section("Fix", body))

    if p.get("atomicity"):
        a = p["atomicity"]
        body = _md_paragraphs(a.get("description", "")) if isinstance(a, dict) else _md_paragraphs(a)
        if isinstance(a, dict) and a.get("checks"):
            items = "".join(f"<li>{_esc_rich(c)}</li>" for c in a["checks"])
            body += f"<ul>{items}</ul>"
        parts.append(_section("Atomicity Check", body))

    for c in p.get("callouts", []):
        parts.append(_callout(c.get("type", "info"), c.get("text", "")))

    title = p.get("title") or p.get("issue_ref") or "Bug Fix"
    return ("Bug Fix", "danger", "".join(parts)), title, ""


def render_plan(p: dict) -> tuple:
    stage = (p.get("stage") or "plan").lower()
    accent = "accent" if stage == "plan" else "success"

    chips = [_chip(stage.upper(), f"chip-{accent}")]
    if p.get("issue_ref"):
        chips.append(_chip(p["issue_ref"], "chip-mono"))
    if p.get("classification"):
        chips.append(_chip(p["classification"]))

    parts = [f'<div class="chip-row">{"".join(chips)}</div>']

    if p.get("summary"):
        parts.append(_section("Goal", _md_paragraphs(p["summary"])))

    if p.get("approach"):
        parts.append(_section("Approach", _md_paragraphs(p["approach"])))

    if p.get("steps"):
        items = []
        status_label = {
            "pending": "Pending",
            "in_progress": "In progress",
            "done": "Done",
            "blocked": "Blocked",
            "skipped": "Skipped",
        }
        status_class = {
            "pending": "muted",
            "in_progress": "warning",
            "done": "success",
            "blocked": "danger",
            "skipped": "muted",
        }
        for i, step in enumerate(p["steps"], 1):
            status = (step.get("status") or "pending").lower()
            label = status_label.get(status, "Pending")
            cls = status_class.get(status, "muted")
            status_chip = f'<span class="chip chip-{cls}">{label}</span>'
            files = ""
            if step.get("files"):
                badges = "".join(_file_badge(f) for f in step["files"])
                files = f'<div class="file-list">{badges}</div>'
            description = ""
            if step.get("description"):
                description = _md_paragraphs(step["description"])
            verification = ""
            if step.get("verification"):
                verification = _callout("info", f"Verify: {step['verification']}")
            items.append(
                f'<div class="step">'
                f'<div class="step-number">{i}</div>'
                f'<div class="step-header"><h3>{_esc(step.get("title", ""))} {status_chip}</h3></div>'
                f'{files}'
                f'{description}'
                f'{verification}'
                f'</div>'
            )
        label = "Plan Steps" if stage == "plan" else "Execution Log"
        parts.append(_section(label, "".join(items)))

    if p.get("verification"):
        v = p["verification"]
        body = _md_paragraphs(v.get("description", "")) if isinstance(v, dict) else _md_paragraphs(v)
        if isinstance(v, dict) and v.get("steps"):
            items = "".join(f"<li>{_esc_rich(s)}</li>" for s in v["steps"])
            body += f"<ol>{items}</ol>"
        if isinstance(v, dict) and v.get("command"):
            body += _code_block(v["command"], "bash")
        parts.append(_section("Verification", body))

    if p.get("risks"):
        items = "".join(f"<li>{_esc_rich(r)}</li>" for r in p["risks"])
        parts.append(_section("Risks", f"<ul>{items}</ul>"))

    for c in p.get("callouts", []):
        parts.append(_callout(c.get("type", "info"), c.get("text", "")))

    title = p.get("title") or p.get("issue_ref") or "Change Plan"
    label = "Plan (Awaiting Approval)" if stage == "plan" else "Execution Log"
    return (label, accent, "".join(parts)), title, ""


def render_explain(p: dict) -> tuple:
    chips = []
    if p.get("question"):
        chips.append(_chip("question", "chip-mono"))
    if p.get("files_touched"):
        chips.append(_chip(f'{len(p["files_touched"])} files'))

    parts = []
    if chips:
        parts.append(f'<div class="chip-row">{"".join(chips)}</div>')

    if p.get("question"):
        parts.append(
            f'<div class="callout info">'
            f'<span><strong>Question:</strong> {_esc_rich(p["question"])}</span></div>'
        )

    if p.get("summary"):
        parts.append(_section("Short Answer", _md_paragraphs(p["summary"])))

    if p.get("mermaid"):
        parts.append(_section(
            "Diagram",
            f'<div class="mermaid">{_esc(p["mermaid"])}</div>'
        ))

    for section in p.get("sections", []):
        heading = section.get("heading", "")
        body_parts = []
        if section.get("markdown"):
            body_parts.append(_md_paragraphs(section["markdown"]))
        for c in section.get("citations", []):
            file_path = c.get("file", "")
            line = c.get("line", "")
            loc = f"{file_path}:{line}" if line else file_path
            note = c.get("note", "")
            body_parts.append(
                f'<div class="citation">'
                f'<span class="file-badge">{_esc(loc)}</span>'
                f'{f"<span> — {_esc_rich(note)}</span>" if note else ""}'
                f'</div>'
            )
        if section.get("code"):
            body_parts.append(_code_block(section["code"], section.get("lang", "")))
        parts.append(_section(heading, "".join(body_parts)))

    if p.get("files_touched"):
        badges = "".join(_file_badge(f) for f in p["files_touched"])
        parts.append(_section("Files Referenced", f'<div class="file-list">{badges}</div>'))

    for c in p.get("callouts", []):
        parts.append(_callout(c.get("type", "info"), c.get("text", "")))

    title = p.get("title") or "Codebase Explanation"
    return ("Explanation", "accent", "".join(parts)), title, ""


# ---------- section + page shell ----------

def _section(title: str, content: str) -> str:
    return (
        f'<div class="section">'
        f'<h2>{_esc(title)}</h2>'
        f'{content}'
        f'</div>'
    )


KIND_DISPATCH = {
    "triage": render_triage,
    "review": render_review,
    "bugfix": render_bugfix,
    "plan": render_plan,
    "explain": render_explain,
}


def render_page(kind: str, payload: dict) -> str:
    renderer = KIND_DISPATCH.get(kind)
    if not renderer:
        raise ValueError(f"Unknown kind '{kind}'. Expected one of: {', '.join(KIND_DISPATCH)}")

    (badge_text, accent, body), title, source_url = renderer(payload)

    source_link = ""
    if source_url:
        source_link = (
            f'<a class="source-link" href="{_esc(source_url)}" '
            f'target="_blank" rel="noopener">↗ source</a>'
        )

    mermaid_script = ""
    if kind == "explain" and payload.get("mermaid"):
        mermaid_script = (
            '<script type="module">'
            "import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';"
            "mermaid.initialize({ startOnLoad: true, theme: 'dark', "
            "themeVariables: { background: '#0f1117', primaryColor: '#1a1d27', "
            "primaryTextColor: '#e4e4e7', primaryBorderColor: '#2a2e3a', "
            "lineColor: '#818cf8' } });"
            "</script>"
        )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{_esc(title)}</title>
<style>{CSS}</style>
</head>
<body>
<div class="header header-{accent}">
<div class="badge badge-{accent}">{_esc(badge_text)}</div>
<h1>{_esc(title)}</h1>
{source_link}
</div>
{body}
<div class="footer">Generated by catalogue/{_esc(kind)} · {datetime.now().strftime("%Y-%m-%d %H:%M")}</div>
{mermaid_script}
</body>
</html>"""


CSS = """
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
:root {
  --bg: #F5F4ED;
  --surface: #FFFFFF;
  --surface-2: #FAFAF7;
  --border: #E8E6DD;
  --border-strong: #D4D1C4;
  --text: #1A1A1A;
  --text-muted: #6B6B6B;
  --text-subtle: #8E8E83;
  --accent: #C96442;
  --accent-soft: #F4E4DC;
  --accent-deep: #A04F33;
  --success: #4F7A4F;
  --success-soft: #E4EBE0;
  --warning: #B8893B;
  --warning-soft: #F2E8D2;
  --danger: #B5443A;
  --danger-soft: #F2DAD6;
  --muted-color: #6B6B6B;
  --muted-soft: #ECEAE0;
  --radius: 6px;
  --radius-lg: 10px;
  --font-mono: 'SF Mono', 'JetBrains Mono', 'Fira Code', ui-monospace, monospace;
  --font-sans: 'Söhne', 'Inter', -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
  --font-serif: 'Tiempos Text', 'Charter', 'Iowan Old Style', 'Georgia', serif;
}
body {
  font-family: var(--font-sans);
  background: var(--bg);
  color: var(--text);
  line-height: 1.65;
  font-size: 16px;
  padding: 3rem 2rem 4rem;
  max-width: 760px;
  margin: 0 auto;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}
.header {
  padding: 0 0 2rem;
  margin-bottom: 2.5rem;
  border-bottom: 1px solid var(--border-strong);
}
.badge {
  display: inline-block;
  font-size: 0.72rem;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  padding: 0;
  margin-bottom: 1.25rem;
  color: var(--accent);
  background: none;
}
.badge-success { color: var(--success); }
.badge-danger { color: var(--danger); }
.badge-warning { color: var(--warning); }
.badge-muted { color: var(--text-subtle); }
.header h1 {
  font-family: var(--font-serif);
  font-size: 2.25rem;
  font-weight: 400;
  line-height: 1.15;
  letter-spacing: -0.015em;
  color: var(--text);
  margin-bottom: 0.5rem;
}
.source-link {
  display: inline-block;
  font-size: 0.85rem;
  color: var(--text-muted);
  margin-top: 0.75rem;
  text-decoration: none;
  border-bottom: 1px solid transparent;
  transition: border-color 0.15s;
}
.source-link:hover { border-bottom-color: var(--accent); color: var(--accent); }
.chip-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  margin: 1rem 0 1.5rem;
}
.chip {
  display: inline-block;
  font-size: 0.74rem;
  font-weight: 500;
  padding: 0.2rem 0.6rem;
  border-radius: 4px;
  background: var(--muted-soft);
  color: var(--text-muted);
  letter-spacing: 0.01em;
}
.chip-mono { font-family: var(--font-mono); font-size: 0.72rem; padding: 0.15rem 0.5rem; }
.chip-accent { color: var(--accent-deep); background: var(--accent-soft); }
.chip-success { color: var(--success); background: var(--success-soft); }
.chip-danger { color: var(--danger); background: var(--danger-soft); }
.chip-warning { color: var(--warning); background: var(--warning-soft); }
.chip-muted { color: var(--text-muted); background: var(--muted-soft); }
.section {
  padding: 1.75rem 0 1.5rem;
  margin: 0;
  border-bottom: 1px solid var(--border);
}
.section:last-of-type { border-bottom: none; }
.section h2 {
  font-family: var(--font-serif);
  font-size: 1.35rem;
  font-weight: 400;
  letter-spacing: -0.01em;
  line-height: 1.3;
  color: var(--text);
  margin-bottom: 1rem;
}
.section h3 {
  font-size: 0.95rem;
  font-weight: 600;
  margin: 1.25rem 0 0.5rem;
  color: var(--text);
  letter-spacing: -0.005em;
}
.section h3:first-child { margin-top: 0; }
.section p { color: var(--text); font-size: 0.95rem; line-height: 1.7; margin: 0.5rem 0; }
.section li { color: var(--text); font-size: 0.95rem; line-height: 1.7; margin-bottom: 0.35rem; }
.section ul, .section ol { padding-left: 1.4rem; margin: 0.6rem 0; }
.section li strong { color: var(--text); font-weight: 600; }
pre {
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 0.95rem 1.1rem;
  overflow-x: auto;
  margin: 0.85rem 0;
  font-family: var(--font-mono);
  font-size: 0.825rem;
  line-height: 1.65;
  color: var(--text);
  position: relative;
}
.lang-label {
  position: absolute;
  top: 0.45rem; right: 0.7rem;
  font-size: 0.65rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-subtle);
  font-family: var(--font-sans);
  font-weight: 500;
}
code {
  font-family: var(--font-mono);
  font-size: 0.88em;
  background: var(--surface-2);
  padding: 0.1em 0.35em;
  border-radius: 3px;
  color: var(--accent-deep);
  border: 1px solid var(--border);
}
pre code { background: none; padding: 0; color: inherit; border: none; }
.line-add {
  background: rgba(79, 122, 79, 0.08);
  display: block;
  margin: 0 -1.1rem;
  padding: 0 1.1rem;
  border-left: 2px solid var(--success);
}
.line-remove {
  background: rgba(181, 68, 58, 0.06);
  display: block;
  margin: 0 -1.1rem;
  padding: 0 1.1rem;
  border-left: 2px solid var(--danger);
  opacity: 0.7;
}
.line-context { display: block; margin: 0 -1.1rem; padding: 0 1.1rem; opacity: 0.55; }
.callout {
  display: flex;
  gap: 0.7rem;
  padding: 0.85rem 1.1rem;
  border-radius: var(--radius);
  margin: 0.85rem 0;
  font-size: 0.92rem;
  line-height: 1.6;
  background: var(--surface-2);
  border-left: 2px solid var(--text-subtle);
  color: var(--text);
}
.callout.info { border-left-color: var(--accent); background: var(--accent-soft); color: var(--text); }
.callout.tip { border-left-color: var(--success); background: var(--success-soft); color: var(--text); }
.callout.warning { border-left-color: var(--warning); background: var(--warning-soft); color: var(--text); }
.callout.danger { border-left-color: var(--danger); background: var(--danger-soft); color: var(--text); }
.file-badge {
  display: inline-block;
  font-family: var(--font-mono);
  font-size: 0.75rem;
  background: var(--muted-soft);
  color: var(--text-muted);
  padding: 0.18rem 0.5rem;
  border-radius: 3px;
  margin: 0.15rem 0.15rem 0.15rem 0;
}
.file-list { display: flex; flex-wrap: wrap; gap: 0.35rem; margin: 0.5rem 0; }
.location {
  font-family: var(--font-mono);
  font-size: 0.78rem;
  color: var(--text-subtle);
  margin: 0.3rem 0 0.5rem;
}
.ac-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.92rem;
  margin: 0.75rem 0;
}
.ac-table th, .ac-table td {
  text-align: left;
  padding: 0.7rem 0.85rem;
  border-bottom: 1px solid var(--border);
  vertical-align: top;
}
.ac-table th {
  color: var(--text-subtle);
  font-weight: 500;
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  border-bottom: 1px solid var(--border-strong);
}
.ac-table td { color: var(--text); }
.ac-table td:first-child { width: 32px; text-align: center; padding-right: 0; }
.ac-table tr:last-child td { border-bottom: none; }
.finding {
  padding: 0.5rem 0 0.85rem;
  margin: 0;
  border-bottom: 1px solid var(--border);
}
.finding:last-child { border-bottom: none; }
.finding h3 { font-size: 0.98rem; font-weight: 600; color: var(--text); margin: 0.3rem 0 0.25rem; }
.block-label {
  font-family: var(--font-mono);
  font-size: 0.68rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--text-subtle);
  margin: 0.85rem 0 0.3rem;
}
.draft {
  border-left: 3px solid var(--accent);
  background: var(--accent-soft);
  border-radius: 0 var(--radius) var(--radius) 0;
  padding: 0.7rem 0.9rem;
  margin: 0.9rem 0 0.2rem;
}
.draft-label {
  font-family: var(--font-mono);
  font-size: 0.68rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--accent-deep);
  font-weight: 600;
  margin-bottom: 0.35rem;
}
.draft p { margin: 0 0 0.45rem; }
.draft p:last-child { margin-bottom: 0; }
.attempt {
  padding: 0.5rem 0 0.85rem;
  margin: 0;
  border-bottom: 1px solid var(--border);
}
.attempt:last-child { border-bottom: none; }
.attempt strong { color: var(--text); font-weight: 600; }
.attempt em { color: var(--text-subtle); font-size: 0.85rem; font-style: normal; margin-left: 0.4rem; }
.attempt p { margin-top: 0.35rem; }
.citation {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0.4rem 0;
  font-size: 0.88rem;
  color: var(--text-muted);
}
.step {
  position: relative;
  padding: 0.85rem 0 0.85rem 2.5rem;
  margin: 0;
  border-bottom: 1px solid var(--border);
}
.step:last-child { border-bottom: none; }
.step-number {
  position: absolute;
  top: 0.95rem;
  left: 0;
  font-family: var(--font-mono);
  font-size: 0.85rem;
  width: 1.75rem;
  text-align: left;
  color: var(--text-subtle);
  font-variant-numeric: tabular-nums;
}
.step-header { margin-bottom: 0.3rem; }
.step-header h3 {
  font-size: 1rem;
  font-weight: 600;
  color: var(--text);
  margin: 0;
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.step-header h3 .chip { font-weight: 500; }
.mermaid {
  background: var(--surface);
  padding: 1.5rem;
  border-radius: var(--radius);
  border: 1px solid var(--border);
  text-align: center;
}
a {
  color: var(--accent);
  text-decoration: none;
  border-bottom: 1px solid var(--accent-soft);
  transition: border-color 0.15s;
}
a:hover { border-bottom-color: var(--accent); }
.footer {
  text-align: left;
  color: var(--text-subtle);
  font-size: 0.78rem;
  margin-top: 3rem;
  padding-top: 1.5rem;
  border-top: 1px solid var(--border);
  font-family: var(--font-mono);
  letter-spacing: 0.02em;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1E1E1B;
    --surface: #26262200;
    --surface-2: #2A2A26;
    --border: #36362F;
    --border-strong: #4A4A40;
    --text: #ECECE5;
    --text-muted: #A8A89E;
    --text-subtle: #7A7A70;
    --accent: #E08562;
    --accent-soft: #3D2A22;
    --accent-deep: #F0A084;
    --success: #8FB28F;
    --success-soft: #2A3A2A;
    --warning: #D4A654;
    --warning-soft: #3D331E;
    --danger: #D67B70;
    --danger-soft: #3D2522;
    --muted-soft: #2A2A26;
  }
}
"""


def _read_input() -> str:
    if len(sys.argv) >= 2 and sys.argv[1] not in ("-", "--stdin"):
        return sys.argv[1]
    if not sys.stdin.isatty():
        return sys.stdin.read()
    print(
        "Usage:\n"
        "  python3 render-artifact.py '<json>'\n"
        "  echo '<json>' | python3 render-artifact.py\n\n"
        "Envelope: {\"kind\": \"triage|review|bugfix|plan|explain\", \"payload\": {...}}",
        file=sys.stderr,
    )
    sys.exit(1)


def main() -> None:
    raw = _read_input()
    try:
        envelope = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"Invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)

    kind = envelope.get("kind")
    payload = envelope.get("payload", {})
    if not kind:
        print("Missing 'kind' in envelope.", file=sys.stderr)
        sys.exit(1)

    html = render_page(kind, payload)
    out = Path(f"/tmp/catalogue-{kind}-{int(datetime.now().timestamp())}.html")
    out.write_text(html)
    print(f"Artifact: {out}")
    webbrowser.open(f"file://{out}")


if __name__ == "__main__":
    main()
