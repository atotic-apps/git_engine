import 'dart:io';
import 'dart:typed_data';

import 'git_file_system.dart';

/// [GitFileSystem] over the file system of the machine, through `dart:io`.
///
/// It is the default the process backend falls back to; tests hand an
/// in-memory file system to the engine and the repositories instead.
class ProcessGitFileSystem implements GitFileSystem {
  /// Creates a file system reading and writing the machine's disk.
  const ProcessGitFileSystem();

  @override
  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await File(path).writeAsBytes(bytes);
  }

  @override
  Future<bool> exists(String path) async {
    return await FileSystemEntity.type(path) != FileSystemEntityType.notFound;
  }

  @override
  Future<bool> isDirectory(String path) async {
    return await FileSystemEntity.type(path) == FileSystemEntityType.directory;
  }

  @override
  Future<List<GitFileSystemEntry>> list(String path) async {
    final List<FileSystemEntity> entities =
        await Directory(path).list(followLinks: false).toList();
    final List<GitFileSystemEntry> entries = <GitFileSystemEntry>[
      for (final FileSystemEntity entity in entities)
        GitFileSystemEntry(
          name: _baseName(entity.path),
          isDirectory: entity is Directory,
        ),
    ];
    entries.sort(
      (GitFileSystemEntry first, GitFileSystemEntry second) =>
          first.name.compareTo(second.name),
    );
    return entries;
  }

  @override
  Future<void> createDirectory(String path, {bool recursive = false}) {
    return Directory(path).create(recursive: recursive);
  }

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) {
    return Directory(path).delete(recursive: recursive);
  }

  @override
  Future<String> createTemporaryDirectory(String prefix) async {
    final Directory directory = await Directory.systemTemp.createTemp(prefix);
    return directory.path;
  }

  @override
  Future<bool> isLink(String path) async {
    return await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.link;
  }

  @override
  Future<String> resolveSymbolicLinks(String path) {
    return File(path).resolveSymbolicLinks();
  }

  @override
  String absolutePath(String path) => Directory(path).absolute.path;

  /// File name of [path], without its directory.
  static String _baseName(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final int slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }
}
