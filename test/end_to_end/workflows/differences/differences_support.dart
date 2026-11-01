import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// A throwaway workspace to read differences of the far end of a branch
/// from a recorded base, sealed off from the machine's git configuration.
final class DifferenceSandbox {
  DifferenceSandbox._({
    required this.root,
    required this.engine,
  });

  /// Root directory of the sandbox; every repository lives inside it.
  final Directory root;

  /// Engine opening the repositories of the sandbox.
  final ProcessGitEngine engine;

  /// Creates a sandbox whose disposal is registered with the current test.
  static Future<DifferenceSandbox> create() async {
    final Directory root =
        await Directory.systemTemp.createTemp('differences_');
    final File globalConfig = File(sandboxPath(root.path, 'gitconfig-global'));
    await globalConfig.writeAsString('''
[user]
	name = Difference Keeper
	email = keeper@difference.test
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
    final DifferenceSandbox sandbox = DifferenceSandbox._(
      root: root,
      engine: ProcessGitEngine(runner: runner),
    );
    addTearDown(sandbox.dispose);
    return sandbox;
  }

  /// Absolute path of [relative] inside the sandbox.
  String path(String relative) => sandboxPath(root.path, relative);

  /// Initializes a bare repository [name] holding [files] on the branch
  /// [branch], pushed from a throwaway clone. The repository is created
  /// when it does not exist; pushed files of a later call are committed
  /// onto the branch, which advances.
  Future<GitOid> seedBranch(
    String name,
    String branch,
    Map<String, String> files,
  ) async {
    final String barePath = path(name);
    if (!File(sandboxPath(barePath, 'HEAD')).existsSync()) {
      await engine.initBare(barePath, initialBranch: branch);
    }
    final String writerPath = path('$name-writer-${_writerCounter++}');
    final GitWorkingRepository writer =
        await engine.clone(barePath, writerPath);
    await writer.worktree.checkoutNewBranch(branch, resetIfExists: true);
    files.forEach((String relative, String content) {
      final File file = File(sandboxPath(writerPath, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    });
    await writer.worktree.addAll();
    await writer.worktree.commit('carry the branch');
    await engine.push(
      writer,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/$branch'],
    );
    return resolve(writer, 'refs/heads/$branch');
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

/// Resolves [rev] in [repository], failing the test when it names nothing.
Future<GitOid> resolve(GitRepository repository, String rev) async {
  final GitOid? oid = await repository.revisions.resolveRevision(rev);
  if (oid == null) {
    fail('revision "$rev" does not resolve');
  }
  return oid;
}

/// Counting the throwaway writer clones, so a second seeding never runs
/// into an existing folder.
int _writerCounter = 0;

/// Joins [base] and [relative] with the platform separator.
String sandboxPath(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}
