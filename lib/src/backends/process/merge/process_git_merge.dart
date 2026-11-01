import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_refusal.dart';
import '../git_runner.dart';
import '../git_version.dart';
import '../process_git_repository.dart';

/// Oldest git with `git merge-tree --write-tree`, required by
/// [ProcessGitMerge.mergeTree].
const String mergeTreeMinimumGitVersion = '2.38';

/// Exit code git reports for a merge whose computation found conflicts; the
/// conflict report then travels in the standard output.
const int _conflictedExitCode = 1;

/// [GitMerge] implementation running git through the owning process
/// repository, so every command inherits the repository context - working
/// directory and environment variables - instead of talking to the runner
/// alone.
///
/// It carries the repository-level merge: computing a merged tree without an
/// index or a work tree. [ProcessGitWorkingMerge] extends it with the
/// operations that merge into a work tree.
///
/// It implements the [GitMerge] facade, which carries the compatibility
/// contract; this class is an implementation detail.
class ProcessGitMerge implements GitMerge {
  /// Repository whose context every command runs in.
  final ProcessGitRepository repository;

  /// Runtime used to read the installed git version for [mergeTree], whose
  /// `--write-tree` mode needs a recent `merge-tree`; built on the same
  /// runner.
  final GitEngineRuntime runtime;

  /// Builds the domain over [repository], with [runtime] as its version gate.
  ProcessGitMerge({required this.repository, required this.runtime});

  @override
  Future<GitMergeTreeResult> mergeTree(
    GitOid ours,
    GitOid theirs, {
    bool allowUnrelatedHistories = false,
  }) async {
    await _ensureMergeTreeAvailable();
    try {
      final GitRunResult result = await repository.runCommand(<String>[
        'merge-tree',
        '--write-tree',
        '--name-only',
        '-z',
        if (allowUnrelatedHistories) '--allow-unrelated-histories',
        ours.value,
        theirs.value,
      ]);
      return _mergeTreeResult(
          _parseMergeTreeOutput(result.stdout), result.stdout);
    } on GitCommandException catch (error) {
      // Exit code 1: the merge itself found conflicts and the output still
      // carries the merged tree. Any other code is a refusal of git's,
      // reported as the unrelated-histories domain failure when git's
      // diagnostic says so, as-is otherwise.
      if (error.exitCode != _conflictedExitCode) {
        throw unrelatedHistoriesFailure(error);
      }
      final (GitOid, List<String>)? parsed =
          _parseMergeTreeOutput(error.stdout);
      if (parsed == null) {
        rethrow;
      }
      return GitMergeTreeResult(tree: parsed.$1, conflictingFiles: parsed.$2);
    }
  }

  /// Refuses an installed git that predates `merge-tree --write-tree`.
  ///
  /// The operation is implemented; only this runtime cannot run it, so the
  /// failure is a [GitFeatureUnavailableException], not a
  /// `GitVersionException` from an explicit version check.
  Future<void> _ensureMergeTreeAvailable() async {
    final String installedVersion = await runtime.engineVersion();
    final GitVersionTriple? installed = parseGitVersion(installedVersion);
    if (installed == null) {
      throw FormatException(
        'Cannot parse git version from: "$installedVersion"',
        installedVersion,
      );
    }
    final GitVersionTriple required =
        parseVersionConstraint(mergeTreeMinimumGitVersion)!;
    if (compareGitVersions(installed, required) < 0) {
      throw GitFeatureUnavailableException(
        operation: 'mergeTree',
        requiredVersion: mergeTreeMinimumGitVersion,
        installedVersion: installedVersion,
      );
    }
  }

  /// Raises when [parsed] turned out to hold no tree name (a success exit
  /// code but an unparsable output, which git never produces).
  static GitMergeTreeResult _mergeTreeResult(
    (GitOid, List<String>)? parsed,
    String stdout,
  ) {
    if (parsed == null) {
      throw FormatException(
        'cannot parse merge-tree output: "$stdout"',
        stdout,
      );
    }
    return GitMergeTreeResult(tree: parsed.$1, conflictingFiles: parsed.$2);
  }

  /// Parses the NUL-encoded output of `merge-tree --write-tree`, whose first
  /// segment is the merged tree name and whose next non-empty segments are
  /// the conflicted file names, up to the start of the (ignored, unstable)
  /// messages section. A clean merge carries nothing after the tree, and a
  /// cached tree name of null means the output came from a refusal, not from
  /// a merge.
  static (GitOid, List<String>)? _parseMergeTreeOutput(String stdout) {
    final List<String> segments = stdout.split('\x00');
    final GitOid? tree = GitOid.tryParse(segments.first.trim());
    if (tree == null) {
      return null;
    }
    final List<String> files = <String>[];
    for (var i = 1; i < segments.length; i++) {
      final String segment = segments[i];
      if (segment.isEmpty) {
        // End of a clean merge's output, or the first NUL of the messages
        // section, which no longer belongs to the file list.
        break;
      }
      files.add(segment);
    }
    return (tree, files);
  }
}
