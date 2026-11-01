import '../../models/git_oid.dart';
import '../../models/git_unmerged_entry.dart';

/// Index of one repository: tree writing, unmerged entries and index removal.
///
/// Every command runs inside the owning repository's context, so a
/// repository view bound to an alternate index file applies here too:
/// [writeTree], [readTree], [unmergedEntries] and [remove] then work on that
/// index instead of `.git/index`.
///
/// The operations mirror git's index commands ([writeTree] writes the tree of
/// the index, [readTree] loads a tree into it, [unmergedEntries] lists its
/// unmerged entries, [remove] removes paths from it); none of them updates a
/// ref or the work tree. Every failure is a `GitException`.
///
/// ```dart
/// final GitOid tree = await indexed.index.writeTree();
/// await indexed.index.readTree(tree);
/// final List<GitUnmergedEntry> conflicts =
///     await indexed.index.unmergedEntries();
/// await indexed.index.remove(<String>['notes.txt']);
/// await indexed.index.remove(<String>['generated'], recursive: true);
/// ```
/// {@category Getting started}
abstract interface class GitIndex {
  /// Writes the tree of the current index and returns its object name.
  ///
  /// Uses the index selected by the repository context, so a view bound to an
  /// alternate index file writes the tree of that index and leaves
  /// `.git/index` untouched.
  Future<GitOid> writeTree();

  /// Replaces the content of the index with [tree], without touching the work
  /// tree or a ref.
  ///
  /// [tree] must name an existing tree object: an unknown object, a blob and a
  /// commit are refused and leave the index unchanged. Uses the index selected
  /// by the repository context, so a view bound to an alternate index file
  /// loads that index and leaves `.git/index` untouched.
  Future<void> readTree(GitOid tree);

  /// Entries left unmerged in the index, one per stage.
  ///
  /// A conflicted path usually yields three entries (stages 1, 2 and 3) with
  /// the same path. An index without conflicts yields an empty list.
  Future<List<GitUnmergedEntry>> unmergedEntries();

  /// Removes [paths] from the index without touching the work tree, leaving
  /// their files in place as untracked; it is `git rm --cached`.
  ///
  /// [paths] are literal paths relative to the repository root: a directory
  /// covers its content and `.` covers the whole repository. No glob (`*`,
  /// `?`, `[...]`) and no magic `:(...)` syntax is interpreted. Missing paths
  /// are ignored. With [recursive], moved directories are removed from the
  /// index as a whole. No path is a no-op.
  Future<void> remove(List<String> paths, {bool recursive = false});
}
