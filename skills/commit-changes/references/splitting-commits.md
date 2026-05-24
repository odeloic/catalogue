# Splitting commits

Default to one commit. Split only when keeping them together would actively hurt review, bisect, or revert.

## When to split

- **Unrelated concerns.** A bug fix in the billing module plus an unrelated rename in the email module → two commits. They have nothing to do with each other; bundling them makes either one harder to revert.
- **Mechanical + substantive.** A logic change plus a lockfile bump, a generated client refresh, or a mass-formatting pass → split. The mechanical commit is noise during code review; isolating it lets reviewers skip it.
- **Generated files.** `package-lock.json`, `pnpm-lock.yaml`, `dist/`, OpenAPI-generated clients, Prisma migrations — separate commit, message says it's generated. Lets `git blame` skip past them.
- **Migration + code that uses it.** Schema migration is one commit, the code change that depends on the new column is the next. Keeps the deploy story straight: migrate first, then deploy code.
- **Upstream report defined separate steps.** If a `fix-bug` or `ship-change` report listed steps as independent — honour that.
- **User asked.** `--split` overrides the default.

## When to keep single (the default)

- Test files alongside the source they exercise — same commit.
- A refactor and the feature it enables, if the refactor only makes sense in service of the feature.
- Small docs touch-ups co-located with the code they document.
- Anything you'd describe in one sentence.

When in doubt, default to single. Surface the decision (and the rationale) before staging so the user can override.

## Clustering files

When splitting, group by concern:

1. **Tests with source.** `foo.ts` + `foo.test.ts` → one cluster.
2. **Generated files alone.** Lockfiles, `dist/`, generated SDKs, snapshot files — their own commit.
3. **Docs.** Co-located README/JSDoc touch-ups go with the code. A standalone docs update is its own commit.
4. **Migrations with consumers.** Schema migration plus the queries / models that use the new schema.
5. **Config alone.** Repo-wide config touches (`tsconfig`, `.eslintrc`, CI yaml) are usually their own commit unless they exist *only* to support the change in this PR.

## Sanity check before staging

If you end up with **3+ clusters**, surface the plan and ask before staging. Three commits is usually a sign the change is broader than it should be.

If you end up with **5+ clusters**, the change is probably too large for one PR — flag it.
