import '../../models/git_oid.dart';
import '../../models/git_ref.dart';
import 'git_invalid_ref_name_exception.dart';
import 'git_ref_mismatch_exception.dart';
import 'git_ref_reader.dart';

/// References of one repository: exact ref reads, symbolic refs and ref
/// updates.
///
/// It implements [GitRefReader], so it can be used wherever server code needs
/// to read references. Every command runs inside the owning repository's
/// context, so a derived view (an alternate index, extra environment
/// variables) applies here too.
///
/// The operations behave the same in a bare repository and in a clone with a
/// work tree. Every failure is a `GitException`, except where an operation
/// documents a null result (an absent revision); the refusals a caller can
/// treat are named on the operation.
///
/// Branch administration lives on `GitBranches`, tags on `GitTags`; this
/// facade stays at the level of named references.
///
/// The names the write operations (`setHead`, `updateRef`, `deleteRef`)
/// take are rejected before any command runs when they cannot name a
/// reference: the rules documented on [GitInvalidRefNameException]. A full
/// reference is a `refs/...` name under those rules, or one of the
/// pseudo-references git maintains at the top level (`HEAD`, `FETCH_HEAD`,
/// `MERGE_HEAD`, `ORIG_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`); any other
/// one-level name is refused. Revision expressions this facade resolves —
/// `exists`, `resetSoft` — follow the grammar of `GitRevisionResolver`,
/// including the rule that an expression starting with `-` names nothing.
///
/// ```dart
/// final GitOid? main = await repo.refs.resolveRef('refs/heads/main');
/// final String? target = await repo.refs.symbolicTarget('HEAD');
/// final List<GitRef> branches =
///     await repo.refs.listRefs(prefix: 'refs/heads/');
/// final bool known = await repo.refs.exists('main');
/// await repo.refs.updateRef('refs/heads/main', head, expectedOld: base);
/// await repo.refs.deleteRef('refs/heads/stale');
/// await repo.refs.resetSoft('main');
/// ```
/// {@category Getting started}
abstract interface class GitRefs implements GitRefReader {
  /// Resolves the exact reference [refName]; see
  /// [GitRefReader.resolveRef].
  @override
  Future<GitOid?> resolveRef(String refName);

  /// Target of the symbolic reference [refName]; see
  /// [GitRefReader.symbolicTarget].
  @override
  Future<String?> symbolicTarget(String refName);

  /// Whether [refName] resolves to an object.
  ///
  /// [refName] is a revision expression of the grammar documented on
  /// `GitRevisionResolver`, so `refs/heads/main`, `main` and `HEAD` all work;
  /// returns false rather than throwing for a name that resolves to nothing,
  /// including `HEAD` in a repository without commits.
  Future<bool> exists(String refName);

  /// Makes `HEAD` a symbolic ref to [refName].
  ///
  /// A name without a `refs/` prefix is taken as a branch, so `setHead('main')`
  /// points `HEAD` at `refs/heads/main`. Works in a bare repository, where it
  /// is the only way to move `HEAD`. The target branch does not have to exist.
  ///
  /// Raises [GitInvalidRefNameException] when [refName] cannot name a
  /// reference — a full `refs/...` name under the rule above, or a branch
  /// short name.
  Future<void> setHead(String refName);

  /// Moves `HEAD` to [target] without touching the index or the work tree
  /// (`git reset --soft`).
  ///
  /// [target] is a revision expression of the grammar documented on
  /// `GitRevisionResolver`, so a branch name and an object name both work. It
  /// works in a bare repository too, where it moves the branch `HEAD` points
  /// at. The commits left behind stay reachable through the refs that still
  /// name them, and their changes stay staged in a work tree. An expression
  /// that reads like an option — it starts with `-` — names no revision and
  /// is refused before any command runs.
  ///
  /// Raises [GitUnknownRevisionException] when [target] names no revision.
  Future<void> resetSoft(String target);

  /// Sets [name] to [oid].
  ///
  /// [name] is a full reference name, under the rule documented on
  /// [GitInvalidRefNameException] and checked before any command runs. When
  /// [expectedOld] is given, the ref must currently point at it, and a
  /// [GitRefMismatchException] is thrown otherwise. Without it the update is
  /// unconditional and creates the ref when it does not exist yet.
  ///
  /// Raises [GitInvalidRefNameException] when [name] cannot name a reference.
  Future<void> updateRef(String name, GitOid oid, {GitOid? expectedOld});

  /// Deletes [name].
  ///
  /// [name] is a full reference name, under the same rule and check as
  /// [updateRef]. When [expectedOld] is given, the ref must currently point
  /// at it, and a [GitRefMismatchException] is thrown otherwise. Deleting a
  /// ref that does not exist succeeds silently.
  ///
  /// Raises [GitInvalidRefNameException] when [name] cannot name a reference.
  Future<void> deleteRef(String name, {GitOid? expectedOld});

  /// Every reference whose full name starts with [prefix]; see
  /// [GitRefReader.listRefs].
  @override
  Future<List<GitRef>> listRefs({String? prefix});
}
