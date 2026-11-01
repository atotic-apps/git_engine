@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'landing_support.dart';

void main() {
  group('a landing whose fold conflicts', () {
    test(
        'names the conflicting files and falls back to the base keeping '
        'the uncommitted work', () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final GitFileBareRepository origin = await sandbox.initBare('origin.git');
      final RemoteWriter writer =
          await RemoteWriter.create(sandbox, origin.path, 'writer');
      final GitOid base = await writer.commitOnBranch(
        'main',
        <String, String>{'README.md': 'shared\n'},
        'seed the origin',
      );
      final GitWorkingRepository work =
          await sandbox.clone(origin.path, 'work');
      await work.worktree.checkoutNewBranch('work');

      // An uncommitted change to a file the integration branch edits too.
      writeFile(work.path, 'README.md', 'work side\n');
      final List<int> patch = await work.patches.binaryDiffAgainstWorkTree();
      expect(patch, isNotEmpty);

      final GitOid targetTip = await writer.commitOnBranch(
        'main',
        <String, String>{'README.md': 'target side\n'},
        'edit the file on the integration branch',
      );
      final GitOid commit = await commitAll(work, 'edit the file');
      await sandbox.engine.fetch(work, remote: 'origin');

      // The work branch moves onto the fetched tip and the fold conflicts.
      await work.worktree.reset(
        mode: GitResetMode.hard,
        target: 'refs/remotes/origin/main',
      );
      final GitMergeResult merged = await work.merge.merge(
        commit.value,
        mode: GitMergeMode.noFastForward,
      );
      final List<String> conflicts =
          (merged as GitMergeConflicts).conflictingFiles;
      expect(conflicts, <String>['README.md']);
      expect(await work.merge.isMerging(), isTrue);

      // The attempt is given up: the merge is aborted, the head returns to
      // the base and the saved work becomes an uncommitted diff again.
      await work.merge.abort();
      await work.worktree.reset(mode: GitResetMode.hard, target: base.value);
      final GitApplyResult applied = await work.patches.apply(patch);
      expect(applied, isA<GitApplyApplied>());

      expect(await resolve(work, 'HEAD'), base);
      expect(readFile(work.path, 'README.md'), 'work side\n');
      final List<GitStatusEntry> status = await work.worktree.status();
      expect(status, hasLength(1));
      expect(status.single.path, 'README.md');
      expect(status.single.workTreeState, GitFileState.modified);
      // The target never moved and no work branch leaked onto the remote.
      expect(await resolve(origin, 'refs/heads/main'), targetTip);
      expect(await contentAt(origin, 'main', 'README.md'), 'target side\n');
      expect(await branchNames(origin), <String>['main']);
    });

    test(
        'detects a work tree dirtied after the fold, publishes nothing, '
        'and lands on a retry', () async {
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

      // An uncommitted new file, recorded so a diff captures it.
      writeFile(work.path, 'thing.txt', 'content\n');
      await work.worktree.intentToAdd(<String>['thing.txt']);
      final List<int> patch = await work.patches.binaryDiffAgainstWorkTree();
      final GitOid commit = await commitAll(work, 'add thing.txt');
      await sandbox.engine.fetch(work, remote: 'origin');

      // The target has not moved: the fold is clean.
      await work.worktree.reset(
        mode: GitResetMode.hard,
        target: 'refs/remotes/origin/main',
      );
      final GitMergeResult merged = await work.merge.merge(
        commit.value,
        mode: GitMergeMode.noFastForward,
        message: 'fold the work',
      );
      expect(merged, isA<GitMergeCommit>());
      expect(await work.worktree.isClean(), isTrue);

      // A verification step dirties the tree with a regenerated file.
      writeFile(work.path, 'generated.txt', 'regenerated\n');
      expect(await work.worktree.isClean(), isFalse);

      // Nothing is published and the tree is restored: the regenerated file
      // is dropped, the head returns to the base and the work survives as an
      // uncommitted diff.
      await work.worktree.reset(mode: GitResetMode.hard, target: base.value);
      await work.worktree.clean(directories: true);
      final GitApplyResult applied = await work.patches.apply(patch);
      expect(applied, isA<GitApplyApplied>());

      expect(await resolve(origin, 'refs/heads/main'), base);
      expect(fileExists(work.path, 'generated.txt'), isFalse);
      expect(await resolve(work, 'HEAD'), base);
      expect(readFile(work.path, 'thing.txt'), 'content\n');
      final List<GitStatusEntry> status = await work.worktree.status();
      expect(status, hasLength(1));
      expect(status.single.path, 'thing.txt');
      expect(await branchNames(origin), <String>['main']);

      // A second attempt recommits the same work and lands it.
      final GitOid retry = await commitAll(work, 'add thing.txt');
      await sandbox.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['work:refs/heads/main'],
      );
      expect(await resolve(origin, 'refs/heads/main'), retry);
      expect(await contentAt(origin, 'main', 'thing.txt'), 'content\n');
    });
  });
}
