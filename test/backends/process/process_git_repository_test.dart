@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../../support/directory_identity.dart';
import 'support/test_repository.dart';

void main() {
  group('ProcessGitRepository.runCommand', () {
    test('runs inside the repository directory', () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitEngine engine = ProcessGitEngine(runner: repo.runner);
      final ProcessGitRepository repository =
          await engine.open(repo.directory.path) as ProcessGitRepository;

      final GitRunResult result = await repository.runCommand(
        const <String>['rev-parse', '--show-toplevel'],
      );

      expect(sameDirectory(result.stdout.trim(), repo.directory.path), isTrue);
    });
  });

  group('withIndexFile', () {
    test('routes commands to the alternate index without touching the original',
        () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitEngine engine = ProcessGitEngine(runner: repo.runner);
      final ProcessGitRepository repository =
          await engine.open(repo.directory.path) as ProcessGitRepository;

      repo.writeFile('a.txt', 'a\n');
      await repository.runCommand(const <String>['add', 'a.txt']);
      await repository.runCommand(const <String>['commit', '-m', 'add a']);
      repo.writeFile('b.txt', 'b\n');

      final String altIndexPath = repo.sandboxFile('alt-index').path;
      final ProcessGitRepository indexed =
          repository.withIndexFile(altIndexPath);

      expect(
        indexed.context.environment['GIT_INDEX_FILE'],
        altIndexPath,
      );

      await indexed.runCommand(const <String>['add', '-N', 'b.txt']);

      final GitRunResult indexedFiles =
          await indexed.runCommand(const <String>['ls-files', '--cached']);
      expect(indexedFiles.stdout, contains('b.txt'));

      final GitRunResult originalFiles =
          await repository.runCommand(const <String>['ls-files', '--cached']);
      expect(originalFiles.stdout, contains('a.txt'));
      expect(originalFiles.stdout, isNot(contains('b.txt')));

      final GitRunResult status =
          await repository.runCommand(const <String>['status', '--porcelain']);
      expect(status.stdout, '?? b.txt\n');

      expect(File(altIndexPath).existsSync(), isTrue,
          reason: 'the alternate index must be a real file on disk');
    });

    test('views stack: the index view keeps its own environment layers',
        () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitEngine engine = ProcessGitEngine(runner: repo.runner);
      final ProcessGitRepository repository =
          await engine.open(repo.directory.path) as ProcessGitRepository;

      final GitRepositoryContext base = repository.context;
      final GitRepositoryContext withIndex = repository
          .withIndexFile(repo.sandboxFile('alt-index').path)
          .withEnvironment(const <String, String>{'ENGINE_LAYER': '1'}).context;

      expect(base.environment.containsKey('GIT_INDEX_FILE'), isFalse);
      expect(withIndex.environment['ENGINE_LAYER'], '1');
      expect(withIndex.environment.containsKey('GIT_INDEX_FILE'), isTrue);
    });
  });

  group('withEnvironment', () {
    test('overrides the runner global environment without mutating the view',
        () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitRunner runner = ProcessGitRunner(
        globalEnvironment: const <String, String>{
          'GIT_AUTHOR_NAME': 'Global User',
          'GIT_AUTHOR_EMAIL': 'global@example.com',
        },
      );
      final ProcessGitEngine engine = ProcessGitEngine(runner: runner);
      final ProcessGitRepository repository =
          await engine.open(repo.directory.path) as ProcessGitRepository;

      final GitRunResult fromGlobal = await repository.runCommand(
        const <String>['var', 'GIT_AUTHOR_IDENT'],
      );
      expect(fromGlobal.stdout, startsWith('Global User <global@example.com>'));

      final ProcessGitRepository overridden = repository.withEnvironment(
        const <String, String>{
          'GIT_AUTHOR_NAME': 'Local User',
          'GIT_AUTHOR_EMAIL': 'local@example.com',
        },
      );

      final GitRunResult fromLocal = await overridden.runCommand(
        const <String>['var', 'GIT_AUTHOR_IDENT'],
      );
      expect(fromLocal.stdout, startsWith('Local User <local@example.com>'));

      final GitRunResult unchanged = await repository.runCommand(
        const <String>['var', 'GIT_AUTHOR_IDENT'],
      );
      expect(
        unchanged.stdout,
        startsWith('Global User <global@example.com>'),
      );
    });

    test('feeds commits through a GitIdentity', () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitEngine engine = ProcessGitEngine(runner: repo.runner);
      final ProcessGitRepository repository =
          await engine.open(repo.directory.path) as ProcessGitRepository;

      final GitIdentity identity = GitIdentity(
        name: 'Ida Identity',
        email: 'ida@example.com',
      );
      repo.writeFile('a.txt', 'a\n');
      await repository.runCommand(const <String>['add', 'a.txt']);
      await repository
          .withEnvironment(identity.toEnvironment())
          .runCommand(const <String>['commit', '-m', 'authored by identity']);

      final GitRunResult author = await repository.runCommand(
        const <String>['log', '-1', '--format=%an <%ae>'],
      );
      expect(author.stdout.trim(), 'Ida Identity <ida@example.com>');
    });
  });

  group('pruneWorktrees', () {
    test('forgets a work tree whose directory was deleted', () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitEngine engine = ProcessGitEngine(runner: repo.runner);
      repo.writeFile('a.txt', 'a\n');
      await repo.runGit(const <String>['add', '--', 'a.txt']);
      await repo.runGit(const <String>['commit', '-m', 'initial']);
      final ProcessGitRepository repository =
          await engine.open(repo.directory.path) as ProcessGitRepository;
      final String linked = TestRepository.join(repo.sandbox.path, 'linked');
      await repo.runGit(<String>[
        'worktree',
        'add',
        '-b',
        'linked-branch',
        linked,
      ]);
      expect(
        (await repo.runGit(<String>['worktree', 'list', '--porcelain'])).stdout,
        contains('linked-branch'),
      );

      await TestRepository.deleteRecursively(Directory(linked));
      await repository.pruneWorktrees();

      expect(
        (await repo.runGit(<String>['worktree', 'list', '--porcelain'])).stdout,
        isNot(contains('linked-branch')),
      );
    });
  });
}
