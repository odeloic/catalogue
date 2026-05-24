---
name: explain-codebase
description: Investigate and explain how something works in the current codebase. Use when the user asks "how does X work here", "where is Y", "explain Z", "trace the flow from A to B", "what happens when [event]", or "show me visually how X works". Default output is a markdown explanation with file:line citations. If the user asks for a visualization (words like "visually", "diagram", "show me", "draw"), produce an HTML artifact with a mermaid diagram appropriate to the question shape. Read-only — never modifies code.
when_to_use: When the user asks how/where/why a piece of code works in the current repo, asks to trace a flow, or asks for a visual explanation of a code path or lifecycle.
---

# explain-codebase

Read-only investigation skill. Parse the question, search the repo, read the densest hits, and answer with `file:line` citations. Optionally render a single-file mermaid HTML artifact.

## 1. Parse the question

Extract two things:

- **Concrete terms** — symbol names, file hints, feature names to search for. If nothing concrete is extractable, ask the user to narrow before investigating. Don't fish.
- **Question shape** — one of:
  - *lookup* — "where is X", "what does Y do" — one-shot answer with a citation.
  - *explanation* — "how does X work", "why does Y happen" — narrative answer.
  - *flow / trace* — "what happens when X", "trace from A to B" — sequential answer.
  - *lifecycle* — "the lifecycle of X" — state-based answer.
  - *comparison* — "what's the difference between X and Y" — side-by-side answer.

See `references/question-shapes.md` for signal phrases and expected output structure for each.

## 2. Detect visual intent

Visual is requested when:
- The user says "visually", "diagram", "draw", "show me", "graph", "chart".
- The user passes a `--visual` flag.
- The shape is *flow* or *lifecycle* AND the user signaled they want depth.

If unsure, default to markdown and offer the diagram at the end ("Want a diagram of this?").

## 3. Investigate

Call `scripts/investigate.sh <keyword> [keyword...]`. Returns ranked search hits as JSON. See `references/search-strategies.md` for keyword derivation.

The agent then:
- Reads top hits with line ranges, not whole files.
- For *flow* / *lifecycle*: follows references one or two hops — entry point → key transformations → exit.
- For *lookup* / *explanation*: focuses on the densest cluster of hits.
- Verifies any file before citing it (stale references happen).

**Budget**: 5-10 file reads for lookup, 10-20 for flow / explanation. If the budget is exceeded without a clear answer, halt and report what was searched.

If `total_hits` is 0, use the `suggestions[]` returned by the script to retry **once**, then report failure honestly.

## 4. Compose the answer

**Markdown (default)** — write to `.claude/explanations/<topic-slug>.md`:
- Direct answer first (one paragraph).
- Detail with `file:path/to/file.ts:42` citations interleaved. See `references/citation-style.md`.
- Flow questions: numbered steps, each with the file:line that handles it.
- Comparison: side-by-side structure.
- End with a **Key files** section listing 3-5 most relevant files.

**Visual (if requested)** — also write `.claude/explanations/<topic-slug>.html`:
- Pick the diagram type from the question shape — see `references/diagram-types.md`:
  - *flow / trace* → `sequenceDiagram` or `flowchart`
  - *lifecycle* → `stateDiagram-v2`
  - *hierarchy / structure* → `classDiagram` or `flowchart TB`
  - *data model* → `erDiagram`
  - *dependency / call graph* → `flowchart LR`
- Write the mermaid source to a temp `.mmd` file, then run `scripts/render-mermaid.sh <file> --title "..." --explanation "..."` to wrap it in the HTML template.
- If the diagram type doesn't fit the question, fall back to a flowchart or a markdown table; don't force-fit.

## 5. Surface

Print a condensed summary in chat with the key `file:line` citations inline and the paths to the markdown / HTML artifacts.

## Edge cases

- **Vague question** — ask to narrow; don't burn budget.
- **No matches** — retry once with `suggestions[]`, then report failure.
- **Topic spans many files** ("how does the whole API work") — surface the breadth, ask whether to zoom into a slice or give an architectural overview with pointers.
- **Monorepo** — if `top_directories` hits span multiple packages, ask which one.
- **Generated code hits** (e.g., `gen/`, `_pb2.py`) — flag and ask whether to include.
- **Runtime-only fact** (e.g., "what's in env in production") — surface the limitation; this skill is static-analysis only.
- **Mermaid syntax error** — surface the raw source for manual fix.

## Hand-off

When the answer warrants a richer treatment than a markdown explanation + simple diagram, hand off:
- `/claude-ode:guide` — for a visual learning guide with mental models and flow diagrams.
- `/claude-ode:showme` — for a step-by-step implementation tutorial with diff-highlighted code.

This skill stays narrow on purpose. The simple mermaid path here covers the common case.

## Testing

`scripts/investigate.sh` honors `INVESTIGATE_FIXTURE_ROOT=<dir>` to search a fixture tree instead of the cwd. Use this for unit tests of ranking and suggestion behavior. See `tests/test-investigate.sh`.
