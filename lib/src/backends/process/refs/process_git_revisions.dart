import 'package:git_engine/backend.dart';
import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_refusal.dart';
import '../git_runner.dart';
import '../process_git_repository.dart';

/// [GitRevisions] implementation running git through the owning process
/// repository, so every command inherits the repository context.
class ProcessGitRevisions implements GitRevisions {
  /// Repository whose context every command runs in.
  final ProcessGitRepository repository;

  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitRevisions({required this.repository});

  @override
  Future<GitOid?> resolveRevision(String expression) async {
    if (readsAsOption(expression)) {
      // An expression that reads like an option names no revision.
      return null;
    }
    try {
      final GitRunResult result = await repository.runCommand(
        <String>['rev-parse', '--verify', '--quiet', expression],
      );
      return GitOid.tryParse(result.stdout.trim());
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException {
      // Exit code 1: nothing resolves to that expression.
      return null;
    }
  }

  @override
  Future<String> symbolicFullName(
    String rev, {
    bool abbreviated = false,
  }) async {
    refuseOptionLikeRevision(rev);
    // Verify first: without it rev-parse exits successfully and echoes a
    // name that resolves to nothing, so a refusal could not be recognized.
    try {
      await repository.runCommand(<String>['rev-parse', '--verify', rev]);
    } on GitCommandException catch (error) {
      throw unknownRevisionFailure(error, rev);
    }
    final GitRunResult result = await repository.runCommand(<String>[
      'rev-parse',
      '--symbolic-full-name',
      if (abbreviated) '--abbrev-ref',
      rev,
    ]);
    return result.stdout.trim();
  }
}
