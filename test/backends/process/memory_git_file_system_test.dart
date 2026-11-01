import 'dart:convert';

import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'git_file_system_contract.dart';

void main() {
  group('MemoryGitFileSystem', () {
    group('shared contract', () {
      defineGitFileSystemContract(() async {
        final MemoryGitFileSystem fileSystem = MemoryGitFileSystem();
        fileSystem.seedDirectory('/repo');
        return FileSystemCase(
          fileSystem: fileSystem,
          root: '/repo',
          separator: '/',
        );
      });
    });

    group('in-memory behavior', () {
      late MemoryGitFileSystem fileSystem;

      setUp(() {
        fileSystem = MemoryGitFileSystem();
      });

      test('the root exists as a directory', () async {
        expect(await fileSystem.exists('/'), isTrue);
        expect(await fileSystem.isDirectory('/'), isTrue);
        expect(await fileSystem.list('/'), isEmpty);
      });

      test('seedFile creates the missing parent directories', () async {
        fileSystem.seedFile('/deeply/nested/notes.txt', utf8.encode('kept\n'));

        expect(
          await fileSystem.readBytes('/deeply/nested/notes.txt'),
          utf8.encode('kept\n'),
        );
        expect(
          (await fileSystem.list('/deeply')).single.name,
          'nested',
        );
      });

      test('writeBytes refuses a missing parent', () async {
        await expectLater(
          fileSystem.writeBytes('/lonely/notes.txt', utf8.encode('kept\n')),
          throwsA(anything),
        );
        expect(fileSystem.hasFile('/lonely/notes.txt'), isFalse);
      });

      test('seeds normalize Windows separators, dots and dot-dots', () async {
        fileSystem.seedFile('/repo\\sub\\..\\notes.txt', utf8.encode('a\n'));

        expect(fileSystem.hasFile('/repo/notes.txt'), isTrue);
        expect(fileSystem.hasFile('/repo/sub/notes.txt'), isFalse);
      });

      test('deleteDirectory refuses the root', () async {
        await expectLater(
          fileSystem.deleteDirectory('/'),
          throwsA(anything),
        );
      });

      test('deleteDirectory recursive removes the nested files', () async {
        fileSystem.seedFile('/store/inner/notes.txt', utf8.encode('kept\n'));

        await fileSystem.deleteDirectory('/store', recursive: true);

        expect(fileSystem.hasDirectory('/store'), isFalse);
        expect(fileSystem.hasFile('/store/inner/notes.txt'), isFalse);
      });

      test('createTemporaryDirectory names are unique and deterministic',
          () async {
        final String first =
            await fileSystem.createTemporaryDirectory('patch_');
        final String second =
            await fileSystem.createTemporaryDirectory('patch_');

        expect(first, '/tmp/patch_1');
        expect(second, '/tmp/patch_2');
      });

      test('absolutePath roots relative paths and resolves dot-dots', () async {
        expect(fileSystem.absolutePath('name'), '/name');
        expect(fileSystem.absolutePath('/a/./b/../c'), '/a/c');
        expect(fileSystem.absolutePath('a/../../b'), '/b');
      });

      test('inspection helpers see the state a call left behind', () async {
        fileSystem.seedDirectory('/repo');
        await fileSystem.writeBytes('/repo/notes.txt', utf8.encode('kept\n'));

        expect(fileSystem.hasDirectory('/repo'), isTrue);
        expect(fileSystem.hasFile('/repo/notes.txt'), isTrue);
        expect(
            fileSystem.fileContent('/repo/notes.txt'), utf8.encode('kept\n'));
        expect(fileSystem.fileContent('/repo/absent.txt'), isNull);
      });
    });
  });
}
