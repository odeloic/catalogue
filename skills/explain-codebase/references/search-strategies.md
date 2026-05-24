# Search strategies

How to derive keywords for `investigate.sh` and what to do with the results.

## Deriving keywords from a question

Pull from the question, in order of preference:

1. **Quoted strings** — the user gave you the exact identifier. Use it verbatim.
2. **CamelCase / snake_case identifiers** that look like code symbols. Pass them as-is.
3. **Domain nouns** mentioned with weight ("session", "auth", "checkout"). These are usually the right starting point.
4. **Verbs that imply a flow** ("login", "submit", "render"). Search the verb; reading the hits will surface the canonical noun.

Pass 2-4 keywords at most on the first pass. Fewer keywords = cleaner ranking. You can always do a second pass.

## When to do a second pass

After the first pass, read the top 2-3 ranked files. If they reveal a more specific symbol or feature name, run `investigate.sh` again with that term. Common triggers:

- The first pass surfaced a wrapper function but the real logic is in a class it instantiates.
- A barrel/index file ranked #1 just because it re-exports everything — re-search for the actual symbol.
- The keyword is too generic ("config", "handler") and hits are spread across the whole repo — pick the noun the user actually cares about.

Two passes is the budget. If a third is needed, the question is probably under-specified — ask the user to narrow.

## Empty result handling

If `total_hits == 0`, the script returns a `suggestions[]` with 2-3 keyword variations (singular/plural, case style toggles). Try **one** of those once. If still empty, report failure honestly with what was searched.

Common reasons for zero hits:
- Misspelling — check.
- The feature is named differently in code than in conversation (e.g., user says "login", code calls it "authenticate").
- The feature lives in a vendored package — re-run with the vendor exclusion lifted (but that's a manual `rg` call, not this script).

## Monorepo / multi-package

If `top_directories` shows hits spread across 3+ top-level dirs of roughly equal weight, the question may span packages. Surface the breakdown to the user and ask which package to focus on before reading deeply.

If one directory dominates (e.g., 70%+ of hits), proceed there and mention the secondary directories at the end.

## Stale references

Before citing a `file:line`, verify the file exists. The search corpus reflects whatever the working tree currently has, so this is rare — but if you find a citation in a doc/comment that points elsewhere, double-check before quoting.

## Generated code

`investigate.sh` already excludes `node_modules`, `dist`, `build`, `.next`, `vendor`, `__pycache__`, `target`, `.venv`, `coverage`. If hits still land in suspicious paths (`gen/`, `generated/`, `_pb2.py`, `.pb.go`), flag them and ask the user whether to include before treating them as authoritative.

## Citing what you searched

When you report results — successful or not — name the keywords you tried. The user can correct your terminology faster than they can correct your search algorithm.
