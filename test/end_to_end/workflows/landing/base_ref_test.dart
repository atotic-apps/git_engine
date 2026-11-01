@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'landing_support.dart';

void main() {
  group('pushing onto a branch the base ref names', () {
    test(
        'creates the branch at the work commit when the base has not '
        'moved', () async {
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

      // The recorded base is still the tip of the integration branch: the
      // work commit is pushed as is onto the named branch, creating it.
      await sandbox.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['work:refs/heads/incoming'],
      );

      expect(await resolve(origin, 'refs/heads/incoming'), commit);
      expect(
        await parentsOf(origin, 'refs/heads/incoming'),
        <GitOid>[base],
      );
      expect(await contentAt(origin, 'incoming', 'thing.txt'), 'content\n');
      // The integration branch itself is untouched.
      expect(await resolve(origin, 'refs/heads/main'), base);
    });

    test('folds the tip the base ref names when it has moved', () async {
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

      // The integration branch advances twice while the work branch is under
      // way; the base ref now names the second tip.
      await writer.commitOnBranch(
        'main',
        <String, String>{'a.md': 'a\n'},
        'first advance',
      );
      final GitOid moved = await writer.commitOnBranch(
        'main',
        <String, String>{'b.md': 'b\n'},
        'second advance',
      );

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
        refspecs: <String>['work:refs/heads/incoming'],
      );

      // The fold carries the moved tip as first parent, its content included.
      expect(
        await parentsOf(origin, 'refs/heads/incoming'),
        <GitOid>[moved, commit],
      );
      expect(await contentAt(origin, 'incoming', 'thing.txt'), 'content\n');
      expect(await contentAt(origin, 'incoming', 'a.md'), 'a\n');
      expect(await contentAt(origin, 'incoming', 'b.md'), 'b\n');
    });

    test('re-reads the moved base on the retry and drops the stale fold',
        () async {
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

      // The first attempt reads the first advance, folds it, and is refused:
      // the branch moved again before the push.
      await writer.commitOnBranch(
        'main',
        <String, String>{'a.md': 'a\n'},
        'first advance',
      );
      await sandbox.engine.fetch(work, remote: 'origin');
      await work.worktree.reset(
        mode: GitResetMode.hard,
        target: 'refs/remotes/origin/main',
      );
      await work.merge.merge(
        commit.value,
        mode: GitMergeMode.noFastForward,
        message: 'stale fold',
      );
      await writer.commitOnBranch(
        'main',
        <String, String>{'b.md': 'b\n'},
        'second advance',
      );
      await expectLater(
        sandbox.engine.push(
          work,
          remote: 'origin',
          refspecs: <String>['work:refs/heads/main'],
        ),
        throwsA(isA<GitPushRejectedException>()),
      );

      // The retry reads the base again: it folds the fresh tip, whose content
      // is carried in, and the stale fold is never pushed.
      final GitOid fresh = await resolve(origin, 'refs/heads/main');
      await sandbox.engine.fetch(work, remote: 'origin');
      await work.worktree.reset(
        mode: GitResetMode.hard,
        target: 'refs/remotes/origin/main',
      );
      final GitMergeResult merged = await work.merge.merge(
        commit.value,
        mode: GitMergeMode.noFastForward,
        message: 'fresh fold',
      );
      await sandbox.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['work:refs/heads/main'],
      );

      expect(
        await parentsOf(origin, 'refs/heads/main'),
        <GitOid>[fresh, commit],
      );
      expect(
        await parentsOf(origin, 'refs/heads/main'),
        isNot(contains((merged as GitMergeCommit).commit)),
      );
      expect(await contentAt(origin, 'main', 'a.md'), 'a\n');
      expect(await contentAt(origin, 'main', 'b.md'), 'b\n');
      expect(await contentAt(origin, 'main', 'thing.txt'), 'content\n');
    });
  });

  group('advancing a companion clone', () {
    test(
        'moves onto the new tip of the noted branch and back onto the noted '
        'commit', () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final GitFileBareRepository other = await sandbox.initBare(
        'other.git',
      );
      final RemoteWriter writer =
          await RemoteWriter.create(sandbox, other.path, 'other-writer');
      final GitOid noted = await writer.commitOnBranch(
        'main',
        <String, String>{'lib.md': '# other\n'},
        'seed the companion',
      );
      final GitWorkingRepository clone =
          await sandbox.clone(other.path, 'companion');
      expect(await resolve(clone, 'HEAD'), noted);

      // The companion repository advances while the clone works.
      final GitOid moved = await writer.commitOnBranch(
        'main',
        <String, String>{'late.md': 'late\n'},
        'advance the companion',
      );

      // The clone is advanced onto the fetched tip of the noted branch.
      await sandbox.engine.fetch(clone, remote: 'origin');
      await clone.worktree.reset(
        mode: GitResetMode.hard,
        target: 'refs/remotes/origin/main',
      );
      expect(await resolve(clone, 'HEAD'), moved);
      expect(await resolve(clone, 'HEAD'), isNot(noted));
      expect(readFile(clone.path, 'late.md'), 'late\n');

      // Rolling the attempt back brings the clone to its noted commit again.
      await clone.worktree.reset(mode: GitResetMode.hard, target: noted.value);
      expect(await resolve(clone, 'HEAD'), noted);
      expect(fileExists(clone.path, 'late.md'), isFalse);
    });

    test('follows a branch the companion named itself, whatever its name',
        () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final GitFileBareRepository other = await sandbox.initBare(
        'other.git',
        initialBranch: 'master',
      );
      final RemoteWriter writer =
          await RemoteWriter.create(sandbox, other.path, 'other-writer');
      final GitOid noted = await writer.commitOnBranch(
        'master',
        <String, String>{'lib.md': '# other\n'},
        'seed the companion',
      );
      final GitWorkingRepository clone =
          await sandbox.clone(other.path, 'companion');

      // The companion gains a branch of its own and advances it.
      final GitOid tip = await writer.commitOnBranch(
        'incoming',
        <String, String>{'note.md': 'landed\n'},
        'land on the named branch',
      );

      // The clone follows the tip of that branch, not the one the clone was
      // started from.
      await sandbox.engine.fetch(clone, remote: 'origin');
      await clone.worktree.reset(
        mode: GitResetMode.hard,
        target: 'refs/remotes/origin/incoming',
      );
      expect(await resolve(clone, 'HEAD'), tip);
      expect(await resolve(clone, 'HEAD'), isNot(noted));
      expect(readFile(clone.path, 'note.md'), 'landed\n');
    });
  });
}
