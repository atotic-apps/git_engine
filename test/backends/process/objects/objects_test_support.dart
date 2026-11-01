import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';

export '../support/process_backend_types.dart';

/// Opens the repository — or the sandbox directory [directory] — through the
/// same runner the test state was prepared with.
Future<ProcessGitRepository> openRepository(
  TestRepository repo, {
  String? directory,
}) async {
  final ProcessGitEngine engine = ProcessGitEngine(runner: repo.runner);
  return await engine.open(directory ?? repo.directory.path)
      as ProcessGitRepository;
}

/// Object name `HEAD` currently resolves to.
Future<String> headOid(TestRepository repo) async {
  return (await repo.runGit(<String>['rev-parse', 'HEAD'])).stdout.trim();
}

/// Object name of [rev].
Future<String> oidOf(TestRepository repo, String rev) async {
  return (await repo.runGit(<String>['rev-parse', rev])).stdout.trim();
}

/// Creates and commits [path] with [content]; returns the new commit.
Future<String> commitFile(
  TestRepository repo,
  String path,
  String content,
  String message,
) async {
  repo.writeFile(path, content);
  await repo.runGit(<String>['add', '--', path]);
  await repo.runGit(<String>['commit', '-m', message]);
  return headOid(repo);
}

/// Writes [content] as a blob into the object database and returns its name.
Future<GitOid> writeBlob(TestRepository repo, String content) async {
  final String oid = (await repo.runGit(
    <String>['hash-object', '-w', '--stdin'],
    stdin: Uint8List.fromList(utf8.encode(content)),
  ))
      .stdout
      .trim();
  return GitOid.parse(oid);
}

/// Clones the repository into a bare repository at the sandbox root; returns
/// its path.
Future<String> createBareClone(TestRepository repo, String name) async {
  final String path = TestRepository.join(repo.sandbox.path, name);
  await repo.runGit(
    <String>['clone', '--bare', '--', repo.directory.path, path],
    workingDirectory: repo.sandbox.path,
  );
  return path;
}

/// Runs a git command expected to fail and returns the failure.
Future<GitCommandException> failureOf(Future<Object?> action) async {
  try {
    await action;
  } on GitCommandException catch (error) {
    return error;
  }
  fail('expected the git command to fail');
}

/// One regular file of a tar archive.
class TarEntry {
  /// Path recorded in the archive.
  final String name;

  /// Bytes of the file.
  final Uint8List content;

  const TarEntry({required this.name, required this.content});

  /// Content decoded as UTF-8.
  String get text => utf8.decode(content);
}

/// Reads the regular files of an uncompressed tar archive.
///
/// Enough of the format for the archives git writes in tests: 512-byte
/// headers, octal sizes, an optional `ustar` prefix, and global or extended
/// headers skipped.
List<TarEntry> readTar(Uint8List bytes) {
  final List<TarEntry> entries = <TarEntry>[];
  int offset = 0;
  while (offset + 512 <= bytes.length) {
    final Uint8List header = Uint8List.sublistView(bytes, offset, offset + 512);
    final String name = _tarString(header, 0, 100);
    if (name.isEmpty) {
      break;
    }
    final int size = _tarOctal(header, 124, 12);
    final String type = _tarString(header, 156, 1);
    final String prefix = _tarString(header, 345, 155);
    final int contentStart = offset + 512;
    if (type == '0' || type == '\x00') {
      final String fullName = prefix.isEmpty ? name : '$prefix/$name';
      entries.add(TarEntry(
        name: fullName,
        content:
            Uint8List.sublistView(bytes, contentStart, contentStart + size),
      ));
    }
    offset = contentStart + ((size + 511) ~/ 512) * 512;
  }
  return entries;
}

String _tarString(Uint8List header, int start, int length) {
  final List<int> slice =
      header.sublist(start, start + length).takeWhile((int byte) {
    return byte != 0;
  }).toList();
  return utf8.decode(slice, allowMalformed: true);
}

int _tarOctal(Uint8List header, int start, int length) {
  final String text = _tarString(header, start, length).trim();
  return text.isEmpty ? 0 : int.parse(text, radix: 8);
}

/// Snapshot of a file's bytes, or null when it does not exist.
Uint8List? snapshot(String path) {
  final File file = File(path);
  return file.existsSync() ? file.readAsBytesSync() : null;
}
