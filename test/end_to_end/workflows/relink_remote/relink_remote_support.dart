import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// Identity every seed commit of these rewiring scenarios carries.
const String wireUserName = 'Wire Keeper';
const String wireUserEmail = 'keeper@wire.test';

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

/// A throwaway area holding an upstream, clones of it and canonical stores,
/// driven by one engine whose git commands never see the machine
/// configuration.
final class WireArea {
  /// Root directory of the area; everything lives inside it.
  final Directory root;

  /// Runner every command goes through, sealed off from the machine config.
  final ProcessGitRunner runner;

  /// Engine built on [runner]: it creates, opens, clones and exchanges.
  final ProcessGitEngine engine;

  const WireArea._({
    required this.root,
    required this.runner,
    required this.engine,
  });

  /// Creates the area and registers its disposal with [addTearDown].
  static Future<WireArea> create() async {
    final Directory root =
        await Directory.systemTemp.createTemp('git_engine_wire_');
    try {
      final File globalConfig = File(join(root.path, 'global-config'));
      await globalConfig.writeAsString('''
[user]
	name = $wireUserName
	email = $wireUserEmail
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
      final WireArea area = WireArea._(
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

  /// An upstream [name] holding [files] on `main`, plus a commit on the
  /// branch [upstreamOnlyBranch] that no clone has fetched yet.
  Future<GitWorkingRepository> seedUpstream(
    String name,
    Map<String, String> files, {
    required String upstreamOnlyBranch,
  }) async {
    final GitWorkingRepository upstream =
        await engine.init(path(name), initialBranch: 'main');
    files.forEach((String relative, String content) {
      final File file = File(join(upstream.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    });
    await upstream.worktree.addAll();
    final GitOid mainCommit = await upstream.worktree.commit('seed main');
    await upstream.refs.updateRef(
      'refs/heads/$upstreamOnlyBranch',
      mainCommit,
    );
    return upstream;
  }

  /// A working clone of [sourcePath] named [name], carrying the usual
  /// `origin` remote, its remote-tracking branches and the upstream
  /// configuration of its checked-out branch.
  Future<GitWorkingRepository> seedClone(
    String sourcePath,
    String name,
  ) {
    return engine.clone(sourcePath, path(name));
  }

  /// An empty bare store [name], the target a rewiring points `origin` at.
  Future<GitFileBareRepository> seedStore(String name) {
    return engine.initBare(path(name), initialBranch: 'main');
  }

  /// Deletes the whole area.
  Future<void> dispose() => deleteRecursively(root);
}
