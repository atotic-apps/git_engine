import '../../models/git_oid.dart';

/// Interprets git revision expressions (`HEAD~2`, `main^{tree}`…).
///
/// This is a capability contract: a backend implements it only when it can
/// honour every operation.
///
/// Every backend accepts at least this grammar; a backend may accept more, but
/// portable code uses only this subset:
///
/// - an object name: 40 or 64 hexadecimal characters (a complete name), or an
///   unambiguous abbreviation of at least 4 hexadecimal characters;
/// - a reference name: a complete `refs/...` name, or a short name resolved in
///   this order: `<name>` itself when it exists under `.git` (`HEAD`…),
///   `refs/<name>`, `refs/tags/<name>`, `refs/heads/<name>`,
///   `refs/remotes/<name>`, `refs/remotes/<name>/HEAD`, so a tag wins over
///   a branch of the same name;
/// - `HEAD`;
/// - the chainable suffixes `~`, `~<n>`, `^` and `^<n>`;
/// - the peels `<rev>^{commit}`, `<rev>^{tree}`, `<rev>^{blob}`,
///   `<rev>^{tag}` and `<rev>^{}`;
/// - `<rev>:<path>`, the object at that path in `<rev>`'s tree;
/// - `<branch>@{upstream}`, `<branch>@{u}`, and `@{upstream}` / `@{u}` alone
///   for the current branch.
///
/// Nothing of the grammar names a revision that starts with the `-` marker:
/// git would read such an argument as one of its own options, so it is not a
/// revision expression at all. `resolveRevision` returns null for one, and
/// the operations that resolve a revision and raise on a missing one refuse
/// with `GitUnknownRevisionException` before any command runs.
///
/// The process backend additionally accepts every revision syntax git accepts;
/// another backend does not have to.
/// {@category Getting started}
/// {@category Compatibility}
abstract interface class GitRevisionResolver {
  /// Resolves [expression] to an object name.
  ///
  /// [expression] is a revision expression of the grammar documented on
  /// [GitRevisionResolver]. Returns null when it names nothing — an unknown
  /// name, an unborn `HEAD`, a path that exists in the work tree but is not a
  /// revision. A name is never resolved through a file of the work tree: only
  /// revisions are.
  ///
  /// Like git itself, a full object name is accepted syntactically even when
  /// no such object exists in the repository.
  Future<GitOid?> resolveRevision(String expression);
}
