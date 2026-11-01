import 'dart:io';

import 'package:git_engine/testing.dart';

import 'test_repository.dart';

export 'process_backend_types.dart';

/// A temporary sandbox holding one bare git repository that carries a
/// commit, with direct access to the underlying [runner] so tests can
/// inspect the served state through raw git commands.
///
/// Create it with [BareTestRepository.create] and dispose of it with
/// [dispose] — from [tearDownAll] at the top of a suite, or from
/// [addTearDown] inside a test.
final class BareTestRepository {
  /// Sandbox root; the bare repository lives in [directory].
  final Directory sandbox;

  /// The bare git repository.
  final Directory directory;

  /// Runner preconfigured with the isolated git environment.
  final ProcessGitRunner runner;

  /// The backend view of the bare repository a resolver returns.
  final ProcessGitFileBareRepository repository;

  /// Object name `HEAD` resolves to in the bare repository.
  final String headOid;

  BareTestRepository._({
    required this.sandbox,
    required this.directory,
    required this.runner,
    required this.repository,
    required this.headOid,
  });

  /// Creates a new sandbox with a bare repository serving one commit.
  static Future<BareTestRepository> create() async {
    final Directory sandbox =
        await Directory.systemTemp.createTemp('git_engine_bare_test_');
    try {
      final File globalConfig = File(TestRepository.join(
        sandbox.path,
        'gitconfig-global',
      ));
      await globalConfig.create();
      final String workPath = TestRepository.join(sandbox.path, 'work');
      final String barePath = TestRepository.join(sandbox.path, 'served.git');
      final ProcessGitRunner runner = ProcessGitRunner(
        globalEnvironment: <String, String>{
          'GIT_CONFIG_NOSYSTEM': '1',
          'GIT_CONFIG_GLOBAL': globalConfig.path,
        },
      );
      Future<GitRunResult> git(
        List<String> arguments, {
        String? workingDirectory,
      }) {
        return runner.run(GitRunRequest(
          arguments: arguments,
          workingDirectory: workingDirectory,
        ));
      }

      await git(<String>[
        '-c',
        'init.defaultBranch=main',
        'init',
        '--',
        workPath,
      ]);
      await git(const <String>['config', 'user.name', testUserName],
          workingDirectory: workPath);
      await git(const <String>['config', 'user.email', testUserEmail],
          workingDirectory: workPath);
      await File(TestRepository.join(workPath, 'served.txt'))
          .writeAsString('served content\n');
      await git(const <String>['add', '--', 'served.txt'],
          workingDirectory: workPath);
      await git(const <String>['commit', '-m', 'Serve me'],
          workingDirectory: workPath);
      await git(<String>['clone', '--bare', '--', workPath, barePath]);
      final GitRunResult head = await git(
        const <String>['rev-parse', 'HEAD'],
        workingDirectory: barePath,
      );
      return BareTestRepository._(
        sandbox: sandbox,
        directory: Directory(barePath),
        runner: runner,
        repository: ProcessGitFileBareRepository(
          runner: runner,
          context: GitRepositoryContext(path: barePath),
        ),
        headOid: head.stdout.trim(),
      );
    } catch (_) {
      await BareTestRepository._deleteSandbox(sandbox);
      rethrow;
    }
  }

  /// Deletes the whole sandbox, retrying a few times because Windows may
  /// still hold file locks right after git exits.
  Future<void> dispose() => _deleteSandbox(sandbox);

  static Future<void> _deleteSandbox(Directory sandbox) async {
    for (var attempt = 0;; attempt++) {
      try {
        await sandbox.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 4) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}
