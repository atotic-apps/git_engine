import 'git_oid.dart';

/// Outcome of a merge, as one of the typed variants.
///
/// A conflicted merge is a result — the merge did happen and its conflicts
/// must be resolved by the caller — it is never raised as an exception.
/// {@category Getting started}
sealed class GitMergeResult {
  const GitMergeResult();
}

/// The merged history was already part of the current head; nothing moved.
/// {@category Getting started}
class GitMergeUpToDate extends GitMergeResult {
  /// Creates the result of a merge that had nothing to do.
  const GitMergeUpToDate();

  @override
  String toString() => 'up to date';
}

/// Fast-forward: the current head moved forward onto the merged revision
/// without a new commit.
/// {@category Getting started}
class GitMergeFastForward extends GitMergeResult {
  /// Object name of the head after the fast-forward.
  final GitOid newHead;

  /// Creates the fast-forward result pointing at [newHead].
  const GitMergeFastForward({required this.newHead});

  @override
  String toString() => 'fast-forward to $newHead';
}

/// A merge commit was created to fold the merged history in.
/// {@category Getting started}
class GitMergeCommit extends GitMergeResult {
  /// Object name of the merge commit; its first parent is the head the merge
  /// started from.
  final GitOid commit;

  /// Creates the result naming [commit] as the merge commit.
  const GitMergeCommit({required this.commit});

  @override
  String toString() => 'merge commit $commit';
}

/// A clean, non-fast-forward merge was staged but stopped before committing
/// (`noCommit`): the index holds the merged state and `MERGE_HEAD` marks the
/// merge as in progress, so the caller can commit it — or give it up through
/// `abort()`.
/// {@category Getting started}
class GitMergeStopped extends GitMergeResult {
  /// Creates the result of a merge staged but stopped before committing.
  const GitMergeStopped();

  @override
  String toString() => 'merge staged, stopped before committing';
}

/// The merge could not be done automatically: the paths it lists were left
/// with conflicts in the index and the work tree, and the merge stays
/// in progress (`MERGE_HEAD`) until the caller resolves them or gives it up
/// through [GitWorkingMerge.abort].
/// {@category Getting started}
class GitMergeConflicts extends GitMergeResult {
  /// Paths left in conflict, as git wrote them.
  final List<String> conflictingFiles;

  /// Creates the result listing [conflictingFiles].
  const GitMergeConflicts({required this.conflictingFiles});

  @override
  String toString() => 'conflicts in ${conflictingFiles.join(', ')}';
}
