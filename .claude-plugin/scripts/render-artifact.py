#!/usr/bin/env python3
"""Thin shim → the `artifact` package.

Kept at this path so existing skill invocations keep working unchanged:

    python3 <plugin-root>/.claude-plugin/scripts/render-artifact.py <<'ARTIFACT_EOF'
    {"kind": "triage|review|bugfix|plan|explain", "payload": {...}}
    ARTIFACT_EOF

All artifact markup and CSS live in ./artifact/ — change the look there once and
every catalogue skill's output changes. Pure stdlib: no virtualenv, no deps.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from artifact.__main__ import main  # noqa: E402

if __name__ == "__main__":
    main()
