import '../models/git_oid.dart';
import 'git_file_repository.dart';
import 'git_indexed_repository.dart';
import 'merge/git_working_merge.dart';
import 'patches/git_working_patches.dart';
import 'worktree/git_worktree.dart';

/// A [GitFileRepository] with a work tree and an active index view.
///
/// It exposes the operations that read or write working-tree files, and it is
/// the only repository type with a work tree.
/// {@category Getting started}
abstract interface class GitWorkingRepository
    implements GitIndexedRepository, GitFileRepository {
  /// Absolute path of the work tree root. It is never null: a repository
  /// without a work tree is not a [GitWorkingRepository].
  Future<String> toplevel();

  /// Work tree and index: status, staging, reset, cleaning, checkout and
  /// commits, all through this repository.
  GitWorktree get worktree;

  /// Comparisons against the work tree, and applying a patch to the work
  /// tree only, all through this repository.
  @override
  GitWorkingPatches get patches;

  /// Merging into the work tree: fast-forwards, merge commits, conflicted
  /// merges, the in-progress merge state with its abort, plus the in-memory
  /// merges of [GitMerge].
  @override
  GitWorkingMerge get merge;

  /// Runs [action] on a working view whose active index is a temporary one,
  /// empty or initialized from [fromTree], and returns its result.
  ///
  /// The view is still a working repository, so the work tree remains usable;
  /// the temporary index is deleted afterwards, even when [action] throws.
  /// Every command of that view works on the temporary index, so
  /// `worktree.addAll`, `worktree.intentToAdd`, the patch comparisons and
  /// `index.writeTree` build a tree without touching the repository's own
  /// index or `HEAD`.
  @override
  Future<T> withTemporaryIndex<T>(
    Future<T> Function(GitWorkingRepository repository) action, {
    GitOid? fromTree,
  });
}
