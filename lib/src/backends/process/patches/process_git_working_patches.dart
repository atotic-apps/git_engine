import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import '../git_runner.dart';
import 'applyable_diff_arguments.dart';
import 'process_git_indexed_patches.dart';
import 'process_git_patches.dart';

/// [GitWorkingPatches] implementation running index-to-work-tree comparisons
/// and work-tree applies through the owning process repository.
class ProcessGitWorkingPatches extends ProcessGitIndexedPatches
    implements GitWorkingPatches {
  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitWorkingPatches({required super.repository});

  @override
  Future<List<String>> changedPathsAgainstWorkTree({
    Set<GitChangeKind>? kinds,
  }) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      '--name-only',
      '-z',
      ...ProcessGitPatches.diffFilterArguments(kinds),
    ]);
    return ProcessGitPatches.splitPaths(result.stdout);
  }

  @override
  Future<String> textDiffAgainstWorkTree({
    List<String> paths = const <String>[],
  }) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      '--no-color',
      if (paths.isNotEmpty) '--',
      ...paths,
    ]);
    return result.stdout;
  }

  @override
  Future<Uint8List> binaryDiffAgainstWorkTree() async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      ...applyableDiffArguments,
    ]);
    return result.stdoutBytes;
  }

  @override
  Future<List<String>> changedPathsFromTree(
    GitOid tree, {
    Set<GitChangeKind>? kinds,
  }) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      '--name-only',
      '-z',
      ...ProcessGitPatches.diffFilterArguments(kinds),
      tree.value,
    ]);
    return ProcessGitPatches.splitPaths(result.stdout);
  }

  @override
  Future<String> textDiffFromTree(
    GitOid tree, {
    List<String> paths = const <String>[],
  }) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      '--no-color',
      tree.value,
      if (paths.isNotEmpty) '--',
      ...paths,
    ]);
    return result.stdout;
  }

  @override
  Future<Uint8List> binaryDiffFromTree(GitOid tree) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      ...applyableDiffArguments,
      tree.value,
    ]);
    return result.stdoutBytes;
  }

  @override
  Future<GitApplyResult> apply(
    List<int> patch, {
    bool check = false,
    bool reverse = false,
    bool threeWay = false,
  }) {
    return applyPatch(patch, <String>[
      if (check) '--check',
      if (reverse) '--reverse',
      if (threeWay) '--3way',
    ]);
  }
}
