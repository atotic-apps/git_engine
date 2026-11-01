import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// Identity every seed commit of these copy scenarios carries.
const String copyUserName = 'Copy Keeper';
const String copyUserEmail = 'keeper@copy.test';

/// Joins [base] and [relative] with the platform separator.
String join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
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

/// A throwaway area holding the sources, the clones and the canonical stores
/// of one copy scenario, driven by one engine whose git commands never see
/// the machine configuration.
final class CopyArea {
  /// Root directory of the area; everything lives inside it.
  final Directory root;

  /// Runner every command goes through, sealed off from the machine config.
  final ProcessGitRunner runner;

  /// Engine built on [runner]: it creates, opens, clones and exchanges.
  final ProcessGitEngine engine;

  const CopyArea._({
    required this.root,
    required this.runner,
    required this.engine,
  });

  /// Creates the area and registers its disposal with [addTearDown].
  static Future<CopyArea> create() async {
    final Directory root =
        await Directory.systemTemp.createTemp('git_engine_copy_');
    try {
      final File globalConfig = File(join(root.path, 'global-config'));
      await globalConfig.writeAsString('''
[user]
	name = $copyUserName
	email = $copyUserEmail
[init]
	defaultBranch = main
[core]
	autocrlf = false
''');
      final ProcessGitRunner runner = ProcessGitRunner(
        globalEnvironment: <String, String>{
          'GIT_CONFIG_NOSYSTEM': '1',
          'GIT_CONFIG_GLOBAL': globalConfig.path,
        },
      );
      final CopyArea area = CopyArea._(
        root: root,
        runner: runner,
        engine: ProcessGitEngine(runner: runner),
      );
      addTearDown(area.dispose);
      return area;
    } catch (_) {
      await deleteRecursively(root);
      rethrow;
    }
  }

  /// Path of [name] directly under the area root.
  String path(String name) => join(root.path, name);

  /// A working repository [name] on the initial branch [branch], holding
  /// [files] in one commit. With [sideBranch], a second branch is created at
  /// the same commit. With [tag], a lightweight tag names the commit too.
  Future<GitWorkingRepository> seedWorking(
    String name,
    Map<String, String> files, {
    String branch = 'main',
    String? sideBranch,
    String? tag,
  }) async {
    final GitWorkingRepository source =
        await engine.init(path(name), initialBranch: branch);
    files.forEach((String relative, String content) {
      writeFile(source.path, relative, content);
    });
    await source.worktree.addAll();
    final GitOid commit = await source.worktree.commit('seed the source');
    if (sideBranch != null) {
      await source.refs.updateRef('refs/heads/$sideBranch', commit);
    }
    if (tag != null) {
      await source.refs.updateRef('refs/tags/$tag', commit);
    }
    return source;
  }

  /// A working clone of [sourcePath] named [name], the way a repository
  /// reported from elsewhere looks: an `origin` pointing at its upstream,
  /// remote-tracking branches included. With [localBranch], a local branch is
  /// created at the current tip as well.
  Future<GitWorkingRepository> seedClone(
    String sourcePath,
    String name, {
    String? localBranch,
  }) async {
    final GitWorkingRepository clone =
        await engine.clone(sourcePath, path(name));
    if (localBranch != null) {
      await clone.worktree.checkoutNewBranch(localBranch);
      await clone.worktree.checkout('main');
    }
    return clone;
  }

  /// A bare store [name] cloned from [sourcePath].
  Future<GitFileBareRepository> seedBare(
    String sourcePath,
    String name,
  ) {
    return engine.cloneBare(sourcePath, path(name));
  }

  /// Deletes the whole area.
  Future<void> dispose() => deleteRecursively(root);
}
