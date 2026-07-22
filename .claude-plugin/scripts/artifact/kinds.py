"""Per-kind renderers for catalogue artifacts.

Each renderer returns ((badge, accent, body_html), title, source_url) and is
composed entirely from the builders in components.py — no styling here.
"""

from __future__ import annotations

from .components import (
    callout,
    chip,
    code_block,
    diff_block,
    esc,
    esc_rich,
    file_badge,
    md_paragraphs,
    section,
)


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

    chips = [chip(classification.upper(), f"chip-{accent}")]
    if confidence:
        chips.append(chip(f"confidence: {confidence}"))
    if p.get("id"):
        chips.append(chip(p["id"], "chip-mono"))
    if p.get("source"):
        chips.append(chip(p["source"]))

    parts = [f'<div class="chip-row">{"".join(chips)}</div>']

    if p.get("summary"):
        parts.append(section("Summary", md_paragraphs(p["summary"])))

    if p.get("context"):
        items = "".join(f"<li>{esc_rich(c)}</li>" for c in p["context"])
        parts.append(section("Context", f"<ul>{items}</ul>"))

    if p.get("acceptance_criteria"):
        items = "".join(f"<li>{esc_rich(a)}</li>" for a in p["acceptance_criteria"])
        parts.append(section("Acceptance Criteria", f"<ul>{items}</ul>"))

    if p.get("related"):
        rows = []
        for r in p["related"]:
            rid = esc(r.get("id", ""))
            title = esc(r.get("title", ""))
            url = r.get("url", "")
            link = f'<a href="{esc(url)}" target="_blank" rel="noopener">{rid}</a>' if url else rid
            rows.append(f"<li>{link} — {title}</li>")
        parts.append(section("Related Issues", f'<ul>{"".join(rows)}</ul>'))

    if p.get("prior_attempts"):
        out = []
        for a in p["prior_attempts"]:
            ref = esc(a.get("ref", ""))
            outcome = esc(a.get("outcome", ""))
            notes = esc_rich(a.get("notes", ""))
            out.append(
                f'<div class="attempt"><strong>{ref}</strong> — '
                f'<em>{outcome}</em><p>{notes}</p></div>'
            )
        parts.append(section("Prior Attempts", "".join(out)))

    for c in p.get("callouts", []):
        parts.append(callout(c.get("type", "info"), c.get("text", "")))

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
            head.append(chip(f["id"], "chip-mono"))
        head.append(chip(SEV_LABEL.get(sev, "Nit"), f'chip-{SEV_CLASS.get(sev, "muted")}'))

        loc = f.get("file") or ""
        if loc and f.get("line"):
            loc = f'{loc}:{f["line"]}'
        loc_html = f'<div class="location">{esc(loc)}</div>' if loc else ""

        blocks = [
            f'<div class="chip-row">{"".join(head)}</div>',
            f'<h3>{esc(f.get("title", ""))}</h3>',
            loc_html,
            md_paragraphs(f.get("detail", "")),
        ]

        if f.get("diff"):
            blocks.append('<div class="block-label">In the diff</div>')
            blocks.append(diff_block(f["diff"]))

        if f.get("repro"):
            blocks.append('<div class="block-label">Reproduced</div>')
            blocks.append(code_block(f["repro"]))

        if f.get("fix"):
            blocks.append('<div class="block-label">Proposed fix</div>')
            blocks.append(diff_block(f["fix"]))

        if f.get("draft_comment"):
            blocks.append(
                '<div class="draft">'
                '<div class="draft-label">Draft comment</div>'
                f'{md_paragraphs(f["draft_comment"])}'
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

    chips = [chip(recommendation.replace("_", " ").upper(), f"chip-{rec_color}")]
    if p.get("issue_ref"):
        chips.append(chip(p["issue_ref"], "chip-mono"))
    if p.get("branch"):
        chips.append(chip(p["branch"], "chip-mono"))
    if p.get("files_changed") is not None:
        chips.append(chip(f'{p["files_changed"]} files'))

    parts = [f'<div class="chip-row">{"".join(chips)}</div>']

    if p.get("summary"):
        parts.append(section("Summary", md_paragraphs(p["summary"])))

    if p.get("acceptance_criteria"):
        rows = []
        for ac in p["acceptance_criteria"]:
            status = (ac.get("status") or "unknown").lower()
            status_label = {"met": "Met", "partial": "Partial", "missed": "Missed"}.get(status, "Unknown")
            status_class = {"met": "success", "partial": "warning", "missed": "danger"}.get(status, "muted")
            status_chip = f'<span class="chip chip-{status_class}">{status_label}</span>'
            rows.append(
                f"<tr><td>{status_chip}</td>"
                f"<td>{esc_rich(ac.get('criterion', ''))}</td>"
                f"<td>{esc_rich(ac.get('note', ''))}</td></tr>"
            )
        table = (
            '<table class="ac-table"><thead>'
            '<tr><th>Status</th><th>Criterion</th><th>Note</th></tr>'
            f'</thead><tbody>{"".join(rows)}</tbody></table>'
        )
        parts.append(section("Acceptance Criteria", table))

    # Findings arrive grouped by sub-project. A flat findings[] is treated as a
    # single unnamed group so older payloads keep rendering.
    groups = p.get("subprojects")
    if not groups:
        groups = [{"findings": p.get("findings", [])}] if p.get("findings") else []

    for g in groups:
        fs = g.get("findings") or []
        if not fs:
            continue
        parts.append(section(_group_title(g), _render_findings(fs)))

    if p.get("open_questions"):
        items = "".join(f"<li>{esc_rich(q)}</li>" for q in p["open_questions"])
        parts.append(section("Open Questions", f"<ul>{items}</ul>"))

    title = p.get("pr_title") or p.get("branch") or "Code Review"
    return ("Code Review", rec_color, "".join(parts)), title, p.get("pr_url", "")


def render_bugfix(p: dict) -> tuple:
    chips = []
    if p.get("issue_ref"):
        chips.append(chip(p["issue_ref"], "chip-mono"))
    if p.get("status"):
        status = p["status"].lower()
        col = {"fixed": "success", "in_progress": "warning", "blocked": "danger"}.get(status, "accent")
        chips.append(chip(status.upper(), f"chip-{col}"))

    parts = [f'<div class="chip-row">{"".join(chips)}</div>'] if chips else []

    if p.get("reproduction"):
        body = md_paragraphs(p["reproduction"].get("description") if isinstance(p["reproduction"], dict) else p["reproduction"])
        if isinstance(p["reproduction"], dict) and p["reproduction"].get("steps"):
            items = "".join(f"<li>{esc_rich(s)}</li>" for s in p["reproduction"]["steps"])
            body += f"<ol>{items}</ol>"
        if isinstance(p["reproduction"], dict) and p["reproduction"].get("command"):
            body += code_block(p["reproduction"]["command"], "bash")
        parts.append(section("Reproduction", body))

    if p.get("test"):
        t = p["test"]
        body = ""
        if t.get("description"):
            body += md_paragraphs(t["description"])
        if t.get("file"):
            body += f'<div class="location">{esc(t["file"])}</div>'
        if t.get("code"):
            body += code_block(t["code"], t.get("lang", ""))
        parts.append(section("Failing Test", body))

    if p.get("fix"):
        f = p["fix"]
        body = md_paragraphs(f.get("summary", "")) if isinstance(f, dict) else md_paragraphs(f)
        if isinstance(f, dict):
            for change in f.get("changes", []):
                file_path = change.get("file", "")
                body += f'<div class="location">{esc(file_path)}</div>'
                if change.get("diff"):
                    body += diff_block(change["diff"], change.get("lang", ""))
                elif change.get("code"):
                    body += code_block(change["code"], change.get("lang", ""))
        parts.append(section("Fix", body))

    if p.get("atomicity"):
        a = p["atomicity"]
        body = md_paragraphs(a.get("description", "")) if isinstance(a, dict) else md_paragraphs(a)
        if isinstance(a, dict) and a.get("checks"):
            items = "".join(f"<li>{esc_rich(c)}</li>" for c in a["checks"])
            body += f"<ul>{items}</ul>"
        parts.append(section("Atomicity Check", body))

    for c in p.get("callouts", []):
        parts.append(callout(c.get("type", "info"), c.get("text", "")))

    title = p.get("title") or p.get("issue_ref") or "Bug Fix"
    return ("Bug Fix", "danger", "".join(parts)), title, ""


def render_plan(p: dict) -> tuple:
    stage = (p.get("stage") or "plan").lower()
    accent = "accent" if stage == "plan" else "success"

    chips = [chip(stage.upper(), f"chip-{accent}")]
    if p.get("issue_ref"):
        chips.append(chip(p["issue_ref"], "chip-mono"))
    if p.get("classification"):
        chips.append(chip(p["classification"]))

    parts = [f'<div class="chip-row">{"".join(chips)}</div>']

    if p.get("summary"):
        parts.append(section("Goal", md_paragraphs(p["summary"])))

    if p.get("approach"):
        parts.append(section("Approach", md_paragraphs(p["approach"])))

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
                badges = "".join(file_badge(f) for f in step["files"])
                files = f'<div class="file-list">{badges}</div>'
            description = ""
            if step.get("description"):
                description = md_paragraphs(step["description"])
            verification = ""
            if step.get("verification"):
                verification = callout("info", f"Verify: {step['verification']}")
            items.append(
                f'<div class="step">'
                f'<div class="step-number">{i}</div>'
                f'<div class="step-header"><h3>{esc(step.get("title", ""))} {status_chip}</h3></div>'
                f'{files}'
                f'{description}'
                f'{verification}'
                f'</div>'
            )
        label = "Plan Steps" if stage == "plan" else "Execution Log"
        parts.append(section(label, "".join(items)))

    if p.get("verification"):
        v = p["verification"]
        body = md_paragraphs(v.get("description", "")) if isinstance(v, dict) else md_paragraphs(v)
        if isinstance(v, dict) and v.get("steps"):
            items = "".join(f"<li>{esc_rich(s)}</li>" for s in v["steps"])
            body += f"<ol>{items}</ol>"
        if isinstance(v, dict) and v.get("command"):
            body += code_block(v["command"], "bash")
        parts.append(section("Verification", body))

    if p.get("risks"):
        items = "".join(f"<li>{esc_rich(r)}</li>" for r in p["risks"])
        parts.append(section("Risks", f"<ul>{items}</ul>"))

    for c in p.get("callouts", []):
        parts.append(callout(c.get("type", "info"), c.get("text", "")))

    title = p.get("title") or p.get("issue_ref") or "Change Plan"
    label = "Plan (Awaiting Approval)" if stage == "plan" else "Execution Log"
    return (label, accent, "".join(parts)), title, ""


def render_explain(p: dict) -> tuple:
    chips = []
    if p.get("question"):
        chips.append(chip("question", "chip-mono"))
    if p.get("files_touched"):
        chips.append(chip(f'{len(p["files_touched"])} files'))

    parts = []
    if chips:
        parts.append(f'<div class="chip-row">{"".join(chips)}</div>')

    if p.get("question"):
        parts.append(
            f'<div class="callout info">'
            f'<span><strong>Question:</strong> {esc_rich(p["question"])}</span></div>'
        )

    if p.get("summary"):
        parts.append(section("Short Answer", md_paragraphs(p["summary"])))

    if p.get("mermaid"):
        parts.append(section(
            "Diagram",
            f'<div class="mermaid">{esc(p["mermaid"])}</div>'
        ))

    for sec in p.get("sections", []):
        heading = sec.get("heading", "")
        body_parts = []
        if sec.get("markdown"):
            body_parts.append(md_paragraphs(sec["markdown"]))
        for c in sec.get("citations", []):
            file_path = c.get("file", "")
            line = c.get("line", "")
            loc = f"{file_path}:{line}" if line else file_path
            note = c.get("note", "")
            body_parts.append(
                f'<div class="citation">'
                f'<span class="file-badge">{esc(loc)}</span>'
                f'{f"<span> — {esc_rich(note)}</span>" if note else ""}'
                f'</div>'
            )
        if sec.get("code"):
            body_parts.append(code_block(sec["code"], sec.get("lang", "")))
        parts.append(section(heading, "".join(body_parts)))

    if p.get("files_touched"):
        badges = "".join(file_badge(f) for f in p["files_touched"])
        parts.append(section("Files Referenced", f'<div class="file-list">{badges}</div>'))

    for c in p.get("callouts", []):
        parts.append(callout(c.get("type", "info"), c.get("text", "")))

    title = p.get("title") or "Codebase Explanation"
    return ("Explanation", "accent", "".join(parts)), title, ""


KIND_DISPATCH = {
    "triage": render_triage,
    "review": render_review,
    "bugfix": render_bugfix,
    "plan": render_plan,
    "explain": render_explain,
}
