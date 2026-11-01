@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../../../backends/process/support/process_test_git.dart';
import 'relink_remote_support.dart';

/// Rewiring a working clone onto a new canonical store: the old upstream
/// becomes a backup remote carrying the references it had, the origin name is
/// taken over and points at the store, the tracking references are refreshed
/// from it, and the upstream configuration of the local branches keeps naming
/// origin. An exchange aborts while a tracking reference is locked.
void main() {
  late WireArea area;
  var scratchCounter = 0;

  setUp(() async {
    area = await WireArea.create();
  });

  /// Lands a commit on [branch] of [store] from a throwaway clone: the branch
  /// is created at the current tip when it does not exist yet. Returns the
  /// tip it carries afterwards.
  Future<GitOid> landOnBranch(
    GitFileBareRepository store,
    String branch,
  ) async {
    final String scratch = area.path('seed-${scratchCounter++}');
    final GitWorkingRepository work = await area.engine.clone(
      store.path,
      scratch,
    );
    try {
      if (await work.branches.current() != branch) {
        final GitOid? remoteTip =
            await work.refs.resolveRef('refs/remotes/origin/$branch');
        await work.worktree.checkoutNewBranch(
          branch,
          startPoint: remoteTip?.value,
          resetIfExists: true,
        );
      }
      File(join(work.path, 'notes.txt'))
          .writeAsStringSync('work for $branch ($scratchCounter)\n');
      await work.worktree.addAll();
      final GitOid commit = await work.worktree.commit('work on $branch');
      await area.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['HEAD:refs/heads/$branch'],
      );
      return commit;
    } finally {
      await deleteRecursively(Directory(scratch));
    }
  }

  test('the origin becomes a backup remote and the store takes its place',
      () async {
    final GitWorkingRepository upstream = await area.seedUpstream(
      'upstream',
      <String, String>{'readme.md': '# upstream\n'},
      upstreamOnlyBranch: 'upstream-only',
    );
    final GitWorkingRepository clone =
        await area.seedClone(upstream.path, 'clone');
    final GitFileBareRepository store = await area.seedStore('store');

    final GitOid? mainTipBefore =
        await clone.refs.resolveRef('refs/heads/main');
    final GitOid? upstreamMain =
        await clone.refs.resolveRef('refs/remotes/origin/main');
    final GitOid? upstreamOnly =
        await clone.refs.resolveRef('refs/remotes/origin/upstream-only');
    expect(
      await clone.refs.symbolicTarget('refs/remotes/origin/HEAD'),
      'refs/remotes/origin/main',
      reason: 'the fixture carries the usual symbolic head of an origin',
    );
    final GitOid? headTipBefore = await clone.refs.resolveRef('HEAD');

    await clone.remotes.rename('origin', 'archive');
    await clone.remotes.add('origin', store.path);
    await area.engine.fetch(clone, remote: 'origin');

    // The backup remote carries the old URL and the old tracking references,
    // the symbolic head and the fetch refspec included.
    expect(await clone.remotes.getUrl('archive'), upstream.path);
    expect(
      await clone.refs.resolveRef('refs/remotes/archive/main'),
      upstreamMain,
    );
    expect(
      await clone.refs.resolveRef('refs/remotes/archive/upstream-only'),
      upstreamOnly,
    );
    expect(
      await clone.refs.symbolicTarget('refs/remotes/archive/HEAD'),
      'refs/remotes/archive/main',
      reason: 'the symbolic head followed the rename',
    );
    expect(
      await clone.config.get('remote.archive.fetch'),
      '+refs/heads/*:refs/remotes/archive/*',
      reason: 'the fetch refspec followed the rename',
    );

    // origin names the store now; the store is still empty, so nothing is
    // tracked from it yet.
    expect(await clone.remotes.getUrl('origin'), store.path);
    expect(await store.refs.resolveRef('refs/heads/main'), isNull);
    expect(
      await clone.refs.resolveRef('refs/remotes/origin/main'),
      isNull,
      reason: 'an empty store has no branch to track',
    );

    // The rename carried the upstream configuration to the backup name; the
    // rewiring sets the local branch back on origin, which now leads to the
    // store.
    await clone.config.set('branch.main.remote', 'origin');
    expect(await clone.config.get('branch.main.remote'), 'origin');
    expect(await clone.config.get('branch.main.merge'), 'refs/heads/main');

    // The local branches and the head of the clone are untouched.
    expect(await clone.refs.resolveRef('refs/heads/main'), mainTipBefore);
    expect(await clone.refs.resolveRef('HEAD'), headTipBefore);
    expect(await clone.refs.symbolicTarget('HEAD'), 'refs/heads/main');
  });

  for (final bool explicitHead in <bool>[false, true]) {
    test(
        'the fresh tracking references describe the store once it holds work'
        '${explicitHead ? ' with an explicit symbolic HEAD' : ''}', () async {
      final GitWorkingRepository upstream = await area.seedUpstream(
        'upstream',
        <String, String>{'readme.md': '# upstream\n'},
        upstreamOnlyBranch: 'upstream-only',
      );
      final GitWorkingRepository clone =
          await area.seedClone(upstream.path, 'clone');
      final GitFileBareRepository store = await area.seedStore('store');

      await clone.remotes.rename('origin', 'archive');
      await clone.remotes.add('origin', store.path);
      // The rename carried the upstream configuration to the backup name; the
      // rewiring sets the local branch back on origin.
      await clone.config.set('branch.main.remote', 'origin');

      // The store gains a branch from another writer; the exchange brings it
      // over under the origin name.
      final GitOid landed = await landOnBranch(store, 'main');
      await area.engine.fetch(clone, remote: 'origin');
      if (explicitHead) {
        // Reproduce a fetch that also learns the remote's default branch,
        // even when the installed Git does not create this ref itself.
        await pointSymbolicRef(
          clone,
          'refs/remotes/origin/HEAD',
          'refs/remotes/origin/main',
        );
      }

      expect(
        await clone.refs.resolveRef('refs/remotes/origin/main'),
        await store.refs.resolveRef('refs/heads/main'),
      );
      expect(await clone.refs.resolveRef('refs/remotes/origin/main'), landed);
      final String? remoteHead =
          await clone.refs.symbolicTarget('refs/remotes/origin/HEAD');
      expect(remoteHead, anyOf(isNull, 'refs/remotes/origin/main'));
      if (remoteHead != null) {
        expect(await clone.refs.resolveRef('refs/remotes/origin/HEAD'), landed);
      }
      expect(
        (await clone.refs.listRefs(prefix: 'refs/remotes/origin/'))
            .map((GitRef ref) => ref.name),
        unorderedEquals(<String>[
          'refs/remotes/origin/main',
          if (remoteHead != null) 'refs/remotes/origin/HEAD',
        ]),
        reason: 'nothing of the old upstream tracking world is left under '
            'origin',
      );
      expect(await clone.config.get('branch.main.remote'), 'origin');
    });
  }

  test('a repository without origin gains one pointing at the store', () async {
    final GitWorkingRepository source =
        await area.engine.init(area.path('source'), initialBranch: 'main');
    File(join(source.path, 'readme.md')).writeAsStringSync('# source\n');
    await source.worktree.addAll();
    final GitOid commit = await source.worktree.commit('seed the source');
    final GitFileBareRepository store = await area.seedStore('store');

    final GitWorkingRepository clone =
        await area.engine.clone(source.path, area.path('clone'));
    // A remote pointing at an archive the clone never fetches from stays
    // exactly as it is.
    final String archive = area.path('archive');
    await area.engine.initBare(archive, initialBranch: 'main');
    await clone.remotes.add('keep', archive);

    await clone.remotes.rename('origin', 'archive-backup');
    await clone.remotes.add('origin', store.path);
    await area.engine.fetch(clone, remote: 'origin');

    expect(await clone.remotes.getUrl('origin'), store.path);
    expect(
      await clone.refs.resolveRef('refs/remotes/origin/main'),
      isNull,
      reason: 'the store is empty: nothing to track yet',
    );
    expect(
      await clone.remotes.getUrl('keep'),
      archive,
      reason: 'an unrelated remote keeps its name and its url',
    );
    expect(await clone.refs.listRefs(prefix: 'refs/remotes/keep/'), isEmpty);
    expect(
      (await clone.remotes.list()).toSet(),
      <String>{'origin', 'keep', 'archive-backup'},
    );
    expect(await clone.refs.resolveRef('refs/heads/main'), commit);
  });

  test('a locked tracking reference aborts the exchange until it is freed',
      () async {
    final GitWorkingRepository upstream = await area.seedUpstream(
      'upstream',
      <String, String>{'readme.md': '# upstream\n'},
      upstreamOnlyBranch: 'upstream-only',
    );
    final GitWorkingRepository clone =
        await area.seedClone(upstream.path, 'clone');
    final GitFileBareRepository store = await area.seedStore('store');
    await clone.remotes.rename('origin', 'archive');
    await clone.remotes.add('origin', store.path);
    final GitOid first = await landOnBranch(store, 'main');
    await area.engine.fetch(clone, remote: 'origin');
    expect(
      await clone.refs.resolveRef('refs/remotes/origin/main'),
      first,
    );

    // The store gains a branch and advances its main one; a stale lock sits
    // on the tracking reference the exchange alone would write (the branch
    // is new to the clone), so the exchange aborts without finishing.
    final GitOid advanced = await landOnBranch(store, 'main');
    final GitOid landed = await landOnBranch(store, 'side');
    final String gitDir = await clone.gitDir();
    final File staleLock = File(
      join(gitDir, 'refs/remotes/origin/side.lock'),
    );
    await staleLock.parent.create(recursive: true);
    await staleLock.writeAsString('');

    await expectLater(
      area.engine.fetch(clone, remote: 'origin'),
      throwsA(isA<GitCommandException>()),
    );
    expect(
      staleLock.existsSync(),
      isTrue,
      reason: 'the exchange never touches the lock that blocked it',
    );
    expect(
      await clone.refs.resolveRef('refs/remotes/origin/side'),
      isNull,
      reason: 'the locked reference was never written',
    );

    await staleLock.delete();
    await area.engine.fetch(clone, remote: 'origin');

    expect(
      await clone.refs.resolveRef('refs/remotes/origin/main'),
      advanced,
    );
    expect(
      await clone.refs.resolveRef('refs/remotes/origin/side'),
      landed,
    );
  });
}
