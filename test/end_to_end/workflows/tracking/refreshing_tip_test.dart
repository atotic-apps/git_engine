@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'tracking_support.dart';

/// Folding the current tip of the integration branch into a branch a work
/// copy carries: the fold is a merge commit even when a fast-forward would
/// be possible, the merged-in tip keeps its second-parent place, the author
/// is the identity the copy holds itself, and a second fold with an
/// unchanged upstream has nothing to do.
void main() {
  test('folds the fetched tip even when a fast-forward would be possible',
      () async {
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
    // The copy carries its own identity, set after the clone: the fold is
    // authored by the copy, whose configuration the repository context
    // holds.
    final GitIdentity keeper = GitIdentity(
      name: 'Copy Keeper',
      email: 'keeper@copy.test',
    );
    await copy.config.set('user.name', keeper.name);
    await copy.config.set('user.email', keeper.email);
    writeFile(copy.path, 'work.md', 'copy content\n');
    final GitOid copyTip = await commitAll(copy, 'working copy content');

    // The integration branch advances on the remote; the tip is fetched so
    // the fold reads it at where it stands now.
    final GitOid integrationTip = await setter.commitOnBranch(
      'main',
      <String, String>{'integration.md': 'integration\n'},
      'integration content',
    );
    expect(integrationTip, isNot(base));
    await sandbox.engine.fetch(copy, remote: 'origin');

    final GitMergeResult merged = await copy.merge
        .merge('refs/remotes/origin/main', mode: GitMergeMode.noFastForward);

    final GitOid fold = (merged as GitMergeCommit).commit;
    final GitCommit record = await copy.objects.readCommit(fold);
    // The branch tip is the first parent and the folded tip the second:
    // nothing reverted the branch to merge in the other direction.
    expect(record.parents, <GitOid>[copyTip, integrationTip]);
    expect(record.parents.first, isNot(integrationTip));
    expect(record.author, keeper);
    expect(
      await copy.history.lastCommitTouching(
        'integration.md',
        rev: fold.value,
      ),
      isNotNull,
    );
    expect(await copy.contentAt(fold, 'integration.md'), 'integration\n');
    // The pushed branch is a plain descendant of the fetched tip by
    // construction: the push reaches the branch without any refusal.
    await sandbox.engine.push(
      copy,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/copy-branch'],
    );
    expect(await resolve(origin, 'refs/heads/copy-branch'), fold);
    // The integration branch never moved backwards: the fold went onto the
    // work branch alone.
    expect(await resolve(origin, 'refs/heads/main'), integrationTip);
  });

  test('a second fold of an unchanged upstream has nothing to do', () async {
    final TrackingSandbox sandbox = await TrackingSandbox.create();
    final GitFileBareRepository origin = await sandbox.initBare('origin.git');
    final TipSetter setter = await TipSetter.create(sandbox, origin.path);
    await setter.commitOnBranch(
      'main',
      <String, String>{'readme.md': '# project\n'},
      'seed the origin',
    );
    final GitWorkingRepository copy = await sandbox.clone(
      origin.path,
      'copy',
    );
    writeFile(copy.path, 'work.md', 'copy content\n');
    final GitOid copyTip = await commitAll(copy, 'working copy content');
    // The integration branch advances while the copy carries its own
    // commit: the first fold is a merge commit of the two tips.
    final GitOid integrationTip = await setter.commitOnBranch(
      'main',
      <String, String>{'aside.md': 'aside\n'},
      'integration content',
    );
    expect(integrationTip, isNot(copyTip));
    await sandbox.engine.fetch(copy, remote: 'origin');
    final GitMergeResult first = await copy.merge
        .merge('refs/remotes/origin/main', mode: GitMergeMode.noFastForward);
    expect(first, isA<GitMergeCommit>());

    // No new tip arrived: the branch already carries the merged-in tip, so
    // folding again reports up-to-date and no second commit appears.
    await sandbox.engine.fetch(copy, remote: 'origin');
    final GitMergeResult second = await copy.merge
        .merge('refs/remotes/origin/main', mode: GitMergeMode.noFastForward);
    expect(second, isA<GitMergeUpToDate>());
    final GitOid head = await resolve(copy, 'HEAD');
    expect(head, isNot(copyTip));
    final GitCommit record = await copy.objects.readCommit(head);
    expect(record.parents.length, 2, reason: 'still the single fold commit');
    expect(await copy.worktree.isClean(), isTrue);
  });
}

extension on GitWorkingRepository {
  /// Content of [path] as [commit] names it.
  Future<String?> contentAt(GitOid commit, String path) async {
    final GitOid? blob =
        await revisions.resolveRevision('${commit.value}:$path');
    if (blob == null) {
      return null;
    }
    return String.fromCharCodes(await objects.readBlob(blob));
  }
}
