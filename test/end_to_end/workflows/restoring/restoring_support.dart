import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// A throwaway workspace holding a bare repository and the working copy
/// carrying an uncommitted piece of work, sealed off from the machine's git
/// configuration.
final class RestoreSandbox {
  RestoreSandbox._({
    required this.root,
    required this.engine,
  });

  /// Root directory of the sandbox; every repository lives inside it.
  final Directory root;

  /// Engine opening, cloning and pushing the repositories of the sandbox.
  final ProcessGitEngine engine;

  /// Creates a sandbox whose disposal is registered with the current test.
  static Future<RestoreSandbox> create() async {
    final Directory root = await Directory.systemTemp.createTemp('restoring_');
    final File globalConfig = File(sandboxPath(root.path, 'gitconfig-global'));
    await globalConfig.writeAsString('''
[user]
	name = Restore Keeper
	email = keeper@restore.test
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
    final RestoreSandbox sandbox = RestoreSandbox._(
      root: root,
      engine: ProcessGitEngine(runner: runner),
    );
    addTearDown(sandbox.dispose);
    return sandbox;
  }

  /// Absolute path of [relative] inside the sandbox.
  String path(String relative) => sandboxPath(root.path, relative);

  /// Initializes a bare repository [name] holding [files] on the
  /// integration branch `main`, pushed from a throwaway clone.
  Future<GitFileBareRepository> seedBare(
    String name,
    Map<String, String> files,
  ) async {
    final String originPath = path(name);
    await engine.initBare(originPath, initialBranch: 'main');
    final String writerPath = path('$name-writer');
    final GitWorkingRepository writer =
        await engine.clone(originPath, writerPath);
    await writer.worktree.checkoutNewBranch('main', resetIfExists: true);
    files.forEach((String relative, String content) {
      writeFile(writerPath, relative, content);
    });
    await writer.worktree.addAll();
    await writer.worktree.commit('seed the origin');
    await engine.push(
      writer,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/main'],
    );
    return engine.openBare(originPath);
  }

  /// Clones [source] into the sandbox as [name].
  Future<GitWorkingRepository> clone(String source, String name) {
    return engine.clone(source, path(name));
  }

  /// Deletes the sandbox, retrying while the system may still hold file
  /// locks right after git exits.
  Future<void> dispose() async {
    for (var attempt = 0;; attempt++) {
      try {
        await root.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 4) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}

/// A working clone of a bare repository used to move the `main` branch from
/// the outside, the way another writer would between two reads of a work
/// copy.
final class AdvanceWriter {
  AdvanceWriter._(this._clone, this._barePath, this._engine);

  final GitWorkingRepository _clone;
  final String _barePath;
  final ProcessGitEngine _engine;

  /// Creates a writer clone of the bare at [barePath] inside [sandbox].
  static Future<AdvanceWriter> create(
    RestoreSandbox sandbox,
    String barePath, {
    String name = 'advancer',
  }) async {
    final GitWorkingRepository clone =
        await sandbox.engine.clone(barePath, sandbox.path(name));
    return AdvanceWriter._(clone, barePath, sandbox.engine);
  }

  /// Writes [content] into the work tree as the file [relative], commits
  /// it on the integration branch and pushes. Returns the bare repository.
  Future<GitFileBareRepository> commitOnFile(
    String relative,
    String content,
    String message,
  ) async {
    writeFile(_clone.path, relative, content);
    await _clone.worktree.addAll();
    await _clone.worktree.commit(message);
    await _engine.push(
      _clone,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/main'],
    );
    return _engine.openBare(_barePath);
  }
}

/// Writes [content] into the file [repoPath]/[relative], creating the
/// parent directories.
void writeFile(String repoPath, String relative, String content) {
  final File file = File(sandboxPath(repoPath, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

/// Content of [relative] in the work tree at [repoPath].
String readFile(String repoPath, String relative) {
  return File(sandboxPath(repoPath, relative)).readAsStringSync();
}

/// Stages every change of [repository] and commits it as [message].
Future<GitOid> commitAll(
  GitWorkingRepository repository,
  String message,
) async {
  await repository.worktree.addAll();
  return repository.worktree.commit(message);
}

/// Resolves [rev] in [repository], failing the test when it names nothing.
Future<GitOid> resolve(GitRepository repository, String rev) async {
  final GitOid? oid = await repository.revisions.resolveRevision(rev);
  if (oid == null) {
    fail('revision "$rev" does not resolve');
  }
  return oid;
}

/// Joins [base] and [relative] with the platform separator.
String sandboxPath(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}
