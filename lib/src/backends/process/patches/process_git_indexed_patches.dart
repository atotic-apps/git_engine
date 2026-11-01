import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import '../git_runner.dart';
import 'applyable_diff_arguments.dart';
import 'process_git_patches.dart';

/// [GitIndexedPatches] implementation running tree-to-index comparisons and
/// index-only applies through the owning process repository.
class ProcessGitIndexedPatches extends ProcessGitPatches
    implements GitIndexedPatches {
  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitIndexedPatches({required super.repository});

  @override
  Future<List<String>> changedPathsAgainstIndex(
    GitOid tree, {
    Set<GitChangeKind>? kinds,
  }) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      '--name-only',
      '-z',
      ...ProcessGitPatches.diffFilterArguments(kinds),
      '--cached',
      tree.value,
    ]);
    return ProcessGitPatches.splitPaths(result.stdout);
  }

  @override
  Future<String> textDiffAgainstIndex(
    GitOid tree, {
    List<String> paths = const <String>[],
  }) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      '--no-color',
      '--cached',
      tree.value,
      if (paths.isNotEmpty) '--',
      ...paths,
    ]);
    return result.stdout;
  }

  @override
  Future<Uint8List> binaryDiffAgainstIndex(GitOid tree) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      ...applyableDiffArguments,
      '--cached',
      tree.value,
    ]);
    return result.stdoutBytes;
  }

  @override
  Future<GitApplyResult> applyToIndex(
    List<int> patch, {
    bool check = false,
    bool reverse = false,
    bool threeWay = false,
  }) {
    return applyPatch(patch, <String>[
      '--cached',
      if (check) '--check',
      if (reverse) '--reverse',
      if (threeWay) '--3way',
    ]);
  }
}
