import '../../core/errors/git_feature_unavailable_exception.dart';
import '../../models/git_merge_tree_result.dart';
import '../../models/git_oid.dart';
import 'git_unrelated_histories_exception.dart';

/// Merging that needs neither an index nor a work tree: in-memory merges.
///
/// Every repository carries it, bare repositories included. The operations
/// that merge into a work tree (fast-forwards, merge commits, conflicts,
/// abort) live on [GitWorkingMerge], the refinement a working repository
/// exposes.
///
/// Every command runs inside the owning repository's context, so a derived
/// view (an alternate index, extra environment variables) applies here too.
/// {@category Getting started}
abstract interface class GitMerge {
  /// Computes what merging [theirs] into [ours] would produce, writing the
  /// merged tree as an object but never touching the index or the work tree
  /// (`git merge-tree`).
  ///
  /// Conflicting paths come back in [GitMergeTreeResult.conflictingFiles] and
  /// carry conflict markers in [GitMergeTreeResult.tree]. Both arguments are
  /// object names of commits; resolve a revision expression first with
  /// `GitRevisionResolver.resolveRevision`. With [allowUnrelatedHistories]
  /// two histories without a common ancestor are merged without refusal;
  /// without the flag git refuses and [GitUnrelatedHistoriesException] is
  /// raised. A backend incapable of computing this merge raises
  /// [GitFeatureUnavailableException].
  Future<GitMergeTreeResult> mergeTree(
    GitOid ours,
    GitOid theirs, {
    bool allowUnrelatedHistories = false,
  });
}
