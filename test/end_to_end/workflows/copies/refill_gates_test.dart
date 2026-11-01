@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// Doors a refill of an existing folder must keep closed, on git state alone:
/// the folder is only refilled when it already is a working copy of the
/// recorded origin, stands on its own and is not a sub-area of another
/// repository, and a refill moves it by fetching and folding its tracked
/// branch, never by resetting its work tree. The checks are decisions an area
/// keeper makes itself, each one expressed with a building block of the
/// public API.
void main() {
  late Directory root;
  late ProcessGitRunner runner;
  late ProcessGitEngine engine;
  var scratchCounter = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('git_engine_refill_');
    final File globalConfig = File(join(root.path, 'gitconfig-global'));
    await globalConfig.writeAsString('''
[user]
	name = Refill Keeper
	email = keeper@refill.test
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

  /// A bare store [name] on the initial branch `main`, seeded with one
  /// commit on `main`.
  Future<GitFileBareRepository> seedStore(String name) async {
    final GitFileBareRepository store =
        await engine.initBare(path(name), initialBranch: 'main');
    final GitWorkingRepository seeder =
        await engine.clone(store.path, path('seed-${scratchCounter++}'));
    File(join(seeder.path, 'readme.md')).writeAsStringSync('# $name\n');
    await seeder.worktree.addAll();
    await seeder.worktree.commit('seed the store');
    await engine.push(
      seeder,
      remote: 'origin',
      refspecs: const <String>['HEAD:refs/heads/main'],
    );
    return store;
  }

  /// A working clone of [storePath] under [name].
  Future<GitWorkingRepository> cloneOf(String name, String storePath) {
    return engine.clone(storePath, path(name));
  }

  /// One commit on `main` of [store], made in a throwaway clone, carrying
  /// [file].
  Future<GitOid> advance(
    GitFileBareRepository store,
    Map<String, String> file,
  ) async {
    final GitWorkingRepository advancer =
        await cloneOf('advance-${scratchCounter++}', store.path);
    file.forEach((String relative, String content) {
      File(join(advancer.path, relative)).writeAsStringSync(content);
    });
    await advancer.worktree.addAll();
    await advancer.worktree.commit('advance the store');
    await engine.push(
      advancer,
      remote: 'origin',
      refspecs: const <String>['HEAD:refs/heads/main'],
    );
    final GitOid tip = (await advancer.revisions.resolveRevision('HEAD'))!;
    return tip;
  }

  test('a folder holding no repository of its own is not refilled', () async {
    final Directory folder = Directory(path('plain'));
    await folder.create(recursive: true);
    File(join(folder.path, 'notes.txt')).writeAsStringSync('plain files\n');

    await expectLater(
      engine.open(folder.path),
      throwsA(isA<GitNotARepositoryException>()),
      reason: 'the folder holds no repository of its own, so no fetch or '
          'clone ever starts',
    );
    expect(
      Directory(join(folder.path, '.git')).existsSync(),
      isFalse,
      reason: 'the folder was left exactly as it was',
    );
    expect(File(join(folder.path, 'notes.txt')).existsSync(), isTrue);
  });

  test('a refilled folder is never reset to the foundation', () async {
    final GitFileBareRepository store = await seedStore('store');

    // A folder that stayed behind folds forward: fetch, then a
    // fast-forward-only merge of its tracked branch — never a reset.
    final GitWorkingRepository behind = await cloneOf('behind', store.path);
    File(join(behind.path, 'local-notes.txt')).writeAsStringSync('kept\n');
    final GitOid advanced = await advance(
      store,
      <String, String>{'ahead.txt': 'ahead\n'},
    );
    await engine.fetch(behind, remote: 'origin');
    await behind.merge.merge(
      'origin/main',
      mode: GitMergeMode.fastForwardOnly,
    );
    expect(await behind.revisions.resolveRevision('HEAD'), advanced);
    expect(
      File(join(behind.path, 'ahead.txt')).readAsStringSync(),
      'ahead\n',
    );
    expect(
      File(join(behind.path, 'local-notes.txt')).readAsStringSync(),
      'kept\n',
      reason: 'the fold adds and moves files; it never sweeps the folder',
    );

    // A folder that moved on its own refuses the fold instead of being reset
    // to the foundation the origin carries.
    final GitWorkingRepository diverged = await cloneOf('diverged', store.path);
    final GitOid originTip = await advance(
      store,
      <String, String>{'origin-side.txt': 'origin side\n'},
    );
    File(join(diverged.path, 'own.txt')).writeAsStringSync('own work\n');
    await diverged.worktree.addAll();
    await diverged.worktree.commit('own commit');
    File(join(diverged.path, 'own.txt')).writeAsStringSync('own, edited\n');
    await engine.fetch(diverged, remote: 'origin');

    await expectLater(
      diverged.merge.merge(
        'origin/main',
        mode: GitMergeMode.fastForwardOnly,
      ),
      throwsA(isA<GitMergeNotFastForwardException>()),
      reason: 'a diverged folder is never reset to what the origin carries',
    );
    expect(
      File(join(diverged.path, 'own.txt')).readAsStringSync(),
      'own, edited\n',
      reason: 'the committed and uncommitted work of the folder survives',
    );
    expect(
      await diverged.revisions.resolveRevision('origin/main'),
      originTip,
      reason: 'the origin state was fetched, only the fold was refused',
    );
    expect(
      File(join(diverged.path, 'origin-side.txt')).existsSync(),
      isFalse,
      reason: 'no reset brought the origin content into the folder',
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
