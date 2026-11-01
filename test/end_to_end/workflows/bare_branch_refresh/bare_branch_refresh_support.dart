import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// Identity every commit of these refresh scenarios carries.
const String foldUserName = 'Fold Keeper';
const String foldUserEmail = 'keeper@fold.test';

/// Joins [base] and [relative] with the platform separator.
String join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
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

/// A throwaway area holding one bare store whose branches are advanced by
/// other writers, driven by one engine whose git commands never see the
/// machine configuration.
final class FoldArea {
  /// Root directory of the area; everything lives inside it.
  final Directory root;

  /// Runner every command goes through, sealed off from the machine config.
  final ProcessGitRunner runner;

  /// Engine built on [runner]: it creates, opens, clones and exchanges.
  final ProcessGitEngine engine;

  /// Count of the throwaway clones created so far, for unique names.
  int scratchCounter = 0;

  FoldArea._({
    required this.root,
    required this.runner,
    required this.engine,
  });

  /// Creates the area and registers its disposal with [addTearDown].
  static Future<FoldArea> create() async {
    final Directory root =
        await Directory.systemTemp.createTemp('git_engine_fold_');
    try {
      final File globalConfig = File(join(root.path, 'global-config'));
      await globalConfig.writeAsString('''
[user]
	name = $foldUserName
	email = $foldUserEmail
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
      final FoldArea area = FoldArea._(
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

  /// An empty bare store [name] on the initial branch [branch].
  Future<GitFileBareRepository> seedStore(
    String name, {
    String branch = 'main',
  }) {
    return engine.initBare(path(name), initialBranch: branch);
  }

  /// Lands a commit on [branch] of [store] from a throwaway clone. When the
  /// store already carries the branch, the commit is built on its tip;
  /// otherwise it is built on the checked-out branch and pushed onto the new
  /// name. Returns the tip the branch carries afterwards.
  Future<GitOid> landOnBranch(
    GitFileBareRepository store,
    String branch,
    Map<String, String> files, {
    required String message,
  }) async {
    final String scratch = path('seed-${scratchCounter++}');
    final GitWorkingRepository work = await engine.clone(
      store.path,
      scratch,
    );
    try {
      final GitOid? remoteTip =
          await work.refs.resolveRef('refs/remotes/origin/$branch');
      if (remoteTip != null) {
        await work.worktree.checkoutNewBranch(
          branch,
          startPoint: remoteTip.value,
          resetIfExists: true,
        );
      }
      files.forEach((String relative, String content) {
        final File file = File(join(work.path, relative));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
      });
      await work.worktree.addAll();
      final GitOid commit = await work.worktree.commit(message);
      await engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['HEAD:refs/heads/$branch'],
      );
      return commit;
    } finally {
      await deleteRecursively(Directory(scratch));
    }
  }

  /// Deletes the whole area.
  Future<void> dispose() => deleteRecursively(root);
}
