import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// A throwaway workspace used to draw working copies of bare repositories,
/// sealed off from the machine's git configuration: the global
/// configuration gives every repository a fixed identity, the default
/// branch `main` and `core.autocrlf=false`.
final class CopiesSandbox {
  CopiesSandbox._({
    required this.root,
    required this.engine,
  });

  /// Absolute path of the sandbox root; every repository lives inside it.
  final String root;

  /// Engine opening and cloning the repositories of the sandbox.
  final ProcessGitEngine engine;

  /// Creates a sandbox whose disposal is registered with the current test.
  static Future<CopiesSandbox> create() async {
    final Directory root = await Directory.systemTemp.createTemp('copies_');
    final File globalConfig = File(joinPaths(root.path, 'gitconfig-global'));
    await globalConfig.writeAsString('''
[user]
	name = Copy Keeper
	email = keeper@copies.test
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
    final CopiesSandbox sandbox = CopiesSandbox._(
      root: root.path,
      engine: ProcessGitEngine(runner: runner),
    );
    addTearDown(sandbox.dispose);
    return sandbox;
  }

  /// Absolute path of [relative] inside the sandbox.
  String path(String relative) => joinPaths(root, relative);

  /// Initializes a bare repository [name] holding [files] on [branch],
  /// pushed from a throwaway clone. Returns the tip [branch] points at.
  ///
  /// A store an earlier seeding created is reinitialized, its data kept: the
  /// push of this seeding moves the branch on.
  Future<GitOid> seedBranch(
    String name,
    String branch,
    Map<String, String> files,
  ) async {
    final String barePath = path(name);
    await engine.initBare(barePath, initialBranch: branch, allowOccupied: true);
    final String writerPath = path('$name-writer-${_writerCounter++}');
    final GitWorkingRepository writer =
        await engine.clone(barePath, writerPath);
    await writer.worktree.checkoutNewBranch(branch, resetIfExists: true);
    files.forEach((String relative, String content) {
      final File file = File(joinPaths(writerPath, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    });
    await writer.worktree.addAll();
    final GitOid tip = await writer.worktree.commit('seed the branch');
    await engine.push(
      writer,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/$branch'],
    );
    return tip;
  }

  /// Deletes the sandbox, retrying while the system may still hold file
  /// locks right after git exits.
  Future<void> dispose() async {
    for (var attempt = 0;; attempt++) {
      try {
        await Directory(root).delete(recursive: true);
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

/// Joins [base] and [relative] with the platform separator.
String joinPaths(String base, String relative) {
  return '$base${Platform.pathSeparator}$relative';
}
