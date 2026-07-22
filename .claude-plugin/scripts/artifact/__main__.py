"""CLI entry: read a JSON envelope, render HTML, write to /tmp, open in a browser.

Envelope: {"kind": "triage"|"review"|"bugfix"|"plan"|"explain", "payload": {...}}
Pure stdlib — no external dependencies, no virtualenv.
"""

from __future__ import annotations

import json
import sys
import webbrowser
from datetime import datetime
from pathlib import Path

from .page import render_page


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
    out.write_text(html, encoding="utf-8")
    print(f"Artifact: {out}")
    webbrowser.open(f"file://{out}")


if __name__ == "__main__":
    main()
