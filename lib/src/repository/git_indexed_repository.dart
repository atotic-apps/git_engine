import 'git_repository.dart';
import 'index/git_index.dart';
import 'patches/git_indexed_patches.dart';

/// A [GitRepository] with an active index view.
///
/// It is the level for operations that need an index — the repository's own,
/// or an explicitly supplied one — without needing a work tree. An indexed
/// view derived from a bare repository is an indexed repository and no longer
/// carries the bare type.
///
/// Its [patches] refines the tree-to-tree facade with tree-to-index
/// comparisons and index-only patch application.
/// {@category Getting started}
abstract interface class GitIndexedRepository implements GitRepository {
  /// The active index: tree writing, unmerged entries and index removal, all
  /// through this repository. On an alternate index view, every operation
  /// works on that index and never on the repository's own index.
  GitIndex get index;

  /// Comparisons against the index, and applying a patch to the index only,
  /// all through this repository.
  @override
  GitIndexedPatches get patches;
}
