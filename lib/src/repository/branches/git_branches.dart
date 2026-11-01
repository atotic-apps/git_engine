import '../../models/git_branch.dart';
import '../../models/git_ref.dart';
import '../refs/git_branch_not_merged_exception.dart';
import '../refs/git_invalid_ref_name_exception.dart';
import '../refs/git_ref_exists_exception.dart';
import '../refs/git_ref_not_found_exception.dart';
import '../refs/git_unknown_revision_exception.dart';

/// Branches of one repository: listing, creating, renaming, deleting and
/// upstream tracking.
///
/// Every command runs inside the owning repository's context, so a derived
/// view (an alternate index, extra environment variables) applies here too.
/// The operations behave the same in a bare repository and in a clone with a
/// work tree: renaming or deleting the branch `HEAD` points at treats it
/// like any other branch, and listing reads the branches of the repository,
/// wherever `HEAD` stands.
///
/// Every failure is a `GitException`, except where an operation documents a
/// null result (a detached `HEAD`); the refusals a caller can treat are
/// named on the operation.
///
/// The branch names the operations take are short names, and they are
/// rejected before any command runs when they cannot be reference names:
/// the rules documented on [GitInvalidRefNameException], plus `HEAD`, which
/// a branch is never named. A violating name raises
/// [GitInvalidRefNameException] before any git call.
///
/// ```dart
/// final String? current = await repo.branches.current();
/// final List<GitBranch> local = await repo.branches.list();
/// final List<GitRef> remote = await repo.branches.listRemote();
/// await repo.branches.create('topic');
/// await repo.branches.rename('topic', 'bugfix');
/// await repo.branches.setUpstream('bugfix', 'origin/bugfix');
/// await repo.branches.delete('bugfix', force: true);
/// ```
/// {@category Getting started}
abstract interface class GitBranches {
  /// Local branches, sorted by name.
  ///
  /// A repository without commits lists no branch. A branch whose upstream
  /// was set carries it in short form, e.g. `origin/main`, whether or not
  /// the upstream branch still exists.
  Future<List<GitBranch>> list();

  /// Remote-tracking branches (`refs/remotes/...`), sorted by name.
  ///
  /// The symbolic `<remote>/HEAD` references are never listed. Without
  /// [remote], the branches of every remote are listed; with [remote], only
  /// that remote's ones — an unknown remote lists none. Nothing is fetched:
  /// the listing reads the remote-tracking references the repository holds.
  Future<List<GitRef>> listRemote({String? remote});

  /// Short name of the branch `HEAD` points at, e.g. `main`.
  ///
  /// Returns null when `HEAD` is detached. In a repository without commits
  /// still returns the branch `HEAD` is set to create.
  Future<String?> current();

  /// Creates the branch [name] at [startPoint] without switching to it
  /// (`git branch`).
  ///
  /// [startPoint] is a revision expression of the grammar documented on
  /// `GitRevisionResolver`; it defaults to `HEAD`. With [force], an existing
  /// branch is reset to [startPoint] instead of the refusal below. A
  /// repository without commits has no revision to start from and refuses
  /// with [GitUnknownRevisionException]. An expression that reads like an
  /// option — it starts with `-` — names no revision and is refused the same
  /// way before any command runs.
  ///
  /// Raises [GitInvalidRefNameException] when [name] cannot be a branch
  /// name, [GitRefExistsException] when [name] is already taken and [force]
  /// is false, [GitUnknownRevisionException] when [startPoint] names no
  /// revision.
  Future<void> create(
    String name, {
    String? startPoint,
    bool force = false,
  });

  /// Renames the branch [name] to [newName].
  ///
  /// Renaming the branch `HEAD` points at updates `HEAD` with it.
  ///
  /// Raises [GitInvalidRefNameException] when [name] or [newName] cannot be
  /// a branch name, [GitRefNotFoundException] when [name] does not exist,
  /// [GitRefExistsException] when [newName] is already taken and [force] is
  /// false.
  Future<void> rename(String name, String newName, {bool force = false});

  /// Deletes the branch [name].
  ///
  /// With [force] the branch is deleted even when it is not fully merged
  /// into its upstream or `HEAD`; without it git refuses rather than lose
  /// its commits, and [GitBranchNotMergedException] carries that refusal.
  /// Deleting the branch `HEAD` points at is refused with a `GitException`,
  /// in a work tree and in a bare repository alike — move `HEAD` first,
  /// with `GitRefs.setHead` or a checkout.
  ///
  /// Raises [GitInvalidRefNameException] when [name] cannot be a branch
  /// name, [GitRefNotFoundException] when [name] does not exist.
  Future<void> delete(String name, {bool force = false});

  /// Makes [branch] track [upstream], e.g.
  /// `setUpstream('main', 'origin/main')`.
  ///
  /// [branch] must exist and [upstream] must name a branch. [upstream] that
  /// reads like an option — it starts with `-` — names no branch and is
  /// refused as below. Raises
  /// [GitInvalidRefNameException] when [branch] cannot be a branch name,
  /// [GitRefNotFoundException] when [branch] does not exist,
  /// [GitUnknownRevisionException] when [upstream] names no branch. Once
  /// set, the upstream reads back on
  /// `GitBranch.upstream` and through `GitRevisions.symbolicFullName` with
  /// `@{upstream}`.
  Future<void> setUpstream(String branch, String upstream);
}
