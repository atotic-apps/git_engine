import 'dart:convert';

import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

/// One [GitFileSystem] under test, with the absolute [root] its paths live
/// under and the [separator] its spelling joins with.
final class FileSystemCase {
  /// Creates a case around [fileSystem], rooted at [root].
  const FileSystemCase({
    required this.fileSystem,
    required this.root,
    required this.separator,
  });

  /// The implementation under test.
  final GitFileSystem fileSystem;

  /// Absolute root every path of the case is built under.
  final String root;

  /// Separator between the segments of a path.
  final String separator;

  /// Joins [name] under [root].
  String path(String name) => '$root$separator$name';
}

/// Declares the contract every [GitFileSystem] implementation satisfies.
///
/// The suite builds its paths from the absolute root of the case, so the
/// same assertions run against the in-memory file system and against the
/// `dart:io` one, on any machine.
void defineGitFileSystemContract(
  Future<FileSystemCase> Function() createCase,
) {
  group('GitFileSystem', () {
    late FileSystemCase fs;

    setUp(() async {
      fs = await createCase();
    });

    test('a missing path neither exists nor is a directory', () async {
      final String absent = fs.path('absent');

      expect(await fs.fileSystem.exists(absent), isFalse);
      expect(await fs.fileSystem.isDirectory(absent), isFalse);
    });

    test('reads back the bytes it wrote', () async {
      final String file = fs.path('notes.txt');

      await fs.fileSystem.writeBytes(file, utf8.encode('kept\n'));

      expect(await fs.fileSystem.exists(file), isTrue);
      expect(await fs.fileSystem.isDirectory(file), isFalse);
      expect(await fs.fileSystem.readBytes(file), utf8.encode('kept\n'));
    });

    test('writing replaces the previous bytes', () async {
      final String file = fs.path('notes.txt');
      await fs.fileSystem.writeBytes(file, utf8.encode('first\n'));

      await fs.fileSystem.writeBytes(file, utf8.encode('second\n'));

      expect(await fs.fileSystem.readBytes(file), utf8.encode('second\n'));
    });

    test('reading a missing file throws', () async {
      await expectLater(
        fs.fileSystem.readBytes(fs.path('absent.txt')),
        throwsA(anything),
      );
    });

    test('lists the children of a directory sorted by name, with kinds',
        () async {
      final String separator = fs.separator;
      final String directory = fs.path('store');
      await fs.fileSystem.createDirectory(directory);
      await fs.fileSystem.createDirectory('$directory${separator}inner');
      await fs.fileSystem.writeBytes(
        '$directory${separator}notes.txt',
        utf8.encode('kept\n'),
      );
      await fs.fileSystem.writeBytes(
        '$directory${separator}z.log',
        utf8.encode(''),
      );

      final List<GitFileSystemEntry> entries =
          await fs.fileSystem.list(directory);

      expect(
        entries.map((GitFileSystemEntry entry) => entry.name),
        <String>['inner', 'notes.txt', 'z.log'],
      );
      expect(
        entries.map((GitFileSystemEntry entry) => entry.isDirectory),
        <bool>[true, false, false],
      );
    });

    test('listing a missing directory throws', () async {
      await expectLater(
        fs.fileSystem.list(fs.path('absent')),
        throwsA(anything),
      );
    });

    test('creates nested directories recursively', () async {
      final String nested =
          fs.path('deeply${fs.separator}nested${fs.separator}directory');

      await fs.fileSystem.createDirectory(nested, recursive: true);

      expect(await fs.fileSystem.isDirectory(nested), isTrue);
    });

    test('creating an existing directory recursively is accepted', () async {
      final String directory = fs.path('store');
      await fs.fileSystem.createDirectory(directory, recursive: true);

      await fs.fileSystem.createDirectory(directory, recursive: true);

      expect(await fs.fileSystem.isDirectory(directory), isTrue);
    });

    test('creating a directory without its parent throws', () async {
      await expectLater(
        fs.fileSystem.createDirectory(
          fs.path('missing${fs.separator}child'),
        ),
        throwsA(anything),
      );
      expect(
        await fs.fileSystem.exists(fs.path('missing${fs.separator}child')),
        isFalse,
      );
    });

    test('deletes an empty directory', () async {
      final String directory = fs.path('empty');
      await fs.fileSystem.createDirectory(directory);

      await fs.fileSystem.deleteDirectory(directory);

      expect(await fs.fileSystem.exists(directory), isFalse);
      expect(await fs.fileSystem.isDirectory(directory), isFalse);
    });

    test('deleting a directory that still holds entries throws', () async {
      final String directory = fs.path('store');
      final String file = fs.path('store${fs.separator}notes.txt');
      await fs.fileSystem.createDirectory(directory);
      await fs.fileSystem.writeBytes(file, utf8.encode('kept\n'));

      await expectLater(
        fs.fileSystem.deleteDirectory(directory),
        throwsA(anything),
      );

      expect(await fs.fileSystem.isDirectory(directory), isTrue);
      expect(await fs.fileSystem.readBytes(file), utf8.encode('kept\n'),
          reason: 'the refused deletion leaves the content untouched');
    });

    test('deletes a directory recursively with its content', () async {
      final String directory = fs.path('store');
      await fs.fileSystem.createDirectory(
        fs.path('store${fs.separator}inner'),
        recursive: true,
      );
      await fs.fileSystem.writeBytes(
        fs.path('store${fs.separator}notes.txt'),
        utf8.encode('kept\n'),
      );

      await fs.fileSystem.deleteDirectory(directory, recursive: true);

      expect(await fs.fileSystem.exists(directory), isFalse);
      expect(
        await fs.fileSystem.exists(
          fs.path('store${fs.separator}inner'),
        ),
        isFalse,
      );
    });

    test('createTemporaryDirectory returns fresh existing directories',
        () async {
      final String first = await fs.fileSystem.createTemporaryDirectory(
        'contract_',
      );
      final String second = await fs.fileSystem.createTemporaryDirectory(
        'contract_',
      );

      expect(first, isNot(second));
      expect(await fs.fileSystem.isDirectory(first), isTrue);
      expect(await fs.fileSystem.isDirectory(second), isTrue);

      final String marker = '$first${fs.separator}marker';
      await fs.fileSystem.writeBytes(marker, utf8.encode('kept\n'));
      expect(await fs.fileSystem.readBytes(marker), utf8.encode('kept\n'));
    });
  });
}
