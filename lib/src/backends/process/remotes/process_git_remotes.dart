import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_runner.dart';
import '../process_git_repository.dart';

/// [GitRemotes] implementation running git through the owning process
/// repository, so every command inherits the repository context — working
/// directory and environment variables — instead of talking to the runner
/// alone.
class ProcessGitRemotes implements GitRemotes {
  /// Repository whose context every command runs in.
  final ProcessGitRepository repository;

  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitRemotes({required this.repository});

  @override
  Future<List<String>> list() async {
    final GitRunResult result = await repository.runCommand(const <String>[
      'remote',
    ]);
    return const LineSplitter()
        .convert(result.stdout)
        .map((String name) => name.trim())
        .where((String name) => name.isNotEmpty)
        .toList();
  }

  @override
  Future<void> add(String name, String url) {
    return repository.runCommand(<String>['remote', 'add', '--', name, url]);
  }

  @override
  Future<void> remove(String name) {
    return repository.runCommand(<String>['remote', 'remove', '--', name]);
  }

  @override
  Future<void> rename(String name, String newName) {
    return repository
        .runCommand(<String>['remote', 'rename', '--', name, newName]);
  }

  @override
  Future<String?> getUrl(String name) async {
    try {
      final GitRunResult result = await repository.runCommand(
        <String>['remote', 'get-url', '--', name],
      );
      return result.stdout.trim();
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException catch (error) {
      if (_isNoSuchRemote(error)) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> setUrl(String name, String url) {
    return repository
        .runCommand(<String>['remote', 'set-url', '--', name, url]);
  }

  /// Whether git reported that the remote does not exist (`get-url`, and
  /// every other refusal stays an error).
  static bool _isNoSuchRemote(GitCommandException error) {
    return error.stderr.toLowerCase().contains('no such remote');
  }
}
