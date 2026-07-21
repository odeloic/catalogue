# Sub-project grouping

Only for a diff that spans more than one project. A single-project diff has no groups — drop the grouping entirely, never mention it, and number findings `1`, `2`, `3`.

## Resolving the owner of a path

1. Walk up from the file and take the first directory holding a project manifest — `package.json`, `pubspec.yaml`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `pom.xml`, `build.gradle`, `composer.json`, `Gemfile`, `*.csproj`.
2. No manifest anywhere above it — use the first path segment.
3. Files at the repo root (CI config, lockfiles, docs) — group them as `repo root`, listed last.

## Naming and ordering

Name each group by its directory (`web/bereich-a`, `backend/API`), not by framework.

Give each group a short prefix derived from the path so findings get a referenceable ID:

| Group | Prefix | Finding IDs |
| --- | --- | --- |
| `backend/API` | `BE` | `BE-1`, `BE-2` |
| `web/bereich-a` | `BA` | `BA-1`, `BA-2` |
| `repo root` | `RR` | `RR-1` |

Order groups by their worst severity, then by file count. `repo root` is pinned last whatever its severity. Within a group, number findings worst-first.

## Generated files

Paths under `__generated__/`, or matching `*.generated.*`, `*.g.dart`, `*.pb.go`, exported `schema.graphql`, and lockfiles: do not read line by line. Check only that they match their source and were produced by the project's own codegen command. At most one finding for all of them, placed in the group that owns them.

## Cross-project findings

A cross-project finding obeys the scope guard like any other: it anchors to a **changed line**, and it lives in the group that owns that line.

Anchor on the change that *introduced* the mismatch, not on the project that suffers it — the suffering project often has no changed line to point at. Name the project that breaks in the first sentence.

> `web/storefront` now sends `discountCode`, but `services/billing` still reads `req.CouponCode`, so every coupon is silently ignored.

Anchored on the rename in `web/storefront/src/checkout/submit.ts`, filed under `web/storefront`, naming `services/billing` first.

When both sides changed and either could be the fix, file one finding per side and cross-reference them by ID.
