import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// Identity every commit of these tree scenarios carries.
const String kindsUserName = 'Tree Keeper';
const String kindsUserEmail = 'keeper@kinds.test';

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

/// A throwaway area holding the working repositories one tree scenario
/// commits into, driven by one engine whose git commands never see the
/// machine configuration.
final class KindsArea {
  /// Root directory of the area; everything lives inside it.
  final Directory root;

  /// Runner every command goes through, sealed off from the machine config.
  final ProcessGitRunner runner;

  /// Engine built on [runner]: it creates and opens repositories.
  final ProcessGitEngine engine;

  const KindsArea._({
    required this.root,
    required this.runner,
    required this.engine,
  });

  /// Creates the area and registers its disposal with [addTearDown].
  static Future<KindsArea> create() async {
    final Directory root =
        await Directory.systemTemp.createTemp('git_engine_kinds_');
    try {
      final File globalConfig = File(join(root.path, 'global-config'));
      await globalConfig.writeAsString('''
[user]
	name = $kindsUserName
	email = $kindsUserEmail
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
      final KindsArea area = KindsArea._(
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

  /// A working repository [name] on the initial branch `main`.
  Future<GitWorkingRepository> seedWorking(String name) {
    return engine.init(path(name), initialBranch: 'main');
  }

  /// Deletes the whole area.
  Future<void> dispose() => deleteRecursively(root);
}
