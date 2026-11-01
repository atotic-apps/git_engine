import '../../models/git_oid.dart';

/// Walks the commit graph of one repository.
///
/// This is a capability contract: a backend implements it only when it can
/// honour every operation.
/// {@category Getting started}
/// {@category Compatibility}
abstract interface class GitHistoryReader {
  /// Whether [ancestor] is an ancestor of [descendant].
  ///
  /// A commit is its own ancestor. Throws a `GitException` when either
  /// object is not a commit.
  Future<bool> isAncestor(GitOid ancestor, GitOid descendant);

  /// Best common ancestor of [first] and [second], or null when they share
  /// none — two unrelated root commits, for instance.
  Future<GitOid?> mergeBase(GitOid first, GitOid second);
}
