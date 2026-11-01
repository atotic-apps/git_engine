@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'landing_support.dart';

void main() {
  group('pushing a work branch onto an integration branch', () {
    test('creates the first branch of a bare origin without any commit',
        () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final GitFileBareRepository origin = await sandbox.initBare('origin.git');
      final GitWorkingRepository work =
          await sandbox.clone(origin.path, 'work');
      await work.worktree.checkoutNewBranch('work');
      writeFile(work.path, 'thing.txt', 'content\n');
      final GitOid commit = await commitAll(work, 'add thing.txt');

      await sandbox.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['work:refs/heads/main'],
      );

      expect(await resolve(origin, 'refs/heads/main'), commit);
      expect(await contentAt(origin, 'main', 'thing.txt'), 'content\n');
      // The push aims at the integration branch alone: the remote holds no
      // trace of the work branch it came from.
      expect(await branchNames(origin), <String>['main']);
    });

    test(
        'pushes the work commit straight when the target still names the '
        'base', () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final GitFileBareRepository origin = await sandbox.initBare('origin.git');
      final RemoteWriter writer =
          await RemoteWriter.create(sandbox, origin.path, 'writer');
      final GitOid base = await writer.commitOnBranch(
        'main',
        <String, String>{'seed.txt': 'seed\n'},
        'seed the origin',
      );
      final GitWorkingRepository work =
          await sandbox.clone(origin.path, 'work');
      await work.worktree.checkoutNewBranch('work');
      writeFile(work.path, 'thing.txt', 'content\n');
      final GitOid commit = await commitAll(work, 'add thing.txt');

      await sandbox.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['work:refs/heads/main'],
      );

      // The work commit descends from the target tip: the push was a plain
      // fast-forward and the target now names it.
      expect(await work.history.isAncestor(base, commit), isTrue);
      expect(await resolve(origin, 'refs/heads/main'), commit);
      expect(await contentAt(origin, 'main', 'thing.txt'), 'content\n');
      expect(await branchNames(origin), <String>['main']);
    });

    test(
        'folds an advanced target with a merge commit whose first parent '
        'is the target tip', () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final GitFileBareRepository origin = await sandbox.initBare('origin.git');
      final RemoteWriter writer =
          await RemoteWriter.create(sandbox, origin.path, 'writer');
      await writer.commitOnBranch(
        'main',
        <String, String>{'seed.txt': 'seed\n'},
        'seed the origin',
      );
      final GitWorkingRepository work =
          await sandbox.clone(origin.path, 'work');
      await work.worktree.checkoutNewBranch('work');
      writeFile(work.path, 'thing.txt', 'content\n');
      final GitOid commit = await commitAll(work, 'add thing.txt');

      // The integration branch advances on a disjoint file while the work
      // branch is under way.
      final GitOid targetTip = await writer.commitOnBranch(
        'main',
        <String, String>{'aside.txt': 'aside\n'},
        'advance the integration branch',
      );
      await sandbox.engine.fetch(work, remote: 'origin');
      expect(await resolve(work, 'refs/remotes/origin/main'), targetTip);

      // The work branch moves onto the fetched tip, then the work commit is
      // folded with a merge commit: the target tip is its first parent, the
      // work commit its second.
      await work.worktree.reset(
        mode: GitResetMode.hard,
        target: 'refs/remotes/origin/main',
      );
      final GitMergeResult merged = await work.merge.merge(
        commit.value,
        mode: GitMergeMode.noFastForward,
        message: 'fold the work',
      );
      await sandbox.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['work:refs/heads/main'],
      );

      final GitOid mergeCommit = (merged as GitMergeCommit).commit;
      expect(await resolve(origin, 'refs/heads/main'), mergeCommit);
      expect(
        await parentsOf(origin, 'refs/heads/main'),
        <GitOid>[targetTip, commit],
      );
      expect(await contentAt(origin, 'main', 'thing.txt'), 'content\n');
      expect(await contentAt(origin, 'main', 'aside.txt'), 'aside\n');
      expect(await branchNames(origin), <String>['main']);
      expect(await work.worktree.isClean(), isTrue);
    });

    test(
        'lands onto an integration branch named master without ever '
        'creating main', () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final GitFileBareRepository origin = await sandbox.initBare(
        'origin.git',
        initialBranch: 'master',
      );
      final RemoteWriter writer =
          await RemoteWriter.create(sandbox, origin.path, 'writer');
      await writer.commitOnBranch(
        'master',
        <String, String>{'seed.txt': 'seed\n'},
        'seed the origin',
      );
      final GitWorkingRepository work =
          await sandbox.clone(origin.path, 'work');
      await work.worktree.checkoutNewBranch('work');
      writeFile(work.path, 'thing.txt', 'content\n');
      final GitOid commit = await commitAll(work, 'add thing.txt');

      // The integration branch advances while the work branch is under way:
      // the fold is made against the fetched tip of master.
      final GitOid targetTip = await writer.commitOnBranch(
        'master',
        <String, String>{'aside.txt': 'aside\n'},
        'advance the integration branch',
      );
      await sandbox.engine.fetch(work, remote: 'origin');
      await work.worktree.reset(
        mode: GitResetMode.hard,
        target: 'refs/remotes/origin/master',
      );
      await work.merge.merge(
        commit.value,
        mode: GitMergeMode.noFastForward,
        message: 'fold the work',
      );
      await sandbox.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['work:refs/heads/master'],
      );

      expect(
        await parentsOf(origin, 'refs/heads/master'),
        <GitOid>[targetTip, commit],
      );
      expect(await contentAt(origin, 'master', 'thing.txt'), 'content\n');
      expect(await contentAt(origin, 'master', 'aside.txt'), 'aside\n');
      // No `main` ref ever appeared on the remote.
      expect(await branchNames(origin), <String>['master']);
    });

    test('refetches and retries when the target refuses the push', () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final GitFileBareRepository origin = await sandbox.initBare('origin.git');
      final RemoteWriter writer =
          await RemoteWriter.create(sandbox, origin.path, 'writer');
      await writer.commitOnBranch(
        'main',
        <String, String>{'seed.txt': 'seed\n'},
        'seed the origin',
      );
      final GitWorkingRepository work =
          await sandbox.clone(origin.path, 'work');
      await work.worktree.checkoutNewBranch('work');
      writeFile(work.path, 'thing.txt', 'content\n');
      final GitOid commit = await commitAll(work, 'add thing.txt');
      await sandbox.engine.fetch(work, remote: 'origin');

      // Another writer lands while the first attempt is on its way: the
      // push, a fast-forward by construction, is refused by the remote.
      final GitOid rival = await writer.commitOnBranch(
        'main',
        <String, String>{'late.txt': 'late\n'},
        'concurrent landing',
      );
      await expectLater(
        sandbox.engine.push(
          work,
          remote: 'origin',
          refspecs: <String>['work:refs/heads/main'],
        ),
        throwsA(isA<GitPushRejectedException>()),
      );
      // The rival landing stands; the refused push changed nothing.
      expect(await resolve(origin, 'refs/heads/main'), rival);

      // The retry refetches, folds the new tip with the target tip as first
      // parent, and lands.
      await sandbox.engine.fetch(work, remote: 'origin');
      await work.worktree.reset(
        mode: GitResetMode.hard,
        target: 'refs/remotes/origin/main',
      );
      await work.merge.merge(
        commit.value,
        mode: GitMergeMode.noFastForward,
        message: 'fold the work',
      );
      await sandbox.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['work:refs/heads/main'],
      );

      expect(
        await parentsOf(origin, 'refs/heads/main'),
        <GitOid>[rival, commit],
      );
      expect(await contentAt(origin, 'main', 'thing.txt'), 'content\n');
      expect(await contentAt(origin, 'main', 'late.txt'), 'late\n');
      expect(await branchNames(origin), <String>['main']);
    });

    test(
        'finds nothing to do when the work is already an ancestor of the '
        'target', () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final GitFileBareRepository origin = await sandbox.initBare('origin.git');
      final RemoteWriter writer =
          await RemoteWriter.create(sandbox, origin.path, 'writer');
      await writer.commitOnBranch(
        'main',
        <String, String>{'seed.txt': 'seed\n'},
        'seed the origin',
      );
      final GitWorkingRepository work =
          await sandbox.clone(origin.path, 'work');
      await work.worktree.checkoutNewBranch('work');
      writeFile(work.path, 'thing.txt', 'content\n');
      final GitOid commit = await commitAll(work, 'add thing.txt');
      await sandbox.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['work:refs/heads/main'],
      );
      final GitOid targetBefore = await resolve(origin, 'refs/heads/main');

      // A repeated attempt: the fetched target already contains the work.
      await sandbox.engine.fetch(work, remote: 'origin');
      final GitOid target = await resolve(work, 'refs/remotes/origin/main');
      expect(await work.history.isAncestor(commit, target), isTrue);
      expect(
        await work.merge.merge(commit.value),
        isA<GitMergeUpToDate>(),
      );
      await sandbox.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['work:refs/heads/main'],
      );

      expect(await resolve(origin, 'refs/heads/main'), targetBefore);
      expect(await branchNames(origin), <String>['main']);
    });
  });
}
