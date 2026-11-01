# Errors

[GitException] represents engine failures and domain refusals and implements
[Exception]. It carries a `message`, a nullable `cause` and a `diagnostic`.
Catch a subclass to handle one refusal, or [GitException] for the common
engine error hierarchy.

Argument and value validation can throw standard Dart errors and exceptions,
including [ArgumentError], [RangeError] and [FormatException]. Underlying
process and file-system errors can also propagate without being wrapped in
[GitException]. An operation's dartdoc describes its validation rules.

## Named refusals

Each facade operation documents the exceptions it raises for the refusals a
caller can treat. Other command failures use [GitException], with no further
promise about its concrete type. Portable code catches the named domain
exceptions first and [GitException] last within that hierarchy; this does not
catch validation errors or unwrapped platform failures.

A refusal decided before git runs is still typed. A reference name that cannot
be a reference, a remote location in an unsupported form and a creation target
that already holds files are refused this way; no command failed, so they carry
no cause. A conflicted merge or a refused patch application is a result, not an
exception.

```dart
try {
  await repo.branches.delete('topic');
} on GitRefNotFoundException {
  // the branch is already gone
} on GitException catch (error) {
  print(error.diagnostic);
}
```

## Portability of refusals

Domain refusals are portable. A timeout ([GitTimeoutException]) and an engine
older than the minimum ([GitVersionException]) are refusals every backend can
report, whether or not it runs a git command. An operation the package
implements but the backend cannot run raises [GitFeatureUnavailableException].
A backend that cannot be used on the host raises [GitEngineUnavailableException];
code portable between backends catches that supertype rather than a
backend-specific subtype.

Domain exceptions derive from [GitException] through backend-independent
types. They carry the underlying failure in `cause` when one exists, and leave
it null on a backend that runs no command underneath. The process engine
raises [GitExecutableNotFoundException] when it cannot find its executable;
that subtype keeps the raw platform error in `spawnError` and leaves `cause`
null. A repository of the wrong kind raises a [GitRepositoryKindException]
subtype.

## URL masking

Command failure messages and refused remote locations mask the userinfo of
each scheme-based URL they name: `https://user:token@host/repo` reads as
`https://***@host/repo`. `diagnostic` applies this masking throughout its
cause chain. The scp-like `user@host:path` spelling has no scheme and is left
as written.

A refused remote location keeps its original spelling on
`GitUnsupportedUrlException.url`, which may contain secrets. Its `message`
and `diagnostic` mask URL userinfo, but do not redact other kinds of secrets.

## diagnostic

`diagnostic` is the complete technical text of a failure. It starts with
`message` and, when there is a `cause`, appends that failure's own text after a
blank line, stopping after sixteen failures in the chain. A command failure
appends the command, its working directory, its exit code and its full output;
a timeout cause appends the command and the output captured before the process
was stopped.

URL userinfo masking is not general secret redaction. Query parameters,
command arguments and process output can still contain tokens, headers or
other sensitive data. Apply any additional redaction needed before logging
or writing diagnostics to a file.

The format and language are not promised. Command output is not truncated by
the diagnostic formatter; a logger applies its own size limit. Code must never
read diagnostics to decide a behaviour: catch the exception type instead.
