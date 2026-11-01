import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import '../confined_path.dart';
import '../git_file_system.dart';
import '../process_git_repository.dart';

/// [GitDirectoryFiles] implementation reading and writing the git directory
/// of the owning process repository as plain files through the injected file
/// system and platform.
///
/// Symbolic links and Windows junctions are never followed while capturing:
/// only the regular files physically under the git directory are collected.
/// Restoring and drifting resolve the links of every path they touch and
/// refuse, with a [GitException] naming the key, any path that leaves the git
/// directory once they are resolved.
class ProcessGitDirectoryFiles implements GitDirectoryFiles {
  /// Repository whose git directory is captured, compared and restored.
  final ProcessGitRepository repository;

  /// Creates the implementation working on [repository]'s git directory.
  ProcessGitDirectoryFiles({required this.repository});

  @override
  Future<GitDirectorySnapshot> capture() async {
    final String root = await _gitDirectory();
    return GitDirectorySnapshot(await _readAll(root));
  }

  @override
  Future<GitDirectoryDrift> drift(GitDirectorySnapshot snapshot) async {
    final String root = await _gitDirectory();
    final String rootReal =
        await repository.fileSystem.resolveSymbolicLinks(root);
    for (final String path in snapshot.files.keys) {
      await _confinedPath(root, rootReal, path);
    }
    final Map<String, Uint8List> current = await _readAll(root);
    final List<String> modified = <String>[];
    final List<String> added = <String>[];
    final List<String> deleted = <String>[];
    snapshot.files.forEach((String path, Uint8List captured) {
      final Uint8List? now = current[path];
      if (now == null) {
        deleted.add(path);
      } else if (!_sameBytes(captured, now)) {
        modified.add(path);
      }
    });
    for (final String path in current.keys) {
      if (!snapshot.files.containsKey(path)) {
        added.add(path);
      }
    }
    return GitDirectoryDrift(
      modified: modified..sort(),
      added: added..sort(),
      deleted: deleted..sort(),
    );
  }

  @override
  Future<List<String>> restore(GitDirectorySnapshot snapshot) async {
    final String root = await _gitDirectory();
    final String rootReal =
        await repository.fileSystem.resolveSymbolicLinks(root);
    // Every key is confined before the first write, so one refused key leaves
    // the git directory exactly as it was.
    final Map<String, String> targets = <String, String>{};
    for (final String path in snapshot.files.keys) {
      targets[path] = await _confinedPath(root, rootReal, path);
    }
    final List<String> restored = <String>[];
    for (final MapEntry<String, String> target in targets.entries) {
      final String path = target.key;
      final Uint8List bytes = snapshot.files[path]!;
      final String filePath = target.value;
      if (await _holdsBytes(filePath, bytes)) {
        continue;
      }
      await _createParentOf(filePath);
      await repository.fileSystem.writeBytes(filePath, bytes);
      restored.add(path);
    }
    return List<String>.unmodifiable(restored..sort());
  }

  /// The platform path of the git-directory relative [key], after checking
  /// that [key] is valid and that every existing segment of it stays under
  /// [root] once symbolic links and Windows junctions are resolved.
  ///
  /// [rootReal] is [root] with its own links resolved. Throws a
  /// [GitException] naming [key] when it is refused.
  Future<String> _confinedPath(
    String root,
    String rootReal,
    String key,
  ) async {
    final String? path = await confineRelativePath(
      repository.fileSystem,
      repository.platform.pathStyle,
      root: root,
      rootReal: rootReal,
      relativePath: key,
      linkPolicy: ConfinedPathLinkPolicy.resolve,
      subject: 'git-directory file',
      windows: repository.platform.pathStyle.isWindows,
    );
    return path!;
  }

  /// The path of the git directory whose plain files this domain reads and
  /// writes.
  ///
  /// git answers for a healthy repository. A git directory being repaired can
  /// be unreadable to git itself — a damaged `HEAD` does exactly that — so
  /// the location git would have found is then derived from the repository
  /// the way git discovers it: the `.git` entry beside the work tree, the
  /// directory a `.git` file names, or the repository itself when it is bare.
  Future<String> _gitDirectory() async {
    try {
      return await repository.gitDir();
    } on GitException {
      return _deriveGitDirectory(repository.path);
    }
  }

  /// The git directory of the repository at [path], derived without git.
  Future<String> _deriveGitDirectory(String path) async {
    final GitFileSystem fileSystem = repository.fileSystem;
    final String dotGit = _joinPath(path, '.git');
    if (await fileSystem.isDirectory(dotGit)) {
      return dotGit;
    }
    if (await fileSystem.exists(dotGit)) {
      final RegExpMatch? match = RegExp(
        r'^gitdir:\s*(.+)$',
      ).firstMatch(utf8.decode(await fileSystem.readBytes(dotGit)).trim());
      if (match != null) {
        final String target = match.group(1)!.trim();
        final bool rooted = repository.platform.pathStyle.isAbsolute(target);
        return rooted ? target : _joinPath(path, target);
      }
    }
    return path;
  }

  /// Whether the file at [path] already holds [bytes], so restoring has
  /// nothing to write. Loose objects are stored read-only on some platforms;
  /// a file git holds verbatim is left exactly as it is.
  Future<bool> _holdsBytes(String path, Uint8List bytes) async {
    if (!await repository.fileSystem.exists(path)) {
      return false;
    }
    return _sameBytes(bytes, await repository.fileSystem.readBytes(path));
  }

  /// Creates the missing parent directory of [path] with all its ancestors.
  Future<void> _createParentOf(String path) async {
    final String? parent = repository.platform.pathStyle.parentOf(path);
    if (parent != null &&
        parent != path &&
        !(await repository.fileSystem.isDirectory(parent))) {
      await repository.fileSystem.createDirectory(parent, recursive: true);
    }
  }

  /// Every regular file under [root], keyed by forward-slash relative path.
  ///
  /// Links are skipped, so a directory of the git directory that points
  /// elsewhere contributes no file to the capture or the drift comparison.
  Future<Map<String, Uint8List>> _readAll(String root) async {
    final Map<String, Uint8List> files = <String, Uint8List>{};
    await _collect(root, '', files);
    return files;
  }

  Future<void> _collect(
    String directoryPath,
    String relativePrefix,
    Map<String, Uint8List> files,
  ) async {
    for (final GitFileSystemEntry entry
        in await repository.fileSystem.list(directoryPath)) {
      final String relative =
          relativePrefix.isEmpty ? entry.name : '$relativePrefix/${entry.name}';
      final String childPath = _joinPath(directoryPath, entry.name);
      if (await repository.fileSystem.isLink(childPath)) {
        continue;
      }
      if (entry.isDirectory) {
        await _collect(childPath, relative, files);
      } else {
        files[relative] = await repository.fileSystem.readBytes(childPath);
      }
    }
  }

  /// The platform path of the git-directory relative [relative] path.
  String _joinPath(String base, String relative) {
    return repository.platform.pathStyle.join(base, relative);
  }

  static bool _sameBytes(Uint8List first, Uint8List second) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }
}
