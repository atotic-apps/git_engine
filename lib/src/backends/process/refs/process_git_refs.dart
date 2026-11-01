import 'dart:convert';

import 'package:git_engine/backend.dart';
import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_refusal.dart';
import '../git_runner.dart';
import '../process_git_repository.dart';
import 'ref_update_failure.dart';

/// [GitRefs] implementation running git through the owning process
/// repository, so every command inherits the repository context — working
/// directory and environment variables — instead of talking to the runner
/// alone.
class ProcessGitRefs implements GitRefs {
  /// Repository whose context every command runs in.
  final ProcessGitRepository repository;

  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitRefs({required this.repository});

  @override
  Future<GitOid?> resolveRef(String refName) async {
    try {
      final GitRunResult result;
      if (refName.startsWith('refs/')) {
        result = await repository.runCommand(<String>[
          'show-ref',
          '--verify',
          '--hash',
          refName,
        ]);
      } else if (refName == 'HEAD') {
        result = await repository.runCommand(<String>[
          'rev-parse',
          '--verify',
          '--quiet',
          refName,
        ]);
      } else {
        return null;
      }
      return GitOid.tryParse(result.stdout.trim());
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException {
      // Exit code 1: the ref does not exist; git also refuses a name that is
      // not a full reference.
      return null;
    }
  }

  @override
  Future<String?> symbolicTarget(String refName) async {
    try {
      final GitRunResult result = await repository.runCommand(
        <String>['symbolic-ref', '--quiet', refName],
      );
      final String target = result.stdout.trim();
      return target.isEmpty ? null : target;
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException {
      // Exit code 1: a direct or absent ref, not a symbolic one.
      return null;
    }
  }

  @override
  Future<bool> exists(String refName) async {
    return (await repository.revisions.resolveRevision(refName)) != null;
  }

  @override
  Future<void> setHead(String refName) async {
    checkHeadTarget(refName);
    final String target =
        refName.startsWith('refs/') ? refName : 'refs/heads/$refName';
    await repository.runCommand(<String>['symbolic-ref', 'HEAD', '--', target]);
  }

  @override
  Future<void> resetSoft(String target) async {
    refuseOptionLikeRevision(target);
    try {
      await repository.runCommand(<String>['reset', '--soft', target]);
    } on GitCommandException catch (error) {
      throw unknownRevisionFailure(error, target);
    }
  }

  @override
  Future<void> updateRef(String name, GitOid oid, {GitOid? expectedOld}) {
    checkWritableRefName(name);
    return _update(<String>[
      'update-ref',
      '--',
      name,
      oid.value,
      if (expectedOld != null) expectedOld.value,
    ]);
  }

  @override
  Future<void> deleteRef(String name, {GitOid? expectedOld}) {
    checkWritableRefName(name);
    return _update(<String>[
      'update-ref',
      '-d',
      '--',
      name,
      if (expectedOld != null) expectedOld.value,
    ]);
  }

  /// Raises [GitInvalidRefNameException] when [refName] cannot be what
  /// `HEAD` is moved onto: a full `refs/...` name, or a bare branch name.
  static void checkHeadTarget(String refName) {
    if (refName.startsWith('refs/')) {
      checkWritableRefName(refName);
    } else {
      checkBranchName(refName);
    }
  }

  /// Runs an `update-ref` command, reporting a rejected expected value as
  /// [GitRefMismatchException] and every other refusal as-is.
  Future<void> _update(List<String> arguments) async {
    try {
      await repository.runCommand(arguments);
    } on GitCommandException catch (error) {
      if (isExpectedValueMismatch(error)) {
        throw GitRefMismatchException(cause: error);
      }
      rethrow;
    }
  }

  @override
  Future<List<GitRef>> listRefs({String? prefix}) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'for-each-ref',
      '--format=%(refname)%09%(objectname)',
    ]);
    final List<GitRef> refs = <GitRef>[];
    for (final String line in const LineSplitter().convert(result.stdout)) {
      if (line.isEmpty) {
        continue;
      }
      final int separator = line.indexOf('\t');
      if (separator < 0) {
        throw FormatException('Unexpected for-each-ref line: "$line"', line);
      }
      final GitOid? oid = GitOid.tryParse(line.substring(separator + 1).trim());
      if (oid == null) {
        throw FormatException(
          'Unexpected for-each-ref object name in: "$line"',
          line,
        );
      }
      final String name = line.substring(0, separator);
      if (prefix == null || name.startsWith(prefix)) {
        refs.add(GitRef(name: name, oid: oid));
      }
    }
    return refs;
  }
}
