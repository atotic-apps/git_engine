@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'sources_support.dart';

/// Merging a divergent branch into a work branch and committing the
/// conflicted state as the base a resolution will stand on.
void main() {
  late SourcesSandbox sandbox;

  setUp(() async {
    sandbox = await createSourcesSandbox();
  });

  test(
      'a committed conflict folds both sides into a merge commit that keeps '
      'the markers', () async {
    final String originPath = sandbox.path('origin.git');
    final GitFileBareRepository origin =
        await sandbox.engine.initBare(originPath, initialBranch: 'main');
    await sandbox.pushTip(
      originPath,
      branch: 'main',
      files: <String, String>{'shared.txt': 'base line\n'},
      message: 'base',
    );
    final GitOid sideTip = await sandbox.pushTip(
      originPath,
      branch: 'side',
      files: <String, String>{'shared.txt': 'side line\n'},
      message: 'side change',
    );
    final GitOid mainTip = await sandbox.pushTip(
      originPath,
      branch: 'main',
      files: <String, String>{'shared.txt': 'main line\n'},
      message: 'main change',
    );

    final GitWorkingRepository clone =
        await sandbox.engine.clone(originPath, sandbox.path('clone'));
    await clone.worktree.checkoutNewBranch('work', startPoint: sideTip.value);

    // The work identity lives in the clone's own configuration, so every
    // commit and merge of the session carries it.
    final GitIdentity worker = GitIdentity(
      name: 'Work Keeper',
      email: 'work@example.com',
    );
    await clone.config.set('user.name', worker.name);
    await clone.config.set('user.email', worker.email);

    final GitMergeResult result = await clone.merge.merge(mainTip.value);

    expect(result, isA<GitMergeConflicts>());
    expect(
      (result as GitMergeConflicts).conflictingFiles,
      <String>['shared.txt'],
    );

    // The conflicted state is committed as it stands, markers included: the
    // merge commit becomes the base of the work, never pushed anywhere.
    await clone.worktree.addAll();
    final GitOid mergeCommitOid =
        await clone.worktree.commit('hold both sides');
    final GitCommit mergeCommit =
        await clone.objects.readCommit(mergeCommitOid);
    expect(mergeCommit.parents, <GitOid>[sideTip, mainTip],
        reason: 'the work branch is the first parent, the merged branch the '
            'second');

    final String conflicted =
        File(join(sandbox.path('clone'), 'shared.txt')).readAsStringSync();
    expect(conflicted, contains('<<<<<<<'));
    expect(conflicted, contains('======='));
    expect(conflicted, contains('>>>>>>>'));
    expect(conflicted, contains('side line'));
    expect(conflicted, contains('main line'));

    expect(await clone.worktree.isClean(), isTrue,
        reason: 'the base is committed, the work tree holds nothing');
    expect(await clone.branches.current(), 'work');
    expect(mergeCommit.author, worker);

    expect(await origin.refs.resolveRef('refs/heads/main'), mainTip);
    expect(await origin.refs.resolveRef('refs/heads/side'), sideTip);
    expect(await origin.refs.resolveRef('refs/heads/work'), isNull,
        reason: 'nothing was pushed to the origin');
  });
}
