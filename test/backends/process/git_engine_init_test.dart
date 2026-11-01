@Tags(['git'])
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/test_repository.dart';
import 'support/remote_test_support.dart';

void main() {
  group('init with a work tree', () {
    late TestRepository repo;
    late ProcessGitWorkingRepository repository;
    late String path;

    setUp(() async {
      repo = await createTestRepository();
      path = await missingDirectory(repo, 'brand new repo');
      repository =
          await engineAt(repo).init(path) as ProcessGitWorkingRepository;
    });

    test('opens the created repository', () async {
      final String top = await repository.toplevel();

      expect(sameDirectory(top, path), isTrue);
    });

    test('the git directory sits in a .git beside the work tree', () async {
      final String gitDir = await repository.gitDir();
      final String expected = '$path${Platform.pathSeparator}.git';

      expect(sameDirectory(gitDir, expected), isTrue);
      expect(fileExistsIn(gitDir, 'HEAD'), isTrue);
    });

    test('a path with spaces and accents', () async {
      final String accented =
          await missingDirectory(repo, 'un dossier éàç à créer');
      final ProcessGitWorkingRepository opened =
          await engineAt(repo).init(accented) as ProcessGitWorkingRepository;

      final String top = await opened.toplevel();
      final String gitDir = await opened.gitDir();

      expect(sameDirectory(top, accented), isTrue);
      expect(fileExistsIn(gitDir, 'HEAD'), isTrue);
    });

    test('a path spelled like an option still names the directory', () async {
      final String weirdPath = await missingDirectory(repo, '-dashy');
      final ProcessGitWorkingRepository opened =
          await engineAt(repo).init(weirdPath) as ProcessGitWorkingRepository;

      final String top = await opened.toplevel();

      expect(sameDirectory(top, weirdPath), isTrue);
    });
  });

  group('bare init', () {
    late TestRepository repo;
    late ProcessGitFileBareRepository repository;
    late String path;

    setUp(() async {
      repo = await createTestRepository();
      path = await missingDirectory(repo, 'bare-repository.git');
      repository = await engineAt(repo).initBare(
        path,
        initialBranch: 'start',
      ) as ProcessGitFileBareRepository;
    });

    test('opens the bare repository', () async {
      final String gitDir = await repository.gitDir();

      expect(sameDirectory(gitDir, path), isTrue);
    });
  });
}
