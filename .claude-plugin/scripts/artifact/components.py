"""HTML-string builders for catalogue artifacts.

Leaf components with no cross-module dependencies. Markup lives here; styling
lives in styles.css. Change a component's markup here and every kind that uses
it follows.
"""

from __future__ import annotations

import re


def esc(text) -> str:
    if text is None:
        return ""
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def esc_rich(text) -> str:
    """Escape HTML but render `code` spans, **bold**, and bare URLs."""
    if text is None:
        return ""
    s = esc(text)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(
        r"(https?://[^\s<]+)",
        r'<a href="\1" target="_blank" rel="noopener">\1</a>',
        s,
    )
    return s


def md_paragraphs(text) -> str:
    """Tiny markdown: split on blank lines, render `code`, **bold**, links per paragraph."""
    if not text:
        return ""
    blocks = [b.strip() for b in re.split(r"\n\s*\n", str(text)) if b.strip()]
    return "\n".join(f"<p>{esc_rich(b)}</p>" for b in blocks)


def callout(ctype: str, text: str) -> str:
    return (
        f'<div class="callout {esc(ctype)}">'
        f'<span>{esc_rich(text)}</span></div>'
    )


def file_badge(path) -> str:
    return f'<span class="file-badge">{esc(path)}</span>' if path else ""


def chip(text: str, variant: str = "") -> str:
    cls = f"chip {variant}".strip()
    return f'<span class="{cls}">{esc(text)}</span>'


def diff_block(diff_lines, lang: str = "") -> str:
    if not diff_lines:
        return ""
    out = []
    for dl in diff_lines:
        t = dl.get("type", "context")
        prefix = {"add": "+ ", "remove": "- ", "context": "  "}.get(t, "  ")
        out.append(f'<span class="line-{t}">{esc(prefix + dl.get("text", ""))}</span>')
    lang_label = f'<span class="lang-label">{esc(lang)}</span>' if lang else ""
    return f'<pre>{lang_label}<code>{"".join(out)}</code></pre>'


def code_block(code: str, lang: str = "") -> str:
    if not code:
        return ""
    lang_label = f'<span class="lang-label">{esc(lang)}</span>' if lang else ""
    return f'<pre>{lang_label}<code>{esc(code)}</code></pre>'


def section(title: str, content: str) -> str:
    return (
        f'<div class="section">'
        f'<h2>{esc(title)}</h2>'
        f'{content}'
        f'</div>'
    )
