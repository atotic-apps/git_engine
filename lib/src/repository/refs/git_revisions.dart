import '../../models/git_oid.dart';
import 'git_revision_resolver.dart';

/// Revision expressions of one repository.
///
/// ```dart
/// final GitOid? parent = await repo.revisions.resolveRevision('HEAD~2');
/// final String full = await repo.revisions.symbolicFullName('HEAD');
/// final String short =
///     await repo.revisions.symbolicFullName('@{upstream}', abbreviated: true);
/// ```
/// {@category Getting started}
abstract interface class GitRevisions implements GitRevisionResolver {
  /// Resolves [expression] to an object name; see
  /// [GitRevisionResolver.resolveRevision].
  @override
  Future<GitOid?> resolveRevision(String expression);

  /// Full name of the symbolic ref [rev] points at, e.g.
  /// `refs/remotes/origin/main` for `@{upstream}`.
  ///
  /// [rev] is a revision expression of the grammar documented on
  /// `GitRevisionResolver`; one that reads like an option — it starts with
  /// `-` — names no revision and is refused as below. With [abbreviated] the
  /// name is shortened the way git does (`origin/main`). A revision that
  /// resolves but is not a symbolic ref — a detached `HEAD` — is reported as
  /// itself (`HEAD`). Raises [GitUnknownRevisionException] when [rev] does
  /// not resolve, including an `@{upstream}` that was never set.
  Future<String> symbolicFullName(String rev, {bool abbreviated = false});
}
