# sample-repo

Fixture for `explain-codebase` tests. Two keywords matter:

- `session` — defined in `src/auth/session.ts`, referenced from `src/auth/auth.ts` and `src/api/login.ts`.
- `auth` — defined in `src/auth/auth.ts`, referenced from `src/api/login.ts` and `src/api/middleware.ts`.

Adding files here will likely break the test assertions. Adjust deliberately.
