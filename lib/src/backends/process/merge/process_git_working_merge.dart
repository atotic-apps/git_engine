import 'package:git_engine/backend.dart';
import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_refusal.dart';
import '../git_runner.dart';
import 'process_git_merge.dart';

/// [GitWorkingMerge] implementation running git through the owning process
/// repository, so every command inherits the repository context - working
/// directory and environment variables - instead of talking to the runner
/// alone.
///
/// It extends [ProcessGitMerge] with the operations that merge into a work
/// tree: fast-forwards, merge commits, conflicted merges and their abort.
///
/// It implements the [GitWorkingMerge] facade, which carries the compatibility
/// contract; this class is an implementation detail.
class ProcessGitWorkingMerge extends ProcessGitMerge
    implements GitWorkingMerge {
  /// Builds the working merge over [repository], with the same version gate
  /// as the repository-level merge.
  ProcessGitWorkingMerge({
    required super.repository,
    required super.runtime,
  });

  @override
  Future<GitMergeResult> merge(
    String rev, {
    GitMergeMode mode = GitMergeMode.auto,
    bool noCommit = false,
    String? message,
    bool allowUnrelatedHistories = false,
  }) async {
    refuseOptionLikeRevision(rev);
    if (mode == GitMergeMode.fastForwardOnly) {
      await _ensureFastForwardPossible(rev);
    }
    final GitOid? headBefore = await _resolve('HEAD');
    try {
      await repository.runCommand(<String>[
        'merge',
        '--no-edit',
        if (mode == GitMergeMode.fastForwardOnly) '--ff-only',
        if (mode == GitMergeMode.noFastForward) '--no-ff',
        if (noCommit) '--no-commit',
        if (allowUnrelatedHistories) '--allow-unrelated-histories',
        if (message != null) ...<String>['-m', message],
        '--',
        rev,
      ]);
    } on GitCommandException catch (error) {
      if (await _hasStagedConflicts()) {
        return GitMergeConflicts(conflictingFiles: await _conflictingFiles());
      }
      throw mergeFailure(error, rev);
    }
    final GitOid? headAfter = await _resolve('HEAD');
    if (headBefore == null) {
      // git squared an unborn head away; the head it points at now is the
      // history that was merged in.
      return headAfter == null
          ? const GitMergeUpToDate()
          : GitMergeFastForward(newHead: headAfter);
    }
    if (headAfter == headBefore) {
      // The head did not move: the merged history was already there ("already
      // up to date"), or the merge was staged and stopped before committing
      // (--no-commit), which leaves MERGE_HEAD behind.
      return (await _resolve('MERGE_HEAD')) != null
          ? const GitMergeStopped()
          : const GitMergeUpToDate();
    }
    if (headAfter == null) {
      return const GitMergeUpToDate();
    }
    // A real fast-forward moves HEAD exactly onto the merged revision; a
    // merge commit is a brand new commit whose first parent is the old head.
    final GitOid? mergedOid = await _resolve(rev);
    if (mergedOid != null && headAfter == mergedOid) {
      return GitMergeFastForward(newHead: headAfter);
    }
    return GitMergeCommit(commit: headAfter);
  }

  @override
  Future<bool> isMerging() async => (await _resolve('MERGE_HEAD')) != null;

  @override
  Future<void> abort() async {
    try {
      await repository.runCommand(<String>['merge', '--abort']);
    } on GitCommandException catch (error) {
      throw mergeAbortFailure(error);
    }
  }

  /// Refuses a fast-forward that cannot happen with fast-forward-only mode,
  /// so an impossibility is reported upfront and nothing of the repository is
  /// touched. A revision already contained in the head is not an
  /// impossibility (git answers "already up to date"); unresolvable names and
  /// unborn heads are left for the real merge to answer.
  Future<void> _ensureFastForwardPossible(String rev) async {
    final GitOid? head = await _resolve('HEAD');
    if (head == null) {
      return;
    }
    final GitOid? revOid = await _resolve(rev);
    if (revOid == null) {
      return;
    }
    final GitCommandException? revIsAncestor =
        await _ancestorFailure(revOid, head);
    if (revIsAncestor == null) {
      return;
    }
    final GitCommandException? headIsAncestor =
        await _ancestorFailure(head, revOid);
    if (headIsAncestor != null) {
      throw GitMergeNotFastForwardException(
        'no fast-forward possible from HEAD ($head) to $rev',
        cause: headIsAncestor,
      );
    }
  }

  /// The failure of the ancestry check when [a] is not an ancestor of [b], or
  /// null when it is.
  Future<GitCommandException?> _ancestorFailure(GitOid a, GitOid b) async {
    try {
      await repository.runCommand(<String>[
        'merge-base',
        '--is-ancestor',
        a.value,
        b.value,
      ]);
      return null;
    } on GitCommandException catch (error) {
      return error;
    }
  }

  /// Whether the merge that just failed actually found conflicts: git wrote
  /// its MERGE_HEAD and staged unmerged entries.
  Future<bool> _hasStagedConflicts() async {
    return (await _resolve('MERGE_HEAD')) != null &&
        (await _conflictingFiles()).isNotEmpty;
  }

  /// Paths currently staged as unmerged, once each, in index order.
  Future<List<String>> _conflictingFiles() async {
    final GitRunResult result = await repository.runCommand(<String>[
      'ls-files',
      '--unmerged',
      '-z',
    ]);
    final List<String> paths = <String>[];
    for (final String entry in result.stdout.split('\x00')) {
      if (entry.isEmpty) {
        continue;
      }
      final String path = _unmergedPath(entry);
      if (!paths.contains(path)) {
        paths.add(path);
      }
    }
    return paths;
  }

  /// Path part of one `ls-files --unmerged -z` entry, of the form
  /// `<mode> <object> <stage>\t<path>`.
  static String _unmergedPath(String entry) {
    final int tab = entry.indexOf('\t');
    return tab < 0 ? entry : entry.substring(tab + 1);
  }

  /// Object name [rev] resolves to (or null: an unborn `HEAD`, an unknown
  /// name).
  Future<GitOid?> _resolve(String rev) async {
    try {
      final GitRunResult result = await repository.runCommand(
        <String>['rev-parse', '--verify', '--quiet', rev],
      );
      return GitOid.tryParse(result.stdout.trim());
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException {
      return null;
    }
  }
}
