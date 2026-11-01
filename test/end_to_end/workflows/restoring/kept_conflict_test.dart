@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'restoring_support.dart';

/// A fold the sides cannot reconcile is left undone: the repository is
/// reopened still inside the fold, the files keep the conflict markers, and
/// only giving the fold up restores the state the work was in before it.
void main() {
  test('a conflicted fold left undone is found intact on reopen', () async {
    final RestoreSandbox sandbox = await RestoreSandbox.create();
    final GitFileBareRepository origin = await sandbox.seedBare(
      'origin.git',
      <String, String>{'shared.txt': 'base line\n'},
    );
    final GitWorkingRepository copy = await sandbox.clone(origin.path, 'copy');

    // The work copy moves the shared file its own way and commits the move.
    await copy.worktree.checkoutNewBranch('work');
    writeFile(copy.path, 'shared.txt', 'local side\n');
    final GitOid workTip = await commitAll(copy, 'move the shared file');

    // Another writer moves the same file the other way on the remote.
    final AdvanceWriter writer =
        await AdvanceWriter.create(sandbox, origin.path);
    await writer.commitOnFile(
      'shared.txt',
      'remote side\n',
      'move the shared file the other way',
    );
    final GitOid remoteTip = await resolve(origin, 'refs/heads/main');
    await sandbox.engine.fetch(copy, remote: 'origin');

    // The fold cannot reconcile the two moves: it stays in progress, never
    // aborted while the test is reading the state.
    final GitMergeResult folded = await copy.merge.merge(
      'refs/remotes/origin/main',
      mode: GitMergeMode.noFastForward,
    );
    expect(folded, isA<GitMergeConflicts>());
    expect(
      (folded as GitMergeConflicts).conflictingFiles,
      <String>['shared.txt'],
    );

    // Reopened from its path, the copy is exactly where the fold left it:
    // still folding, markers on disk, the path unmerged and the fold
    // uncommitted.
    final GitWorkingRepository reopened =
        await sandbox.engine.openWorking(copy.path);
    expect(await reopened.merge.isMerging(), isTrue);
    final String here = readFile(reopened.path, 'shared.txt');
    expect(here, contains('<<<<<<<'));
    expect(here, contains('======='));
    expect(here, contains('>>>>>>>'));
    expect(
      await reopened.revisions.resolveRevision('HEAD'),
      workTip,
      reason: 'the fold left the head at the commit the branch already had',
    );
    final List<GitStatusEntry> status = await reopened.worktree.status();
    expect(status, hasLength(1));
    expect(status.single.path, 'shared.txt');
    expect(status.single.workTreeState, GitFileState.unmerged);
    expect(await reopened.worktree.isClean(), isFalse);
    // The fold was never published: the branch it read from is untouched.
    expect(await resolve(origin, 'refs/heads/main'), remoteTip);

    // Giving the fold up restores the state the work was in before it.
    await reopened.merge.abort();
    expect(await reopened.merge.isMerging(), isFalse);
    expect(await resolve(reopened, 'HEAD'), workTip);
    expect(readFile(reopened.path, 'shared.txt'), 'local side\n');
    expect(await reopened.worktree.isClean(), isTrue);
  });
}
