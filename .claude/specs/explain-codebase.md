# Spec: `explain-codebase` skill

## Purpose
Investigate and explain a specific fact, behavior, or flow in a codebase. Default output is a markdown explanation with `file:line` references. When the user asks for a visualization, produce an HTML artifact (single-file, mermaid-based) appropriate to the question shape.

## Skill frontmatter description (the trigger contract)
> Investigate and explain how something works in the current codebase. Use when the user asks "how does X work here", "where is Y", "explain Z", "trace the flow from A to B", "what happens when [event]", or "show me visually how X works". Default output is a markdown explanation with file:line citations. If the user asks for a visualization (words like "visually", "diagram", "show me", "draw"), produce an HTML artifact with a mermaid diagram appropriate to the question shape. Read-only — never modifies code.

## Inputs
1. A natural language question or fact to investigate (always required).
2. Optional: visual flag — explicit (`--visual`) or detected from phrasing.
3. Optional: scope hint — directory, file, or package to focus on.

## Workflow

### 1. Parse the question
Extract:
- **Concrete terms** to search for (symbol names, file hints, feature names).
- **Question shape**:
  - *Lookup* — "where is X", "what does Y do" — one-shot answer with citation.
  - *Explanation* — "how does X work", "why does Y happen" — narrative answer.
  - *Flow / trace* — "what happens when X", "trace from A to B" — sequential answer.
  - *Lifecycle* — "the lifecycle of X" — state-based answer.
  - *Comparison* — "what's the difference between X and Y" — side-by-side answer.

If the question is too vague (no concrete terms extractable), ask the user to narrow before investigating.

### 2. Detect visual intent
Visual is requested when:
- The user explicitly says "visually", "diagram", "draw", "show me", "graph", "chart".
- The user passes a `--visual` flag.
- The question shape is *flow*, *lifecycle*, or has 3+ interacting entities AND the user signaled they want depth.

If unsure, default to markdown and offer the visual at the end ("Want a diagram of this?").

### 3. Investigate
Call `investigate.sh <keywords...>`. Returns ranked search hits across the repo, respecting `.gitignore` and excluding common vendor/build directories.

The agent then:
- Reviews top hits and reads the surrounding code (use `view` with line ranges, not whole files).
- For flow/lifecycle questions, follows references one or two hops — entry point → key transformations → exit/sink.
- For lookup/explanation, focuses on the densest cluster of hits.
- Stops investigating when the answer is sufficient — don't read the whole codebase.

Investigation budget heuristic: 5-10 file reads for lookup, 10-20 for explanation/flow. If the agent exceeds the budget without a clear answer, halt and report what was searched.

### 4. Compose answer

**Markdown path (default):**
- Direct answer first (one paragraph).
- Detail with `file:path/to/file.ts:42` citations interleaved.
- For flow questions: numbered steps, each with the file:line that handles it.
- For lookup: just the citation and a one-paragraph explanation.
- For comparison: side-by-side structure.
- End with a "key files" section listing the most relevant 3-5 files.

**Visual path (if requested):**
- Pick the diagram type from question shape:
  - *Flow / trace* → mermaid `sequenceDiagram` or `flowchart`.
  - *Lifecycle* → mermaid `stateDiagram-v2`.
  - *Hierarchy / structure* → mermaid `classDiagram` or `flowchart TB`.
  - *Data model* → mermaid `erDiagram`.
  - *Dependency / call graph* → mermaid `flowchart LR`.
- Generate the mermaid source.
- Wrap in single-file HTML with mermaid.js from CDN (no build step).
- Include a brief text explanation alongside the diagram in the HTML.
- Save the HTML and surface it.

### 5. Write outputs
- Markdown: `.claude/explanations/<topic-slug>.md`.
- HTML (if visual): `.claude/explanations/<topic-slug>.html`.
- Chat output: a condensed summary with file:line references and a link to the full file(s).

## Script: `scripts/investigate.sh <keywords...>`
Single call. Takes one or more keywords. Returns ranked search results as JSON to stdout. Read-only.

Behavior:
- Uses ripgrep (`rg`) with sensible defaults: respects `.gitignore`, excludes binary files, follows symlinks off.
- Excludes common noise paths: `node_modules`, `dist`, `build`, `.next`, `vendor`, `__pycache__`, `target`, `.venv`, `coverage`.
- For each file, computes a relevance score based on hit count + symbol density (definitions weighted higher than references — `function X`, `class X`, `def X`, `const X =`).
- Groups by directory at the top level for easier scanning.

Output:
```json
{
  "keywords": ["session", "auth"],
  "total_hits": 187,
  "ranked_files": [
    {
      "path": "src/services/auth/session.ts",
      "score": 42,
      "definitions": 3,
      "references": 18,
      "match_lines": [12, 45, 67, 89, 134]
    }
  ],
  "top_directories": [
    { "path": "src/services/auth", "file_count": 4, "total_hits": 72 },
    { "path": "src/api/middleware", "file_count": 2, "total_hits": 31 }
  ],
  "exclusions_applied": ["node_modules", "dist", ".next"],
  "search_duration_ms": 124
}
```

For empty results: `{ "total_hits": 0, "ranked_files": [], "suggestions": ["try X", "try Y"] }`. The agent uses suggestions to refine and retry once before reporting failure.

## Script: `scripts/render-mermaid.sh <diagram-source-file>`
Optional helper. Takes a `.mmd` source file, wraps it in a minimal HTML template with mermaid.js from CDN, writes to stdout. The agent could also do this inline, but having it as a script keeps the HTML wrapper consistent.

HTML template (rough shape):
```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>{title}</title>
  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 1100px; margin: 2rem auto; padding: 0 1rem; }
    .explanation { margin-bottom: 2rem; line-height: 1.6; }
    .mermaid { background: #fafafa; padding: 1rem; border-radius: 8px; }
  </style>
</head>
<body>
  <h1>{title}</h1>
  <div class="explanation">{explanation_html}</div>
  <pre class="mermaid">{diagram_source}</pre>
  <script>mermaid.initialize({startOnLoad: true});</script>
</body>
</html>
```

Single file, no build step. Opens in any browser.

## Outputs
1. Markdown explanation at `.claude/explanations/<topic-slug>.md`.
2. HTML artifact at `.claude/explanations/<topic-slug>.html` (only if visual requested).
3. Chat output: a condensed summary appropriate to the question shape, with the key file:line citations inline and a link to the full artifact.

## Directory layout
```
skills/exploration/explain-codebase/
├── SKILL.md
├── scripts/
│   ├── investigate.sh
│   └── render-mermaid.sh
├── references/
│   ├── question-shapes.md              # lookup / explanation / flow / lifecycle / comparison
│   ├── search-strategies.md            # what to search for given the question shape
│   ├── citation-style.md               # file:line format, when to quote, when to summarize
│   ├── diagram-types.md                # mermaid syntax cheat sheet for each shape
│   └── html-template.html              # the HTML wrapper used by render-mermaid.sh
└── tests/
    └── fixtures/                        # sample questions + expected file references
```

## Relationship to existing tooling
Pairs naturally with the `/claude-ode:guide` and `/claude-ode:showme` skills from the original plugin. Those produce learning guides and step-by-step tutorials with rich HTML. `explain-codebase` is narrower: investigate and explain a specific fact, optionally with a simple diagram. If `explain-codebase` finds the explanation warrants the richer treatment, it can hand off to `guide` or `showme` rather than producing its own elaborate HTML. The simple mermaid path here covers the common case; the existing skills handle the elaborate cases.

## Edge cases
- **Question too vague** — ask to narrow before investigating; don't burn budget on a fishing expedition.
- **No matches found** — surface what was searched, suggest refinements, ask once. If still no hits, report failure honestly.
- **Topic spans many files** (e.g., "how does the whole API work") — surface the breadth, ask whether to zoom in to a slice or give a high-level architectural answer with file pointers.
- **Monorepo** — if `top_directories` shows hits across multiple packages, ask which package to focus on.
- **Generated/vendored code dominates results** — already excluded by `investigate.sh`, but if hits still land in suspicious paths (`gen/`, `generated/`, `_pb2.py`), flag and ask whether to include.
- **Stale references** (search hits exist but the code has been removed) — verify before citing; never cite a file that doesn't exist.
- **The fact requires runtime knowledge** (e.g., "what's in the env in production") — surface the limitation; the skill is static-analysis only.
- **Diagram type doesn't fit the question** — fall back to a flowchart or a markdown table; don't force-fit.
- **Mermaid syntax error** in generated diagram — render-mermaid.sh should validate by attempting a parse via the mermaid CLI if available; fall back to surfacing the raw source for manual fix.

## Testing approach
Fixture-based: a small sample repo with known structure under `tests/fixtures/`, plus a set of questions with expected file references. Assert that `investigate.sh` returns the expected ranked files for known keywords. For diagram generation, snapshot-test the mermaid source against known question shapes. The narrative explanation is hard to test directly — keep it to snapshot tests of the file:line citations.
