import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// A throwaway workspace holding a bare repository and a working copy of it
/// whose git directory can be damaged and mended, sealed off from the
/// machine's git configuration.
///
/// Every repository inside inherits the fixed identity, the default branch
/// `main` and `core.autocrlf=false` from the sandbox's own global
/// configuration file.
final class IntegritySandbox {
  IntegritySandbox._({
    required this.root,
    required this.engine,
  });

  /// Root directory of the sandbox; every repository lives inside it.
  final Directory root;

  /// Engine building and opening the repositories of the sandbox.
  final ProcessGitEngine engine;

  /// Creates a sandbox whose disposal is registered with the current test.
  static Future<IntegritySandbox> create() async {
    final Directory root = await Directory.systemTemp.createTemp('integrity_');
    final File globalConfig = File(sandboxPath(root.path, 'gitconfig-global'));
    await globalConfig.writeAsString('''
[user]
	name = Integrity Keeper
	email = keeper@integrity.test
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
    final IntegritySandbox sandbox = IntegritySandbox._(
      root: root,
      engine: ProcessGitEngine(runner: runner),
    );
    addTearDown(sandbox.dispose);
    return sandbox;
  }

  /// Absolute path of [relative] inside the sandbox.
  String path(String relative) => sandboxPath(root.path, relative);

  /// Initializes a bare repository [name] holding [files] on `main`, pushed
  /// from a throwaway clone, and clones it as [copyName]. Returns the copy,
  /// whose git directory the tests then damage.
  Future<GitWorkingRepository> seedCopy(
    String name,
    String copyName,
    Map<String, String> files,
  ) async {
    final String barePath = path(name);
    await engine.initBare(barePath, initialBranch: 'main');
    final String writerPath = path('$name-writer-${_writerCounter++}');
    final GitWorkingRepository writer =
        await engine.clone(barePath, writerPath);
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
    return engine.clone(barePath, path(copyName));
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

/// Counting the throwaway writer clones, so a second seeding never runs
/// into an existing folder.
int _writerCounter = 0;

/// Writes [content] into [relative] of the work tree at [repoPath].
void writeFile(String repoPath, String relative, String content) {
  final File file = File(sandboxPath(repoPath, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

/// Content of [relative] in the work tree at [repoPath].
String readFile(String repoPath, String relative) {
  return File(sandboxPath(repoPath, relative)).readAsStringSync();
}

/// Joins [base] and [relative] with the platform separator.
String sandboxPath(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}
