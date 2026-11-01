import '../../models/git_merge_mode.dart';
import '../../models/git_merge_result.dart';
import '../refs/git_unknown_revision_exception.dart';
import '../worktree/git_local_changes_overwritten_exception.dart';
import 'git_merge.dart';
import 'git_merge_not_fast_forward_exception.dart';
import 'git_no_merge_in_progress_exception.dart';
import 'git_unrelated_histories_exception.dart';

/// Merging into a work tree: fast-forwards, merge commits, conflicted merges
/// and the in-progress merge state with its abort.
///
/// It refines [GitMerge] with the operations that need a work tree, so a bare
/// repository only offers the in-memory [GitMerge.mergeTree]. This is the
/// type of `merge` on a [GitWorkingRepository].
///
/// Failures follow the domain's rules. A conflicted merge is a result
/// ([GitMergeConflicts]), never an exception. The refusals a caller can treat
/// are named:
///
/// - [GitMergeNotFastForwardException] for a fast-forward-only merge that
///   cannot fast-forward;
/// - [GitUnknownRevisionException] for a [merge] revision that names nothing;
/// - [GitLocalChangesOverwrittenException] for a merge git refuses because it
///   would overwrite local changes or untracked files;
/// - [GitUnrelatedHistoriesException] for histories without a common
///   ancestor merged without `allowUnrelatedHistories`;
/// - [GitNoMergeInProgressException] for an [abort] without a merge in
///   progress.
///
/// ```dart
/// final GitWorkingMerge merge = working.merge;
/// final GitMergeResult result = await merge.merge('topic');
/// if (result is GitMergeConflicts) {
///   print(result.conflictingFiles);
/// }
/// if (await merge.isMerging()) {
///   await merge.abort();
/// }
/// ```
/// {@category Getting started}
abstract interface class GitWorkingMerge implements GitMerge {
  /// Merges [rev] into the current head.
  ///
  /// [rev] is a revision expression of the grammar documented on
  /// `GitRevisionResolver`; one that reads like an option — it starts with
  /// `-` — names no revision and is refused before any command runs.
  /// [mode] selects which merges are allowed
  /// (fast-forward or merge commit).
  /// A conflicted merge is reported as [GitMergeConflicts] with the paths
  /// left in conflict; a refusal is raised as one of the exceptions named on
  /// this class — [GitUnknownRevisionException] for a revision that names
  /// nothing, [GitLocalChangesOverwrittenException] for a work tree it would
  /// overwrite, [GitUnrelatedHistoriesException] for histories without a
  /// common ancestor.
  ///
  /// With [noCommit] the merge is staged and stopped before committing:
  /// non-fast-forward merges stay in progress (see [isMerging]) until the
  /// caller commits, or gives up through [abort]. A [message] overrides the
  /// default merge commit message. Without a message, no editor is opened.
  /// With [allowUnrelatedHistories] (git's own `--allow-unrelated-histories`)
  /// two histories without a common ancestor are merged without refusal;
  /// without the flag git refuses and [GitUnrelatedHistoriesException] is
  /// raised.
  ///
  /// With a [message] the merge levels the default commit message with it.
  Future<GitMergeResult> merge(
    String rev, {
    GitMergeMode mode = GitMergeMode.auto,
    bool noCommit = false,
    String? message,
    bool allowUnrelatedHistories = false,
  });

  /// Whether a merge is in progress, seen through `MERGE_HEAD` - true after a
  /// conflicted merge, or a merge staged by [noCommit] above, until it is
  /// committed or given up through [abort].
  Future<bool> isMerging();

  /// Gives up the current in-progress merge (`git merge --abort`): the head,
  /// index and work tree go back to the pre-merge state.
  ///
  /// Raises [GitNoMergeInProgressException] when no merge is in progress.
  Future<void> abort();
}
