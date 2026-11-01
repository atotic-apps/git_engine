@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/test_repository.dart';

void main() {
  group('ProcessGitEngine', () {
    test('open binds a repository to an absolute path and runs commands',
        () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitEngine engine = ProcessGitEngine(runner: repo.runner);

      final ProcessGitRepository opened =
          await engine.open(repo.directory.path) as ProcessGitRepository;

      expect(Directory(opened.path).isAbsolute, isTrue);
      expect(
        opened.context.environment,
        <String, String>{'GIT_LITERAL_PATHSPECS': '1'},
      );
      final GitRunResult inside = await opened.runCommand(
        const <String>['rev-parse', '--is-inside-work-tree'],
      );
      expect(inside.stdout.trim(), 'true');
    });

    test('open reads the repository kind and fails outside a repository',
        () async {
      final Directory plain =
          await Directory.systemTemp.createTemp('git_engine_norepo_');
      addTearDown(() => TestRepository.deleteRecursively(plain));
      final ProcessGitEngine engine = ProcessGitEngine();

      await expectLater(
        engine.open(plain.path),
        throwsA(isA<GitNotARepositoryException>()),
      );
    });
  });
}
