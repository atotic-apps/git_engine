import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_runner.dart';
import '../process_git_repository.dart';
import 'applyable_diff_arguments.dart';

/// [GitPatches] implementation running tree-to-tree comparisons through the
/// owning process repository, so every command inherits the repository context
/// — working directory and environment variables — instead of talking to the
/// runner alone.
class ProcessGitPatches implements GitPatches {
  /// Repository whose context every command runs in.
  final ProcessGitRepository repository;

  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitPatches({required this.repository});

  /// Git's diff-filter letter for each change kind.
  static const Map<GitChangeKind, String> _diffFilterLetters =
      <GitChangeKind, String>{
    GitChangeKind.added: 'A',
    GitChangeKind.copied: 'C',
    GitChangeKind.deleted: 'D',
    GitChangeKind.modified: 'M',
    GitChangeKind.renamed: 'R',
    GitChangeKind.typeChanged: 'T',
    GitChangeKind.unmerged: 'U',
  };

  @override
  Future<List<String>> changedPaths(
    GitOid from,
    GitOid to, {
    Set<GitChangeKind>? kinds,
  }) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      '--name-only',
      '-z',
      ...diffFilterArguments(kinds),
      from.value,
      to.value,
    ]);
    return splitPaths(result.stdout);
  }

  @override
  Future<String> textDiff(
    GitOid from,
    GitOid to, {
    List<String> paths = const <String>[],
  }) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      '--no-color',
      from.value,
      to.value,
      if (paths.isNotEmpty) '--',
      ...paths,
    ]);
    return result.stdout;
  }

  @override
  Future<Uint8List> binaryDiff(GitOid from, GitOid to) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'diff',
      ...applyableDiffArguments,
      from.value,
      to.value,
    ]);
    return result.stdoutBytes;
  }

  /// Runs `git apply` with [options] on [patch], written to a temporary file
  /// of the injected file system, and turns git's refusal into a
  /// [GitApplyResult].
  ///
  /// With `--3way` among [options], a failure that git reports as applied with
  /// conflicts becomes [GitApplyConflicted]; every other failure becomes
  /// [GitApplyRefused].
  Future<GitApplyResult> applyPatch(
    List<int> patch,
    List<String> options,
  ) async {
    final String sandbox = await repository.fileSystem
        .createTemporaryDirectory('git_engine_patch_');
    try {
      final String patchFile =
          repository.platform.pathStyle.join(sandbox, 'patch.diff');
      await repository.fileSystem.writeBytes(patchFile, patch);
      try {
        await repository.runCommand(<String>[
          'apply',
          ...options,
          patchFile,
        ]);
        return const GitApplyApplied();
      } on GitCommandException catch (error) {
        if (options.contains('--3way')) {
          final List<String> conflicts = _conflictedPaths(error);
          if (conflicts.isNotEmpty) {
            return GitApplyConflicted(conflicts);
          }
        }
        return GitApplyRefused(error.stderr);
      }
    } finally {
      try {
        await repository.fileSystem.deleteDirectory(sandbox, recursive: true);
      } catch (_) {
        // Best effort: a leaked temp directory is harmless.
      }
    }
  }

  /// Splits NUL-separated `--name-only -z` output, removing duplicates and
  /// sorting the paths by the UTF-8 bytes of the full path.
  static List<String> splitPaths(String output) {
    final Set<String> unique = <String>{
      for (final String field in output.split('\u0000'))
        if (field.isNotEmpty) field,
    };
    final List<String> paths = unique.toList()..sort(_compareUtf8);
    return paths;
  }

  /// Compares [first] and [second] by their UTF-8 bytes.
  static int _compareUtf8(String first, String second) {
    final List<int> left = utf8.encode(first);
    final List<int> right = utf8.encode(second);
    final int common = left.length < right.length ? left.length : right.length;
    for (var index = 0; index < common; index++) {
      final int difference = left[index] - right[index];
      if (difference != 0) {
        return difference;
      }
    }
    return left.length - right.length;
  }

  /// Git arguments selecting the changes [kinds] asks for.
  ///
  /// An empty set is refused, and rename or copy detection is enabled only
  /// when those kinds are requested.
  static List<String> diffFilterArguments(Set<GitChangeKind>? kinds) {
    if (kinds == null) {
      return const <String>[];
    }
    if (kinds.isEmpty) {
      throw ArgumentError.value(kinds, 'kinds', 'must not be empty');
    }
    final StringBuffer filter = StringBuffer();
    for (final GitChangeKind kind in GitChangeKind.values) {
      if (kinds.contains(kind)) {
        filter.write(_diffFilterLetters[kind]);
      }
    }
    return <String>[
      '--diff-filter=$filter',
      if (kinds.contains(GitChangeKind.renamed) ||
          kinds.contains(GitChangeKind.copied))
        '-M',
      if (kinds.contains(GitChangeKind.copied)) '--find-copies-harder',
    ];
  }

  /// Files git reported as applied with conflicts, read from messages such as
  /// `Applied patch to 'a.txt' with conflicts.`.
  static List<String> _conflictedPaths(GitCommandException error) {
    final RegExp pattern =
        RegExp(r"^Applied patch to '(.*)' with conflicts\.$", multiLine: true);
    final List<String> paths = <String>[];
    for (final RegExpMatch match
        in pattern.allMatches('${error.stderr}\n${error.stdout}')) {
      final String path = match.group(1)!;
      if (!paths.contains(path)) {
        paths.add(path);
      }
    }
    return paths;
  }
}
