import '../models/git_oid.dart';
import 'branches/git_branches.dart';
import 'config/git_config.dart';
import 'git_indexed_repository.dart';
import 'git_repository_writer.dart';
import 'history/git_history.dart';
import 'merge/git_merge.dart';
import 'objects/git_objects.dart';
import 'patches/git_patches.dart';
import 'refs/git_ref_transaction.dart';
import 'refs/git_refs.dart';
import 'refs/git_revisions.dart';
import 'remotes/git_remotes.dart';
import 'tags/git_tags.dart';

/// Facade over one git repository, whatever its backend.
///
/// It assumes neither an index, nor a work tree, nor a filesystem: a
/// repository stored in memory or exposed without a working directory is a
/// [GitRepository] too. The capabilities that do assume one live on
/// [GitIndexedRepository], [GitWorkingRepository] and [GitFileRepository].
///
/// It implements [GitRepositoryWriter], the narrow read/write contract handed
/// to server-side code, and refines each of its accessors to the matching
/// facade: [objects] is a [GitObjects], [refs] a [GitRefs] and [history] a
/// [GitHistory], all subtypes of the types the contract promises.
/// {@category Getting started}
abstract interface class GitRepository implements GitRepositoryWriter {
  /// Local configuration of this repository: reads and writes limited to
  /// the repository's own configuration file, never the global or system
  /// one, always through this repository.
  GitConfig get config;

  /// Remotes declared for this repository: listing and managing them through
  /// this repository. Fetching from and pushing to a remote are client
  /// operations and live on `GitFileClient`.
  GitRemotes get remotes;

  /// Branches of this repository: listing, creating, renaming, deleting and
  /// upstream tracking, all through this repository.
  GitBranches get branches;

  /// Tags of this repository: listing, creating and deleting, all through
  /// this repository.
  GitTags get tags;

  /// References of this repository: exact ref reads, symbolic refs, ref
  /// updates and branch administration, all through this repository.
  @override
  GitRefs get refs;

  /// Revision expressions of this repository, e.g. `HEAD~2` or
  /// `main^{tree}`, all through this repository.
  GitRevisions get revisions;

  /// Commit-graph history of this repository: ancestry, merge bases and path
  /// history, all through this repository.
  @override
  GitHistory get history;

  /// A transaction that updates several references at once, all or nothing.
  ///
  /// Use [refs] for a single reference; begin a transaction when the updates
  /// must be applied together.
  @override
  GitRefTransaction beginRefTransaction();

  /// Objects and trees: hashing, object inspection, tree writing and reading,
  /// commit fabrication, unmerged index entries and archives, all through
  /// this repository.
  @override
  GitObjects get objects;

  /// Comparisons between two trees: changed paths, text and binary diffs,
  /// all through this repository.
  ///
  /// The index and work-tree comparisons, and patch application, live on
  /// [GitIndexedRepository.patches] and [GitWorkingRepository.patches].
  GitPatches get patches;

  /// Merging that needs no work tree: in-memory merges, available in a bare
  /// repository too. A working repository refines it to a `GitWorkingMerge`.
  GitMerge get merge;

  /// Runs [action] on an indexed view whose active index is a temporary one,
  /// empty or initialized from [fromTree], and returns its result.
  ///
  /// The temporary index is deleted afterwards, even when [action] throws.
  /// Neither the repository's own index nor `$GIT_DIR/index` is ever used: a
  /// bare repository therefore gains no index file, and concurrent operations
  /// on the same repository each get their own index.
  ///
  /// ```dart
  /// final GitOid baseTree = (await repo.objects.readCommit(head)).tree;
  /// final GitOid made = await repo.withTemporaryIndex<GitOid>(
  ///   (GitIndexedRepository view) async {
  ///     final GitOid tree = await view.index.writeTree();
  ///     return view.objects.commitTree(tree, <GitOid>[head], 'Built\n');
  ///   },
  ///   fromTree: baseTree,
  /// );
  /// ```
  Future<T> withTemporaryIndex<T>(
    Future<T> Function(GitIndexedRepository repository) action, {
    GitOid? fromTree,
  });

  /// Drops the administrative data of work trees whose directory no longer
  /// exists (`git worktree prune`). It lives on the repository, so a bare
  /// repository has it too.
  Future<void> pruneWorktrees();
}
