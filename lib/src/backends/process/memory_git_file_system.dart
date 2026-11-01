import 'dart:typed_data';

import 'git_file_system.dart';

/// [GitFileSystem] kept entirely in memory, for tests without a disk.
///
/// Paths use the POSIX spelling: `/` separator, a single root at `/`, and
/// relative paths resolved against the root. `.` and `..` segments,
/// repeated separators and Windows separators are normalized on every call,
/// and `..` above the root stays at the root. Nothing is ever written to
/// the machine.
///
/// The [seedFile], [seedDirectory] and [seedLink] helpers prepare the state a
/// test starts from; the [fileContent], [hasFile] and [hasDirectory] helpers
/// let it assert the state a call left behind.
/// {@category Testing}
final class MemoryGitFileSystem implements GitFileSystem {
  final Map<String, Uint8List> _files = <String, Uint8List>{};
  final Set<String> _directories = <String>{'/'};
  final Map<String, String> _links = <String, String>{};
  int _temporaryDirectories = 0;

  /// Writes [bytes] to the file at [path], creating its missing parent
  /// directories, replacing whatever sits there.
  void seedFile(String path, List<int> bytes) {
    final String normalized = _normalize(path);
    _seedAncestorsOf(normalized);
    _directories.remove(normalized);
    _links.remove(normalized);
    _files[normalized] = Uint8List.fromList(bytes);
  }

  /// Creates the directory at [path], with its missing parent directories,
  /// replacing whatever sits there.
  void seedDirectory(String path) {
    final String normalized = _normalize(path);
    _seedAncestorsOf(normalized);
    _files.remove(normalized);
    _links.remove(normalized);
    _directories.add(normalized);
  }

  /// Creates a symbolic link at [path] pointing at [target], replacing
  /// whatever sits there.
  ///
  /// A [target] starting with `/` is absolute; anything else resolves against
  /// the directory holding the link.
  void seedLink(String path, String target) {
    final String normalized = _normalize(path);
    _seedAncestorsOf(normalized);
    _files.remove(normalized);
    _directories.remove(normalized);
    final String parent = _parentOf(normalized) ?? _root;
    _links[normalized] = target.startsWith('/')
        ? _normalize(target)
        : _normalize('$parent/$target');
  }

  /// The bytes of the file at [path], or null when it holds none.
  Uint8List? fileContent(String path) => _files[_normalize(path)];

  /// Whether a file sits at [path].
  bool hasFile(String path) => _files.containsKey(_normalize(path));

  /// Whether a directory sits at [path].
  bool hasDirectory(String path) => _directories.contains(_normalize(path));

  @override
  Future<Uint8List> readBytes(String path) async {
    final Uint8List? bytes = _files[_resolve(path)];
    if (bytes == null) {
      throw StateError('no file at "$path"');
    }
    return bytes;
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final String normalized = _resolve(path);
    if (!_directories.contains(_parentOf(normalized))) {
      throw StateError('no parent directory of "$path"');
    }
    _directories.remove(normalized);
    _files[normalized] = Uint8List.fromList(bytes);
  }

  @override
  Future<bool> exists(String path) async {
    final String normalized = _resolve(path);
    return _files.containsKey(normalized) || _directories.contains(normalized);
  }

  @override
  Future<bool> isDirectory(String path) async {
    return _directories.contains(_resolve(path));
  }

  @override
  Future<List<GitFileSystemEntry>> list(String path) async {
    final String normalized = _resolve(path);
    if (!_directories.contains(normalized)) {
      throw StateError('no directory at "$path"');
    }
    final List<GitFileSystemEntry> entries = <GitFileSystemEntry>[
      for (final String child in _childrenOf(normalized))
        GitFileSystemEntry(
          name: _baseName(child),
          isDirectory: _directories.contains(child),
        ),
    ];
    entries.sort(
      (GitFileSystemEntry first, GitFileSystemEntry second) =>
          first.name.compareTo(second.name),
    );
    return entries;
  }

  @override
  Future<void> createDirectory(String path, {bool recursive = false}) async {
    final String normalized = _normalize(path);
    if (_files.containsKey(normalized)) {
      throw StateError('a file already sits at "$path"');
    }
    if (_directories.contains(normalized)) {
      if (!recursive) {
        throw StateError('directory "$path" already exists');
      }
      return;
    }
    if (!recursive && !_directories.contains(_parentOf(normalized))) {
      throw StateError('no parent directory of "$path"');
    }
    _seedAncestorsOf(normalized);
    _directories.add(normalized);
  }

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) async {
    final String normalized = _normalize(path);
    if (normalized == _root) {
      throw StateError('the root directory cannot be deleted');
    }
    if (!_directories.contains(normalized)) {
      throw StateError('no directory at "$path"');
    }
    final List<String> descendants = _descendantsOf(normalized);
    if (!recursive && descendants.isNotEmpty) {
      throw StateError('directory "$path" is not empty');
    }
    _files.removeWhere(
      (String descendant, Uint8List bytes) => descendants.contains(descendant),
    );
    _directories.removeAll(descendants);
    _directories.remove(normalized);
  }

  @override
  Future<String> createTemporaryDirectory(String prefix) async {
    _temporaryDirectories += 1;
    final String path =
        _normalize('$_temporaryRoot/$prefix$_temporaryDirectories');
    _seedAncestorsOf(path);
    _directories.add(path);
    return path;
  }

  @override
  Future<bool> isLink(String path) async {
    return _links.containsKey(_normalize(path));
  }

  @override
  Future<String> resolveSymbolicLinks(String path) async {
    return _resolve(path);
  }

  @override
  String absolutePath(String path) => _normalize(path);

  /// Root of the memory file system, the only root there is.
  static const String _root = '/';

  /// Synthetic root the temporary directories are created under.
  static const String _temporaryRoot = '/tmp';

  /// [path] normalized to the memory spelling: `/` separators, one root,
  /// `.` and `..` resolved, relative paths taken from the root.
  String _normalize(String path) {
    final String slashed = path.replaceAll('\\', '/');
    final List<String> segments = <String>[];
    for (final String segment in slashed.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (segments.isNotEmpty) {
          segments.removeLast();
        }
        continue;
      }
      segments.add(segment);
    }
    return '/${segments.join('/')}';
  }

  /// Directory holding [path], or null for the root.
  String? _parentOf(String path) {
    if (path == _root) {
      return null;
    }
    final int slash = path.lastIndexOf('/');
    return slash <= 0 ? _root : path.substring(0, slash);
  }

  /// Creates the missing parent directories of [path].
  void _seedAncestorsOf(String path) {
    String? ancestor = _parentOf(path);
    while (ancestor != null) {
      _files.remove(ancestor);
      _links.remove(ancestor);
      _directories.add(ancestor);
      ancestor = _parentOf(ancestor);
    }
  }

  /// [path] with every link among its segments followed, in the memory
  /// spelling.
  String _resolve(String path) {
    String current = _normalize(path);
    for (var hop = 0; hop < 64; hop++) {
      final List<String> segments = current
          .split('/')
          .where((String segment) => segment.isNotEmpty)
          .toList();
      final StringBuffer prefix = StringBuffer();
      String? target;
      var targetIndex = -1;
      for (var index = 0; index < segments.length; index++) {
        prefix
          ..write('/')
          ..write(segments[index]);
        final String? link = _links[prefix.toString()];
        if (link != null) {
          target = link;
          targetIndex = index;
          break;
        }
      }
      if (target == null) {
        return current;
      }
      final List<String> rest = segments.sublist(targetIndex + 1);
      current = _normalize(<String>[target, ...rest].join('/'));
    }
    throw StateError('too many links at "$path"');
  }

  /// Children of [directory], files and directories together.
  List<String> _childrenOf(String directory) {
    final List<String> children = <String>[];
    for (final String file in _files.keys) {
      if (_parentOf(file) == directory) {
        children.add(file);
      }
    }
    for (final String directoryCandidate in _directories) {
      if (directoryCandidate != directory &&
          _parentOf(directoryCandidate) == directory) {
        children.add(directoryCandidate);
      }
    }
    return children;
  }

  /// Files and directories under [directory], [directory] excluded.
  List<String> _descendantsOf(String directory) {
    final List<String> descendants = <String>[];
    for (final String file in _files.keys) {
      if (_isUnder(file, directory)) {
        descendants.add(file);
      }
    }
    for (final String directoryCandidate in _directories) {
      if (directoryCandidate != directory &&
          _isUnder(directoryCandidate, directory)) {
        descendants.add(directoryCandidate);
      }
    }
    return descendants;
  }

  /// Whether [path] sits inside [directory].
  bool _isUnder(String path, String directory) {
    return directory == _root || path.startsWith('$directory/');
  }

  /// File name of [path], without its directory.
  static String _baseName(String path) {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
