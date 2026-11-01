# Contributing

## Checks

Run every check from the package root before sending a change:

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test --run-skipped
dart run tool/check_without_git.dart
dart run tool/check_examples.dart
```

`dart test` skips the tests tagged `git`, and `--run-skipped` runs them where
git is installed. `check_without_git` runs the machine-independent suites with
a restricted `PATH`, and `check_examples` runs the local examples.

Before publishing, also run:

```sh
dart doc --dry-run
dart pub publish --dry-run
```

## Documentation rule

One fact lives in one place:

- an operation belongs in its dartdoc;
- a cross-cutting concept belongs in `doc/`;
- executable code belongs in `example/`;
- the home page belongs in `README.md`.

Do not repeat an operation's contract in a guide, or a guide's explanation in
the README. Link to the place that owns the fact.
