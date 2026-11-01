import 'dart:io';

import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

export '../../../support/directory_identity.dart' show sameDirectory;

/// Identity every commit of these setup scenarios carries.
const String setupUserName = 'Setup Keeper';
const String setupUserEmail = 'keeper@setup.test';

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

/// A throwaway area holding the stores and working repositories of one test,
/// driven by one engine whose git commands never see the machine
/// configuration.
final class SetupArea {
  /// Root directory of the area; everything lives inside it.
  final Directory root;

  /// Runner every command goes through, sealed off from the machine config.
  final ProcessGitRunner runner;

  /// Engine built on [runner]: it creates, opens, clones and exchanges.
  final ProcessGitEngine engine;

  const SetupArea._({
    required this.root,
    required this.runner,
    required this.engine,
  });

  /// Creates the area and registers its disposal with [addTearDown].
  static Future<SetupArea> create() async {
    final Directory root =
        await Directory.systemTemp.createTemp('git_engine_setup_');
    try {
      final File globalConfig = File(join(root.path, 'global-config'));
      await globalConfig.writeAsString('''
[user]
	name = $setupUserName
	email = $setupUserEmail
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
      final SetupArea area = SetupArea._(
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

  /// Deletes the whole area.
  Future<void> dispose() => deleteRecursively(root);
}
