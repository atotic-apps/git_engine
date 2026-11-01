@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// Readings of the commit history a branch carries since a base, taken on a
/// real bare store.
///
/// The history readings that ARE public are covered elsewhere: ancestry and
/// the best common ancestor (see the sources suites), and the commits that
/// touched one path (see the ref suites).
void main() {
  late Directory root;
  late ProcessGitRunner runner;
  late ProcessGitEngine engine;
  var scratchCounter = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('git_engine_histories_');
    final File globalConfig = File(join(root.path, 'gitconfig-global'));
    await globalConfig.writeAsString('''
[user]
	name = History Keeper
	email = keeper@history.test
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

  /// A bare store [name] on the initial branch `main`.
  Future<GitFileBareRepository> seedStore(String name) {
    return engine.initBare(path(name), initialBranch: 'main');
  }

  /// A working clone of [storePath], named after the scratch counter.
  Future<GitWorkingRepository> cloneOf(String storePath) {
    return engine.clone(storePath, path('clone-${scratchCounter++}'));
  }

  /// Stages and commits every change of [repository] as [message].
  Future<GitOid> commitAll(
    GitWorkingRepository repository,
    String message,
  ) async {
    await repository.worktree.addAll();
    return repository.worktree.commit(message);
  }

  test('a branch is listed by the commits it carries since a recorded base',
      () async {
    final GitFileBareRepository store = await seedStore('store');
    final GitWorkingRepository baseClone = await cloneOf(store.path);
    File(join(baseClone.path, 'readme.md')).writeAsStringSync('# store\n');
    final GitOid base = await commitAll(baseClone, 'seed the store');
    await engine.push(
      baseClone,
      remote: 'origin',
      refspecs: const <String>['HEAD:refs/heads/main'],
    );

    final GitWorkingRepository branch = await cloneOf(store.path);
    await branch.worktree.checkoutNewBranch('work-branch');
    File(join(branch.path, 'notes.txt')).writeAsStringSync('the work\n');
    final GitOid first = await commitAll(branch, 'carry the first piece');
    File(join(branch.path, 'more.txt')).writeAsStringSync('more work\n');
    final GitOid second = await commitAll(branch, 'carry the second piece');
    await engine.push(
      branch,
      remote: 'origin',
      refspecs: const <String>['HEAD:refs/heads/work-branch'],
    );

    final List<GitLogEntry> carried =
        await store.history.commitsSince(base.value, 'refs/heads/work-branch');

    expect(
      carried,
      <GitLogEntry>[
        GitLogEntry(oid: second, subject: 'carry the second piece'),
        GitLogEntry(oid: first, subject: 'carry the first piece'),
      ],
      reason: 'the branch is listed newest first, each commit with its '
          'subject, whether or not it touched a path',
    );
    expect(
      carried.map((GitLogEntry entry) => entry.oid),
      isNot(contains(base)),
      reason: 'the recorded base itself is not part of what the branch '
          'carries since it',
    );
    expect(
      await store.history.commitsSince(second.value, 'refs/heads/work-branch'),
      isEmpty,
      reason: 'a base at the tip of the branch carries nothing since it',
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
