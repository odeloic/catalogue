# Writing the review

The reader is skimming to decide what to do next. Give them that and stop.

## Finding anatomy

| Part | When | Rule |
| --- | --- | --- |
| ID | always | `<n>`, or `<group-prefix>-<n>` in a multi-project diff. Numbered worst-first. |
| Severity | always | `severity-levels.md` |
| `file:line` | always | must be in `files_changed[]` |
| What's wrong | always | 1–2 sentences, 40 words max |
| Diff | always | the hunk from the PR this is about, unedited |
| Draft comment | always | 60 words max, ends with a question |
| Proposed fix | `show-fix` | a diff, never prose |
| Reproduction | `reproduce` | output you actually captured |

**The diff is the anchor.** Show the changed lines the finding is about, straight from the PR. If you cannot point at a changed line, it is not a finding on this PR — drop it.

## Draft comment

Written as you, speaking to the author, ready to paste with no edits. Name what breaks, then ask for what you want. No opener ("Nice work, but…"), no summary of the code they wrote, no instruction voice. Two or three sentences.

Good:

> `fetch` resolves on 4xx, so the `.catch` fallback never runs — a 404 body gets parsed and rendered instead. I hit this on every Antrag with the current dump. Can you check `res.ok` before reading the body?

Bad:

> It is worth noting that the current implementation of the icon fetching logic does not perform any validation of the HTTP response status prior to consuming the response body, which could potentially lead to unexpected behaviour in certain edge cases. It might be beneficial to consider adding appropriate error handling.

## Prose rules

- Lead with the problem. The first sentence names what breaks.
- One idea per sentence. Cut any clause that does not change what the reader does.
- Plain words: *sends* not *dispatches*, *breaks* not *is non-functional*, *before* not *prior to*, *use* not *leverage*, *about* not *regarding*, *so* not *thereby*, *lets you* not *facilitates*.
- Do not describe code the diff already shows.
- Do not stack hedges. "might possibly potentially" → "might".
- Cut fillers: *It is worth noting that*, *As mentioned above*, *In order to*, *At the end of the day*, *This is a good opportunity to*, *Please be aware that*.
- Say "I could not check X" rather than writing around it.
- No emojis anywhere.

Budgets: finding prose 40 words, draft comment 60 words, summary 3 sentences, recommendation reason 1 line. Over budget means the diff should be carrying it.

## Document outline

`.claude/reviews/<pr-id>.md`, in this order:

1. **Summary** — what the PR does. Three sentences max.
2. **Recommendation** — the call plus one line of reason.
3. **Pre-flight** — only if something is flagged.
4. **Acceptance criteria** — table: criterion, status, evidence. Or "no linked issue".
5. **Findings** — worst-first, each with its diff and draft comment. One section per sub-project only in a multi-project diff.
6. **Open questions** — anything the diff left ambiguous.
7. **Coverage** — for large PRs: read closely vs. skimmed.
