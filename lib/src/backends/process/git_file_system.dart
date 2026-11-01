import 'dart:typed_data';

/// One entry of a listed directory.
/// {@category Testing}
final class GitFileSystemEntry {
  /// Creates an entry named [name]; [isDirectory] tells a directory from a
  /// file.
  const GitFileSystemEntry({
    required this.name,
    required this.isDirectory,
  });

  /// File name of the entry, without its directory.
  final String name;

  /// Whether the entry is a directory.
  final bool isDirectory;
}

/// The file operations the process backend performs, injectable so they can
/// run without a disk.
///
/// It is the seam behind every disk access of the backend: repository
/// creation guards, git directory files, conflict markers, patches and
/// temporary indexes either delegate to the machine's file system or, in
/// tests, keep the files in memory.
///
/// Paths are handed over as they are; [absolutePath] turns them absolute.
/// Failing operations throw, and the concrete error type is left to the
/// implementation.
/// {@category Testing}
abstract interface class GitFileSystem {
  /// Reads the bytes of the file at [path].
  ///
  /// Throws when nothing, or a directory, sits at [path].
  Future<Uint8List> readBytes(String path);

  /// Writes [bytes] to the file at [path], creating or replacing it.
  ///
  /// The parent directory must exist; throws when it does not.
  Future<void> writeBytes(String path, List<int> bytes);

  /// Whether anything — a file or a directory — exists at [path].
  Future<bool> exists(String path);

  /// Whether a directory exists at [path]. A file at [path] yields false.
  Future<bool> isDirectory(String path);

  /// Lists the direct children of the directory at [path], sorted by name.
  ///
  /// Throws when [path] is absent or names a file.
  Future<List<GitFileSystemEntry>> list(String path);

  /// Creates a directory at [path].
  ///
  /// With [recursive], missing parent directories are created and an
  /// existing directory is accepted. Without it, the parent must exist and
  /// an existing directory throws.
  Future<void> createDirectory(String path, {bool recursive = false});

  /// Deletes the directory at [path].
  ///
  /// With [recursive], its content goes with it. Without it, the directory
  /// must be empty. Throws when [path] is absent or, without [recursive],
  /// still holds entries.
  Future<void> deleteDirectory(String path, {bool recursive = false});

  /// Creates a fresh empty directory for temporary use and returns its
  /// absolute path. Two calls never return the same path.
  Future<String> createTemporaryDirectory(String prefix);

  /// Whether a symbolic link or a Windows junction sits at [path], without
  /// following it.
  Future<bool> isLink(String path);

  /// Resolves every symbolic link and Windows junction in [path] and returns
  /// the absolute path it designates.
  ///
  /// Throws when [path] does not exist or cannot be resolved.
  Future<String> resolveSymbolicLinks(String path);

  /// Returns [path] as an absolute path, resolving relative paths against
  /// the implementation's current directory.
  String absolutePath(String path);
}
