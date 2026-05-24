# Question shapes

Five shapes. Pick the closest at the start of the investigation — the shape decides depth, output structure, and diagram type.

## Lookup

**Signal phrases**: "where is", "what file has", "show me the definition of", "which function does X".

**Output**: one paragraph + a single `file:line` citation. No headings, no sections.

**Investigation depth**: 1-3 file reads. Stop as soon as the definition site is confirmed.

**Diagram (if visual requested)**: usually not needed. If forced, a `flowchart LR` showing the symbol → its dependents.

## Explanation

**Signal phrases**: "how does X work", "why does Y happen", "what does Z do".

**Output**: a narrative answer, 3-6 short paragraphs. Citations interleaved at the point they're discussed. End with a **Key files** section.

**Investigation depth**: 5-10 file reads. Read the densest cluster of hits, plus one hop on any function that's central to the explanation.

**Diagram (if visual requested)**: `flowchart TB` for structure, or `classDiagram` if there's a class hierarchy worth showing.

## Flow / trace

**Signal phrases**: "what happens when", "trace from A to B", "walk me through", "the request lifecycle of X".

**Output**: numbered steps. Each step has a one-sentence description + a `file:line` citation. End with a **Key files** section.

**Investigation depth**: 10-20 file reads, following references one or two hops from the entry point.

**Diagram (if visual requested)**: `sequenceDiagram` if there are clear actors / participants. Otherwise `flowchart TB` with each step as a node.

## Lifecycle

**Signal phrases**: "the lifecycle of", "the states of", "what states can X be in", "from creation to destruction".

**Output**: a state list with transitions described. Each state and each transition gets a citation.

**Investigation depth**: 5-15 file reads. Focus on state-mutation sites and any state-machine constants/enums.

**Diagram (if visual requested)**: `stateDiagram-v2`. This is the shape where a diagram is most clearly worth it.

## Comparison

**Signal phrases**: "what's the difference between X and Y", "how is A different from B", "X vs Y".

**Output**: side-by-side. A markdown table works well: column per item, rows for purpose / location / behavior / when-used. End with a one-paragraph summary.

**Investigation depth**: 4-8 file reads per side.

**Diagram (if visual requested)**: rarely useful. If forced, two side-by-side `flowchart TB` blocks (mermaid supports `subgraph`).

## Picking the shape

If signals overlap, pick the most specific:
- A lifecycle question is also a flow question; pick lifecycle if the user mentioned "states".
- A comparison question may require two lookups; do them, then write the comparison output.
- "How does X work" with no specific symbol may be too vague — ask the user to narrow before investigating.
