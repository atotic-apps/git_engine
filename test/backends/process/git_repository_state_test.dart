@Tags(['git'])
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/test_repository.dart';
import 'support/remote_test_support.dart';

void main() {
  group('a repository with a work tree', () {
    late TestRepository repo;
    late ProcessGitWorkingRepository repository;

    setUp(() async {
      repo = await createTestRepository();
      repository = await openAt(repo) as ProcessGitWorkingRepository;
    });

    test('its git directory is the .git directory', () async {
      expect(
        sameDirectory(
          await repository.gitDir(),
          '${repo.directory.path}${Platform.pathSeparator}.git',
        ),
        isTrue,
      );
    });

    test('its work tree root is the opened directory', () async {
      final String top = await repository.toplevel();

      expect(sameDirectory(top, repo.directory.path), isTrue);
    });
  });

  group('a bare repository', () {
    late TestRepository repo;
    late ProcessGitFileBareRepository repository;
    late String path;

    setUp(() async {
      repo = await createTestRepository();
      path = await initBareByRunner(repo, 'bare-state.git');
      repository =
          await openAt(repo, directory: path) as ProcessGitFileBareRepository;
    });

    test('its git directory is its own directory', () async {
      expect(sameDirectory(await repository.gitDir(), path), isTrue);
    });
  });
}
