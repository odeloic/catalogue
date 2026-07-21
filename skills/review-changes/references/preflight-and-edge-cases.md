# Pre-flight and edge cases

Check the fetched context against this table before reading code. Flag each match in one line, no diagnosis. If nothing matches, skip the pre-flight section of the review entirely.

| Condition | Signal | Do |
| --- | --- | --- |
| CI failing | `ci.status` is not success | Say "fix CI first". Surface it; do not diagnose or debug it here. |
| Draft PR | `is_draft` | Mark the review preliminary. Ask rather than prescribe. |
| Depends on unmerged work | `depends_on` non-empty | Review the dependency first; note that findings may shift. |
| Large PR | `size_class` is `large` / `xlarge` | State what you read closely and what you skimmed. Prioritise per `pr-size-heuristics.md`. |
| Sensitive paths | path matches `auth`, `payment`, `migration`, `security`, `iam`, `crypto`, `secret` | Read those files line by line. |
| Self-review | author is the requesting user | Continue, but ask for a second reviewer on any blocker. |
| Issue closed or duplicate | triage report says so | Surface it and ask before continuing. |
| No linked issue | `linked_issues` empty | Skip AC checks, say so in the header, focus on the code. |
| Raw diff, no PR | input was a diff file | No `ci` / `linked_issues` / `depends_on`. Skip AC unless the user names an issue ID. Build `files_changed[]` from the `+++ b/<path>` lines. |
| Diff is only generated files | every path matches the generated-file rules | At most one finding: are they in sync with their source? |
| No diff available | script returns an empty diff | Halt with a clear error. |
