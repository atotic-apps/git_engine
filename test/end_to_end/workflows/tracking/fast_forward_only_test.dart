@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'tracking_support.dart';

/// A sync that may only fast-forward: the checked-out branch moves onto the
/// remote tip when it is a descendant, is refused when the histories
/// diverge, and is refused when the branch it tracked has disappeared from
/// the remote — and in every refusal the copy keeps its state untouched.
void main() {
  test('a diverged copy is refused and keeps its state untouched', () async {
    final TrackingSandbox sandbox = await TrackingSandbox.create();
    final GitFileBareRepository origin = await sandbox.initBare('origin.git');
    final TipSetter setter = await TipSetter.create(sandbox, origin.path);
    final GitOid base = await setter.commitOnBranch(
      'main',
      <String, String>{'readme.md': '# project\n'},
      'seed the origin',
    );
    final GitWorkingRepository copy = await sandbox.clone(
      origin.path,
      'copy',
    );
    writeFile(copy.path, 'local.md', 'kept locally\n');
    final GitOid localTip = await commitAll(copy, 'keep a local commit');

    // The tracked branch advances elsewhere while the copy diverged: no
    // fast-forward can reach the new tip any more.
    final GitOid remoteTip = await setter.commitOnBranch(
      'main',
      <String, String>{'note.md': 'newer\n'},
      'advance the tracked branch',
    );
    await sandbox.engine.fetch(copy, remote: 'origin');

    final List<GitStatusEntry> statusBefore = await copy.worktree.status();
    await expectLater(
      copy.merge.merge(
        'refs/remotes/origin/main',
        mode: GitMergeMode.fastForwardOnly,
      ),
      throwsA(isA<GitMergeNotFastForwardException>()),
    );
    // Nothing was reset or merged: the copy keeps its local commit on top
    // of the old base, its files and its cleanliness exactly as they were.
    expect(await resolve(copy, 'HEAD'), localTip);
    expect(readFile(copy.path, 'readme.md'), '# project\n');
    expect(readFile(copy.path, 'local.md'), 'kept locally\n');
    expect(await copy.worktree.status(), statusBefore);
    expect(await copy.worktree.isClean(), isTrue);
    expect(await copy.branches.current(), 'main');
    // The remote branch is intact and nothing leaked onto it.
    expect(await resolve(origin, 'refs/heads/main'), remoteTip);
    expect(await branchNames(origin), <String>['main']);
    expect(base, isNot(remoteTip));
  });

  test(
      'merging a tracking branch the remote withdrew is refused and leaves '
      'the copy checked out where it was', () async {
    final TrackingSandbox sandbox = await TrackingSandbox.create();
    final GitFileBareRepository origin = await sandbox.initBare('origin.git');
    final TipSetter setter = await TipSetter.create(sandbox, origin.path);
    await setter.commitOnBranch(
      'main',
      <String, String>{'readme.md': '# project\n'},
      'seed the origin',
    );
    // Another branch not checked out here disappears during the sync.
    final GitOid sideTip = await setter.commitOnBranch(
      'side',
      <String, String>{'side.md': 'side work\n'},
      'give the branch a tip',
    );
    final GitWorkingRepository copy = await sandbox.clone(
      origin.path,
      'copy',
      branch: 'side',
    );
    await expectLater(
      copy.revisions.resolveRevision('refs/remotes/origin/side'),
      isNotNull,
    );

    // The branch is withdrawn on the remote, then the sync prunes the stale
    // tracking state.
    await origin.branches.delete('side', force: true);
    await sandbox.engine.fetch(copy, remote: 'origin', prune: true);
    expect(
      await copy.revisions.resolveRevision('refs/remotes/origin/side'),
      isNull,
    );

    final GitOid headBefore = await resolve(copy, 'HEAD');
    await expectLater(
      copy.merge.merge(
        'refs/remotes/origin/side',
        mode: GitMergeMode.fastForwardOnly,
      ),
      throwsA(isA<GitException>()),
    );
    // The copy kept reading the branch tip it held, no branch was switched
    // and no merge was started.
    expect(await resolve(copy, 'HEAD'), headBefore);
    expect(await resolve(copy, 'HEAD'), sideTip);
    expect(await copy.branches.current(), 'side');
    expect(readFile(copy.path, 'side.md'), 'side work\n');
    expect(await copy.worktree.isClean(), isTrue);
    expect(await copy.merge.isMerging(), isFalse);
  });
}
