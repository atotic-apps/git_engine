import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/src/backends/process/process_git_runner.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

export 'process_backend_types.dart';

/// Identity every test repository is configured with.
const String testUserName = 'Test Engine User';
const String testUserEmail = 'test-engine@example.com';

/// Creates an isolated throwaway git repository and registers its deletion
/// with [addTearDown].
///
/// The repository is sealed off from the machine's git configuration:
/// `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL` points at an empty file, the
/// initial branch is `main`, and `core.autocrlf=false` plus a fixed identity
/// are set in the local configuration.
Future<TestRepository> createTestRepository() async {
  final TestRepository repository = await TestRepository.create();
  addTearDown(repository.dispose);
  return repository;
}

/// A temporary sandbox holding one git repository, with direct access to the
/// underlying [runner] so tests can prepare state through raw git commands.
final class TestRepository {
  /// Sandbox root; the repository lives in [directory], everything else
  /// (global config file, scratch files) lives next to it.
  final Directory sandbox;

  /// The git repository itself.
  final Directory directory;

  /// Runner preconfigured with the isolated git environment.
  final ProcessGitRunner runner;

  TestRepository._({
    required this.sandbox,
    required this.directory,
    required this.runner,
  });

  /// Creates a new sandbox with an initialized repository.
  static Future<TestRepository> create() async {
    final Directory sandbox =
        await Directory.systemTemp.createTemp('git_engine_test_');
    final File globalConfig = File(join(sandbox.path, 'gitconfig-global'));
    final Directory repository = Directory(join(sandbox.path, 'repo'));
    try {
      await globalConfig.create();
      await repository.create(recursive: true);
      final TestRepository testRepository = TestRepository._(
        sandbox: sandbox,
        directory: repository,
        runner: ProcessGitRunner(
          globalEnvironment: <String, String>{
            'GIT_CONFIG_NOSYSTEM': '1',
            'GIT_CONFIG_GLOBAL': globalConfig.path,
          },
        ),
      );
      await testRepository.runGit(
        const <String>['-c', 'init.defaultBranch=main', 'init'],
      );
      await testRepository.runGit(
        const <String>['config', 'core.autocrlf', 'false'],
      );
      await testRepository.runGit(
        const <String>['config', 'user.name', testUserName],
      );
      await testRepository.runGit(
        const <String>['config', 'user.email', testUserEmail],
      );
      return testRepository;
    } catch (_) {
      await deleteRecursively(sandbox);
      rethrow;
    }
  }

  /// Runs git inside the repository with the isolated environment.
  Future<GitRunResult> runGit(
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Uint8List? stdin,
    Duration? timeout,
    int? maxOutputBytes,
  }) {
    return runner.run(GitRunRequest(
      arguments: arguments,
      workingDirectory: workingDirectory ?? directory.path,
      environment: environment ?? const <String, String>{},
      stdin: stdin,
      timeout: timeout,
      maxOutputBytes: maxOutputBytes,
    ));
  }

  /// Writes [content] into a file relative to the repository, creating parent
  /// directories as needed. Strings are encoded as UTF-8.
  File writeFile(String relativePath, Object content) {
    final File file = File(join(directory.path, relativePath));
    file.parent.createSync(recursive: true);
    final List<int> bytes =
        content is String ? utf8.encode(content) : content as List<int>;
    file.writeAsBytesSync(bytes);
    return file;
  }

  /// A scratch file living in the sandbox, outside the repository.
  File sandboxFile(String name) => File(join(sandbox.path, name));

  /// Deletes the whole sandbox, retrying a few times because Windows may
  /// still hold file locks right after git exits.
  Future<void> dispose() async {
    await deleteRecursively(sandbox);
  }

  static Future<void> deleteRecursively(Directory directory) async {
    for (var attempt = 0;; attempt++) {
      try {
        await directory.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 4) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  /// Joins [base] and [relative] with the platform separator.
  static String join(String base, String relative) {
    final String separator = Platform.pathSeparator;
    return base.endsWith(separator)
        ? '$base$relative'
        : '$base$separator$relative';
  }
}
