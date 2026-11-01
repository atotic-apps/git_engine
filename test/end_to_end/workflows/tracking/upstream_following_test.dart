@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'tracking_support.dart';

/// A local branch keeps up with the branch of the bare it carries: it is
/// spelled on the fetched tip and made to track the matching remote-tracking
/// branch, and a sync folds the next remote tip over without ever leaving
/// the tracked branch.
void main() {
  group('a local branch spelled on its upstream', () {
    test('follows the fetched tip once it tracks the tracking branch',
        () async {
      final TrackingSandbox sandbox = await TrackingSandbox.create();
      final GitFileBareRepository origin = await sandbox.initBare('origin.git');
      final TipSetter setter = await TipSetter.create(sandbox, origin.path);
      final GitOid first = await setter.commitOnBranch(
        'main',
        <String, String>{'readme.md': '# project\n'},
        'seed the origin',
      );

      final GitWorkingRepository copy = await sandbox.clone(
        origin.path,
        'copy',
      );
      await copy.worktree.checkoutNewBranch(
        'main',
        startPoint: 'refs/remotes/origin/main',
        resetIfExists: true,
      );
      await trackUpstream(copy, 'main');

      // The local branch reads back as follower of the tracking branch,
      // abbreviated the way git spells it in status lines.
      expect(
        await copy.revisions.symbolicFullName('@{upstream}'),
        'refs/remotes/origin/main',
      );
      expect(
        await copy.revisions.symbolicFullName(
          '@{upstream}',
          abbreviated: true,
        ),
        'origin/main',
      );
      expect(await resolve(copy, 'HEAD'), first);

      // The branch advances on the remote while the copy is on its way.
      final GitOid second = await setter.commitOnBranch(
        'main',
        <String, String>{'note.md': 'newer\n'},
        'advance the tracked branch',
      );
      await sandbox.engine.fetch(copy, remote: 'origin');

      final GitMergeResult merged = await copy.merge
          .merge('refs/remotes/origin/main', mode: GitMergeMode.auto);

      // A plain fast-forward moved the branch tip; the copy stays checked
      // out on its branch and its upstream is untouched.
      expect(merged, isA<GitMergeFastForward>());
      expect(await resolve(copy, 'HEAD'), second);
      expect(await copy.branches.current(), 'main');
      expect(
        await copy.revisions.symbolicFullName(
          '@{upstream}',
          abbreviated: true,
        ),
        'origin/main',
      );
      expect(readFile(copy.path, 'note.md'), 'newer\n');
      expect(await copy.worktree.isClean(), isTrue);
      expect(await branchNames(origin), <String>['main']);
    });

    test('each copy follows only the upstream of its own branch', () async {
      final TrackingSandbox sandbox = await TrackingSandbox.create();
      final GitFileBareRepository origin = await sandbox.initBare('origin.git');
      final TipSetter setter = await TipSetter.create(sandbox, origin.path);
      await setter.commitOnBranch(
        'main',
        <String, String>{'readme.md': '# project\n'},
        'seed the origin',
      );
      final GitOid sideTip = await setter.commitOnBranch(
        'side',
        <String, String>{'side.md': 'side work\n'},
        'the side branch advances',
      );

      // One copy follows the integration branch, the other the named side
      // branch; each tracking branch is spelled on its own remote-tracking
      // state.
      final GitWorkingRepository onMain = await sandbox.clone(
        origin.path,
        'on-main',
      );
      final GitWorkingRepository onSide = await sandbox.clone(
        origin.path,
        'on-side',
        branch: 'side',
      );
      await trackUpstream(onMain, 'main');
      await trackUpstream(onSide, 'side');

      expect(
        await onSide.revisions.symbolicFullName(
          '@{upstream}',
          abbreviated: true,
        ),
        'origin/side',
      );
      expect(await resolve(onSide, 'HEAD'), sideTip);
      expect(await onSide.branches.current(), 'side');

      // The tracked branches advance in both directions on the remote; each
      // copy folds its own tip over and picks up nothing from the other
      // branch.
      final GitOid mainTip = await setter.commitOnBranch(
        'main',
        <String, String>{'main.md': 'integration\n'},
        'the integration branch advances',
      );
      expect(
        await setter.commitOnBranch(
          'side',
          <String, String>{'side2.md': 'side again\n'},
          'the side branch advances again',
        ),
        isNot(sideTip),
      );
      await sandbox.engine.fetch(onMain, remote: 'origin');
      await sandbox.engine.fetch(onSide, remote: 'origin');
      await onMain.merge
          .merge('refs/remotes/origin/main', mode: GitMergeMode.auto);
      await onSide.merge
          .merge('refs/remotes/origin/side', mode: GitMergeMode.auto);

      expect(await resolve(onMain, 'HEAD'), mainTip);
      expect(await onMain.worktree.isClean(), isTrue);
      expect(await onSide.worktree.isClean(), isTrue);
      // The integration tip removes nothing from the side copy: its branch
      // keeps the side content, and the side file of the integration branch
      // never appears there.
      expect(fileExists(onSide.path, 'side2.md'), isTrue);
      expect(fileExists(onSide.path, 'main.md'), isFalse);
      expect(await onSide.branches.current(), 'side');
      expect(await onMain.branches.current(), 'main');
    });
  });
}
