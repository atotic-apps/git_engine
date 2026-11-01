import '../../models/git_conflict_region.dart';
import '../../models/git_identity.dart';
import '../../models/git_oid.dart';
import '../../models/git_reset_mode.dart';
import '../../models/git_status_entry.dart';
import '../refs/git_unknown_revision_exception.dart';
import 'git_local_changes_overwritten_exception.dart';

/// Work tree and index of one repository: status, staging, reset, cleaning,
/// checkout, ignore checks and commits.
///
/// Every command runs inside the owning repository's context, so a derived
/// view (an alternate index, extra environment variables) applies here too.
/// Operations that change state fail on git's refusals — a checkout that
/// would overwrite local changes, a reset to an unknown revision — and raise
/// [GitUnknownRevisionException] for a revision that names nothing,
/// [GitLocalChangesOverwrittenException] for local state a checkout would
/// overwrite, and `GitException` otherwise.
///
/// An expression that reads like an option — a revision or branch
/// parameter starting with `-` — is not part of the grammar of
/// `GitRevisionResolver`: it names nothing, and the operations that take one
/// refuse with [GitUnknownRevisionException] before any command runs. The
/// path parameters of [add], [intentToAdd] and [isIgnored] are literal
/// paths relative to the repository root: no glob (`*`, `?`, `[...]`) and no
/// magic `:(...)` syntax is interpreted. Where [add] or [intentToAdd] takes a
/// list of paths, a directory path covers its content and `.` covers the whole
/// repository.
///
/// ```dart
/// final List<GitStatusEntry> changes = await working.worktree.status();
/// final bool clean = await working.worktree.isClean();
/// await working.worktree.addAll();
/// await working.worktree.add(<String>['app.txt']);
/// final GitOid made = await working.worktree.commit('Add the notes');
/// await working.worktree.checkoutNewBranch('topic');
/// await working.worktree.reset(mode: GitResetMode.hard);
/// await working.worktree.clean(directories: true);
/// ```
/// {@category Getting started}
abstract interface class GitWorktree {
  /// Status of every path that differs between `HEAD`, the index and the
  /// work tree, as git reports it.
  ///
  /// Entries keep git's path spelling and order. An untracked directory is
  /// reported the way git reports it by default (as a single entry ending
  /// with `/`), not walked file by file.
  Future<List<GitStatusEntry>> status();

  /// Whether the index and the work tree hold no change at all — no staged,
  /// unstaged or untracked path. Ignored files do not count.
  Future<bool> isClean();

  /// Stages [paths] (`git add`), work tree changes and removals included.
  ///
  /// [paths] are literal paths relative to the repository root: a directory
  /// covers its content and `.` covers the whole repository. No glob (`*`,
  /// `?`, `[...]`) and no magic `:(...)` syntax is interpreted. No path is a
  /// no-op.
  Future<void> add(List<String> paths);

  /// Stages every change of the work tree, untracked files and deletions
  /// included, except ignored files (`git add -A`).
  Future<void> addAll();

  /// Records the intent to add [paths] without staging their content
  /// (`git add -N`), the usual preparation for a diff of new files.
  ///
  /// [paths] are literal paths relative to the repository root, with the same
  /// rules as [add]. No path is a no-op.
  Future<void> intentToAdd(List<String> paths);

  /// Moves `HEAD` to [target] and updates the index and work tree according
  /// to [mode].
  ///
  /// [target] is a revision expression of the grammar documented on
  /// `GitRevisionResolver`; without it, `HEAD` is the target.
  /// `GitResetMode.mixed` resets the index and keeps the work tree, while
  /// `GitResetMode.hard` overwrites both. A hard reset keeps ignored files and
  /// untracked files outside the target tree, and overwrites an untracked path
  /// that the target tree also holds; a local directory standing in the way of
  /// a tracked file is removed without a refusal.
  /// Moving `HEAD` alone belongs to `GitRefs.resetSoft`, not to a work-tree
  /// operation; asking for `GitResetMode.soft` here raises an
  /// [ArgumentError].
  ///
  /// With [target] given, raises [GitUnknownRevisionException] when it names
  /// no revision.
  Future<void> reset({
    GitResetMode mode = GitResetMode.mixed,
    String? target,
  });

  /// Removes untracked files (`git clean -f`).
  ///
  /// With [directories], untracked directories are removed too (`-d`).
  /// Ignored files and directories are always kept.
  Future<void> clean({bool directories = false});

  /// Switches the work tree to [branch], updating `HEAD`, the index and the
  /// files on disk.
  ///
  /// Git refuses when local changes would be overwritten —
  /// [GitLocalChangesOverwrittenException] carries the paths it names — and
  /// when [branch] names nothing ([GitUnknownRevisionException]).
  Future<void> checkout(String branch);

  /// Detaches `HEAD` at [rev], a revision expression of the grammar documented
  /// on `GitRevisionResolver`, updating the index and the files on disk.
  ///
  /// Raises [GitLocalChangesOverwrittenException] when git would overwrite
  /// local changes or untracked files, [GitUnknownRevisionException] when
  /// [rev] names no revision.
  Future<void> checkoutDetached(String rev);

  /// Creates the branch [name] at [startPoint] (default: `HEAD`) and checks
  /// it out (`git checkout -b`).
  ///
  /// [startPoint] is a revision expression of the grammar documented on
  /// `GitRevisionResolver`. With [resetIfExists] an existing branch is reset to
  /// [startPoint] instead of making git refuse (`git checkout -B`).
  ///
  /// Raises [GitUnknownRevisionException] when [startPoint] names no
  /// revision, [GitLocalChangesOverwrittenException] when git would overwrite
  /// local changes or untracked files, and `GitException` for every other
  /// refusal.
  Future<void> checkoutNewBranch(
    String name, {
    String? startPoint,
    bool resetIfExists = false,
  });

  /// Whether [path] is ignored by the repository's ignore rules
  /// (`git check-ignore`).
  ///
  /// [path] is a literal path relative to the repository root; no glob (`*`,
  /// `?`, `[...]`) and no magic `:(...)` syntax is interpreted. With
  /// [noIndex], the check applies even to a path tracked by the index.
  Future<bool> isIgnored(String path, {bool noIndex = false});

  /// Scans [paths] of the work tree for real conflict markers, line by line.
  ///
  /// [paths] are work-tree relative paths, the lists a conflicted merge or
  /// apply names - `GitMergeConflicts.conflictingFiles`,
  /// `GitMergeTreeResult.conflictingFiles`, `GitApplyConflicted.paths`. A
  /// path that names no readable file carries no conflict and is skipped.
  ///
  /// Every path must be relative to the work tree and spelled with forward
  /// slashes: it is refused, naming it in a `GitException` before anything is
  /// read, when it is empty or absolute (`/...`, `\...`, `C:...`,
  /// `\\server\...`), or holds a backslash, a NUL character, an empty, `.`
  /// or `..` segment. On Windows a segment holding a colon, ending with a
  /// dot or a space, or naming a reserved device (`CON`, `PRN`, `AUX`, `NUL`,
  /// `COM1` to `COM9`, `LPT1` to `LPT9`, with or without an extension, in any
  /// case) is refused too. One refused path refuses the whole call, so a
  /// caller that scans git's conflict lists passes them unchanged.
  ///
  /// A path whose existing segment under the work tree root is a symbolic
  /// link or a Windows junction is treated like an absent file and never
  /// read: git writes no markers through a link. The check and the read are
  /// separate operations, so a work tree modified in between can still turn
  /// the path into a link the read follows.
  ///
  /// A conflict block is the structure git writes: a `<<<<<<<` line, a
  /// `=======` line, a `>>>>>>>` line with its label, each at the start of
  /// its line. Only a complete block is reported, so a lone `=======`
  /// separator, a `=======` run in ordinary text, and a bare `<<<<<<<`
  /// without the tail that closes it are never a conflict; a `>>>>>>>`
  /// glued to its label closes a block. Regions come back in the order the
  /// paths were given, and by line within a file. The work is linear in the
  /// size of the files scanned.
  Future<List<GitConflictRegion>> scanConflictMarkers(List<String> paths);

  /// Commits the staged changes with [message] and returns the new commit's
  /// object name.
  ///
  /// [message] is cleaned before it is recorded: trailing whitespace is
  /// removed from every line, blank lines at the start and at the end are
  /// dropped, a run of blank lines inside the message becomes a single blank
  /// line, a final newline is added, and lines starting with `#` are kept as
  /// they are. A message that is empty once cleaned is refused.
  ///
  /// When [identity] is given, it is used as the author and committer through
  /// the repository environment, whatever the configuration says. With
  /// [allowEmpty], a commit is created even when the index holds no change.
  Future<GitOid> commit(
    String message, {
    GitIdentity? identity,
    bool allowEmpty = false,
  });
}
