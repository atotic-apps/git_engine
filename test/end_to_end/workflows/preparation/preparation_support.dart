import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

import '../../../support/index_tree_paths.dart';

export '../../../support/directory_identity.dart' show sameDirectory;

/// Identity used for the seed commits of the origin repositories.
const String seedUserName = 'Origin Keeper';
const String seedUserEmail = 'keeper@origin.test';

/// Joins [base] and [relative] with the platform separator.
String join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

/// Path of a working copy [name] under the area's `work` directory.
String copyPath(PreparationWorkdir workdir, String name) {
  return join(join(workdir.root.path, 'work'), name);
}

/// Whether [path] is spelled as an absolute path on this platform.
bool isAbsolutePath(String path) {
  if (Platform.isWindows) {
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');
  }
  return path.startsWith('/');
}

/// Content of the file at [path], read without checkout line-ending noise.
String contentOf(String path) {
  return File(path).readAsStringSync().replaceAll('\r\n', '\n');
}

/// Writes [content] into the file [root]/[relative], creating the parent
/// directories.
void writeFile(String root, String relative, String content) {
  final File file = File(join(root, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

/// Paths tracked by [repository] under [pathspec], sorted.
Future<List<String>> trackedPaths(
  GitIndexedRepository repository,
  String pathspec,
) async {
  final List<String> paths = await indexPaths(repository);
  return paths
      .where(
        (String path) => path == pathspec || path.startsWith('$pathspec/'),
      )
      .toList();
}

/// Paths of the tree [commit] snapshots, at its first level.
Future<Set<String>> committedTopLevelPaths(
  GitFileRepository repository,
  GitOid commit,
) async {
  final GitCommit record = await repository.objects.readCommit(commit);
  final GitTree tree = await repository.objects.readTree(record.tree);
  return tree.entries.map((GitTreeEntry entry) => entry.path).toSet();
}

/// Deletes [directory], retrying while the system still holds a handle on a
/// file, as Windows commonly does right after a git process exits.
Future<void> deleteRecursively(Directory directory) async {
  for (var attempt = 0;; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt >= 4) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// A disposable work area for preparation scenarios: one temporary root
/// holding origin repositories and working copies, driven by one engine whose
/// git commands never see the machine's git configuration.
final class PreparationWorkdir {
  /// Root directory of the area; everything lives inside it.
  final Directory root;

  /// Runner every command goes through, sealed off from the machine config.
  final ProcessGitRunner runner;

  /// Engine built on [runner]: opens, creates, clones and pushes.
  final ProcessGitEngine engine;

  const PreparationWorkdir._({
    required this.root,
    required this.runner,
    required this.engine,
  });

  /// Creates the area and registers its disposal with [addTearDown].
  static Future<PreparationWorkdir> create() async {
    final Directory root =
        await Directory.systemTemp.createTemp('git_engine_preparation_');
    try {
      final File globalConfig = File(join(root.path, 'global-config'));
      await globalConfig.create();
      final ProcessGitRunner runner = ProcessGitRunner(
        globalEnvironment: <String, String>{
          'GIT_CONFIG_NOSYSTEM': '1',
          'GIT_CONFIG_GLOBAL': globalConfig.path,
        },
      );
      final PreparationWorkdir workdir = PreparationWorkdir._(
        root: root,
        runner: runner,
        engine: ProcessGitEngine(runner: runner),
      );
      addTearDown(workdir.dispose);
      return workdir;
    } catch (_) {
      await deleteRecursively(root);
      rethrow;
    }
  }

  /// Creates a bare origin repository [name] holding [files] on the
  /// integration branch `main`, pushed from a throwaway clone. With [files]
  /// left null, the origin stays without any commit: its `HEAD` is unborn.
  Future<String> createOrigin(String name, Map<String, String>? files) async {
    final String originPath = join(root.path, name);
    await engine.initBare(originPath, initialBranch: 'main');
    if (files == null) {
      return originPath;
    }
    final String seedPath = join(root.path, '$name-seed');
    final GitWorkingRepository seed = await engine.clone(originPath, seedPath);
    files.forEach((String relative, String content) {
      writeFile(seedPath, relative, content);
    });
    await seed.worktree.addAll();
    await seed.worktree.commit(
      'seed the origin',
      identity: GitIdentity(name: seedUserName, email: seedUserEmail),
    );
    await engine.push(
      seed,
      remote: 'origin',
      refspecs: <String>['refs/heads/main:refs/heads/main'],
    );
    return originPath;
  }

  /// Creates a fresh working repository [name] on the initial branch `main`,
  /// without any commit yet.
  Future<GitWorkingRepository> createWorking(String name) {
    return engine.init(join(root.path, name), initialBranch: 'main');
  }

  /// Deletes the whole area.
  Future<void> dispose() => deleteRecursively(root);
}
