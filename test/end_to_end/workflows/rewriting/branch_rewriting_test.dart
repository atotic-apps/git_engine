@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// Moves of a branch that a plain exchange refuses: a branch of a remote is
/// moved onto a commit the exchanged history does not descend from, so the
/// remote keeps the pushed history instead of refusing the exchange.
///
/// The building blocks that ARE public are covered elsewhere: a branch of a
/// bare repository moves to a commit its history descends from through a
/// plain push (see the landing suites), and through a direct ref update
/// inside that same repository (see the ref suites).
void main() {
  late Directory root;
  late ProcessGitRunner runner;
  late ProcessGitEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('git_engine_rewriting_');
    final File globalConfig = File(join(root.path, 'gitconfig-global'));
    await globalConfig.writeAsString('''
[user]
	name = Rewrite Keeper
	email = keeper@rewriting.test
[init]
	defaultBranch = main
[core]
	autocrlf = false
''');
    runner = ProcessGitRunner(
      globalEnvironment: <String, String>{
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': globalConfig.path,
      },
    );
    engine = ProcessGitEngine(runner: runner);
    addTearDown(() async {
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
    });
  });

  String path(String name) => join(root.path, name);

  test(
      'a branch of a remote is moved onto a commit the exchanged history '
      'does not descend from', () async {
    final GitFileBareRepository store =
        await engine.initBare(path('store.git'), initialBranch: 'main');

    // The foundation: one commit every side starts from.
    final GitWorkingRepository foundation =
        await engine.clone(store.path, path('foundation'));
    File(join(foundation.path, 'readme.md')).writeAsStringSync('# store\n');
    await foundation.worktree.addAll();
    await foundation.worktree.commit('seed the store');
    await engine.push(
      foundation,
      remote: 'origin',
      refspecs: const <String>['HEAD:refs/heads/main'],
    );
    final GitOid base = (await store.refs.resolveRef('refs/heads/main'))!;

    // The exchanged history: the remote branch is landed on by one clone.
    final GitWorkingRepository landed =
        await engine.clone(store.path, path('landed'));
    File(join(landed.path, 'landed.txt')).writeAsStringSync('landed\n');
    await landed.worktree.addAll();
    await landed.worktree.commit('landed work');
    await engine.push(
      landed,
      remote: 'origin',
      refspecs: const <String>['HEAD:refs/heads/main'],
    );
    final GitOid remoteTipBefore =
        (await store.refs.resolveRef('refs/heads/main'))!;

    // The rewritten history: another clone moves its branch back to the
    // foundation and commits in place, so the pushed commit does not
    // descend from the tip the remote carries.
    final GitWorkingRepository rewritten =
        await engine.clone(store.path, path('rewritten'));
    await rewritten.refs.resetSoft(base.value);
    File(join(rewritten.path, 'landed.txt'))
        .writeAsStringSync('replaced at the foundation\n');
    await rewritten.worktree.addAll();
    final GitOid replacement = await rewritten.worktree.commit(
      'a history that replaces the exchanged one',
    );
    expect(
      (await rewritten.objects.readCommit(replacement)).parents,
      <GitOid>[base],
    );

    await expectLater(
      engine.push(
        rewritten,
        remote: 'origin',
        refspecs: const <String>['HEAD:refs/heads/main'],
      ),
      throwsA(isA<GitPushRejectedException>()),
      reason: 'without force the remote refuses to lose the exchanged '
          'history',
    );

    await engine.push(
      rewritten,
      remote: 'origin',
      refspecs: const <String>['HEAD:refs/heads/main'],
      force: true,
    );

    expect(
      await store.refs.resolveRef('refs/heads/main'),
      replacement,
      reason: 'the remote branch moved onto the pushed commit',
    );
    expect(
      await store.objects.objectExists(remoteTipBefore),
      isTrue,
      reason: 'the tip the branch left behind is kept in the remote store',
    );
    expect(
      await store.history.isAncestor(remoteTipBefore, replacement),
      isFalse,
      reason: 'the pushed history does not descend from the exchanged tip',
    );
  });
}

/// Joins [base] and [relative] with the platform separator.
String join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}
