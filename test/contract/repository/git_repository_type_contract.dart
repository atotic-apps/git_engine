import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the promises the repository hierarchy makes about its types.
///
/// The suite runs only on backends whose repositories are stored on disk: it
/// checks the concrete file-backed types and the index view they expose. The
/// same cases therefore run unchanged on every file-backed backend.
void defineGitRepositoryTypeContract(BackendFactory factory) {
  group('repository type promises', () {
    test('a working repository is an indexed file-backed working repository',
        () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();

      expect(repository, isA<GitWorkingRepository>());
      expect(repository, isA<GitIndexedRepository>());
      expect(repository, isA<GitFileRepository>());
      expect(repository, isA<GitRepository>());
      expect(repository, isNot(isA<GitBareRepository>()));
      expect(repository.patches, isA<GitWorkingPatches>());
    });

    test('a bare repository is a bare file repository and never working',
        () async {
      final GitFileBareRepository repository =
          await factory.createBareRepository();

      expect(repository, isA<GitBareRepository>());
      expect(repository, isA<GitFileRepository>());
      expect(repository, isA<GitRepository>());
      expect(repository, isNot(isA<GitWorkingRepository>()));
      expect(repository, isNot(isA<GitIndexedRepository>()));
      expect(repository.patches, isA<GitPatches>());
      expect(repository.patches, isNot(isA<GitIndexedPatches>()));
    });

    test('a temporary index of a working repository stays a working repository',
        () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();

      await repository.withTemporaryIndex<void>(
        (GitWorkingRepository indexed) async {
          expect(indexed, isA<GitWorkingRepository>());
          expect(indexed, isA<GitIndexedRepository>());
          expect(indexed, isA<GitFileRepository>());
          expect(indexed.patches, isA<GitWorkingPatches>());
          expect(await indexed.toplevel(), isNotEmpty);
        },
      );
    });

    test(
        'a temporary index of a bare repository stays indexed and never '
        'working', () async {
      final GitFileBareRepository repository =
          await factory.createBareRepository();

      await repository.withTemporaryIndex<void>(
        (GitIndexedRepository indexed) async {
          expect(indexed, isA<GitIndexedRepository>());
          expect(indexed, isA<GitFileRepository>());
          expect(indexed, isNot(isA<GitWorkingRepository>()));
          expect(indexed, isNot(isA<GitBareRepository>()));
          expect(indexed.patches, isA<GitIndexedPatches>());
          expect(indexed.patches, isNot(isA<GitWorkingPatches>()));
        },
      );
    });

    test('a temporary index of a bare repository never touches its own index',
        () async {
      final GitFileBareRepository repository =
          await factory.createBareRepository();
      final String gitDir = await repository.gitDir();
      final File ownIndex = File('$gitDir${Platform.pathSeparator}index');
      const List<int> sentinel = <int>[1, 2, 3, 4];
      expect(ownIndex.existsSync(), isFalse);
      ownIndex.writeAsBytesSync(sentinel);

      await repository.withTemporaryIndex<void>(
        (GitIndexedRepository indexed) => indexed.index.writeTree(),
      );

      expect(ownIndex.existsSync(), isTrue);
      expect(ownIndex.readAsBytesSync(), sentinel);
    });
  });
}
