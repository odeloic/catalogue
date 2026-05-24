# Test frameworks: running a single failing test

The detection script returns `single_test_command` as a hint with `<pattern>` placeholders. This reference fills in the details per framework.

## Vitest (Node)

```
pnpm vitest run path/to/file.test.ts
pnpm vitest run -t "name of the test"
```

- `-t` filters by test name (regex). Combine with the file path to scope tightly.
- `--reporter=verbose` makes failure output easier to read on a single test.
- Watch mode (`pnpm vitest`) is fine for the inner loop but the verification phase should use `vitest run` (no watch).

## Jest (Node)

```
pnpm jest path/to/file.test.ts
pnpm jest -t "name of the test"
```

- `--testNamePattern` is the long form of `-t`.
- For monorepos with project configs: `pnpm jest --selectProjects <name>` to avoid running unrelated packages.

## Mocha (Node)

```
pnpm mocha path/to/file.spec.js
pnpm mocha --grep "name of the test"
```

- Mocha's `--grep` is a regex against the full nested test name (`describe` + `it`).

## Ava (Node)

```
pnpm ava path/to/file.test.js
pnpm ava --match "name of the test"
```

## pytest (Python)

```
pytest path/to/test_file.py
pytest path/to/test_file.py::TestClass::test_method
pytest -k "expression"
```

- `::` selects by node id (the most precise form).
- `-k` filters by name expression (`-k "broken and not slow"`).
- `-x` to stop at the first failure; `-vv` for the full assertion diff.

## go test (Go)

```
go test ./path/to/pkg
go test -run TestName ./path/to/pkg
go test -run TestName/sub_name ./path/to/pkg   # subtests via t.Run
```

- `-run` takes a regex against the test name. `-run '^TestExact$'` to pin exactly.
- `-v` for verbose output, `-count=1` to bypass the test cache when you need a clean run.

## cargo test (Rust)

```
cargo test
cargo test test_name
cargo test --test integration_file_name
cargo test -- --exact path::to::test_name
```

- Argument before `--` filters by substring; after `--` is passed to the test binary.
- `--nocapture` shows stdout from passing tests too.

## rspec (Ruby)

```
bundle exec rspec spec/path/to/file_spec.rb
bundle exec rspec spec/path/to/file_spec.rb:42      # line number
bundle exec rspec -e "name of the example"
```

## phpunit (PHP)

```
./vendor/bin/phpunit tests/Path/To/Test.php
./vendor/bin/phpunit --filter test_method_name
```

## Pest (PHP)

```
./vendor/bin/pest tests/Path/To/Test.php
./vendor/bin/pest --filter "name of the test"
```

## exunit (Elixir)

```
mix test test/path/to/file_test.exs
mix test test/path/to/file_test.exs:42      # line number
mix test --only describe:"name"
```

## General tips

- Run the broader suite once before the fix to confirm a green baseline. A flaky main is a separate problem and the failing-test contract is unreliable until it's resolved.
- After the fix, run the single test, then the file's tests, then the broader subset, then the full suite. Catch regressions before commit.
- Tests that depend on time, randomness, network, or filesystem state need explicit isolation (faketime, seeded RNG, recorded fixtures, tmpdir).
