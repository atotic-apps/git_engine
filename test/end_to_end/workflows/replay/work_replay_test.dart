@Tags(['git'])
library;

import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'sandbox.dart';

/// Replaying uncommitted work onto a new tip of the same branch: the work,
/// captured as a binary patch of the work tree against its base — new files
/// neither staged nor touched — is moved onto the moment the tip reached
/// while it was being made.
///
/// The replay evaluates the captured patch against the new tip through git
/// itself: a clean three-way apply carries the work onto the new base, a file
/// both sides changed leaves conflict markers instead of losing the work, and
/// a patch git refuses leaves the clone exactly where the replay started so
/// the work can rest on its earlier base intact. Files created at work stay
/// untracked all along, the move of the base never touches them.
void main() {
  late ReplaySandbox sandbox;
  late GitWorkingRepository seed;
  late GitFileBareRepository origin;
  late GitWorkingRepository work;
  late GitOid base;

  /// Work tree root of the clone the replay works on.
  late String workPath;

  setUp(() async {
    sandbox = await ReplaySandbox.create();
    origin = await sandbox.initBare('origin.git');
    seed = await sandbox.initWorking('seed');
    await seed.remotes.add('origin', origin.path);
    base = await sandbox.commit(
      seed,
      <String, String>{
        'readme.txt': 'base\n',
        'content.txt': 'content\n',
        'epsilon.txt': 'e0\n',
      },
      'base',
    );
    await sandbox.engine.push(
      seed,
      remote: 'origin',
      refspecs: const <String>['main:refs/heads/main'],
    );
    work = await sandbox.clone(origin.path, 'work');
    workPath = sandbox.path('work');
    await sandbox.engine.fetch(work, remote: 'origin');
  });

  /// A change of another [seed] clone: reachable commits go to the branch of
  /// the remote, then the work clone fetches, and [GitOid] is the new tip.
  Future<GitOid> advance(Map<String, String> files) async {
    await sandbox.commit(seed, files, 'a change while the work was in flight');
    await sandbox.engine.push(
      seed,
      remote: 'origin',
      refspecs: const <String>['main:refs/heads/main'],
    );
    await sandbox.engine.fetch(work, remote: 'origin');
    return (await work.revisions.resolveRevision('origin/main'))!;
  }

  /// Captures the uncommitted work of [work] against [at]: one binary patch
  /// of the work tree changes git already considers tracked, so files created
  /// at work stay untracked and survive the replay untouched.
  Future<Uint8List> workPatch(GitOid at) async =>
      work.patches.binaryDiffFromTree(
        (await work.objects.readCommit(at)).tree,
      );

  test('carries the uncommitted work, new files included, onto the new tip',
      () async {
    final GitOid tip = await advance(
      <String, String>{'content.txt': 'changed on the origin\n'},
    );
    sandbox.write(workPath, 'readme.txt', 'changed at work\n');
    sandbox.write(workPath, 'extra.txt', 'a new file\n');
    final Uint8List patch = await workPatch(base);

    // The tip advanced beyond the base while the work stayed local: the
    // replay moves the base of the clone on the tip, then applies the work
    // patch on it.
    await work.worktree.reset(mode: GitResetMode.hard, target: tip.value);
    final GitApplyResult result = await work.patches.apply(
      patch,
      threeWay: true,
    );

    expect(result, isA<GitApplyApplied>());
    expect(
      sandbox.readText(workPath, 'readme.txt'),
      'changed at work\n',
    );
    expect(
      sandbox.readText(workPath, 'extra.txt'),
      'a new file\n',
    );
    expect(
      sandbox.readText(workPath, 'content.txt'),
      'changed on the origin\n',
    );
    // The new file stayed untracked through the move of the base.
    expect(
      await sandbox.ok(
        workPath,
        const <String>['ls-files', '--others', '--exclude-standard'],
      ),
      'extra.txt',
    );
    // The clone stands on the advanced tip, the work unstaged upon it.
    expect(await work.revisions.resolveRevision('HEAD'), tip);
    expect(
      await work.patches.changedPathsFromTree(
        (await work.objects.readCommit(tip)).tree,
        kinds: <GitChangeKind>{GitChangeKind.modified},
      ),
      contains('readme.txt'),
    );
    // Nothing traveled back to the remote: the tip of the branch is the work
    // the replay moved the clone on, pushed by no one since.
    expect(await origin.revisions.resolveRevision('main'), tip);
  });
  test('lands the work unstaged, the index standing on the new base', () async {
    final GitOid tip = await advance(
      <String, String>{'content.txt': 'changed on the origin\n'},
    );
    sandbox.write(workPath, 'readme.txt', 'changed at work\n');
    sandbox.write(workPath, 'extra.txt', 'a new file\n');
    final Uint8List patch = await workPatch(base);

    await work.worktree.reset(mode: GitResetMode.hard, target: tip.value);
    final GitApplyResult result = await work.patches.apply(
      patch,
      threeWay: true,
    );

    expect(result, isA<GitApplyApplied>());
    // A three-way apply updates the index too: the replayed work is staged
    // against the new base right after it.
    final GitOid tipTree = (await work.objects.readCommit(tip)).tree;
    expect(
      await work.patches.changedPathsAgainstIndex(tipTree),
      <String>['readme.txt'],
    );

    // The reset that follows hands the work over unstaged: the index goes
    // back to the new base while the work tree keeps everything.
    await work.worktree.reset(mode: GitResetMode.mixed, target: tip.value);
    expect(await work.patches.changedPathsAgainstIndex(tipTree), isEmpty);
    final List<GitStatusEntry> status = await work.worktree.status();
    final GitStatusEntry readme = status.singleWhere(
      (GitStatusEntry entry) => entry.path == 'readme.txt',
    );
    expect(readme.code, ' M');
    expect(readme.isIndexed, isFalse);
    final GitStatusEntry extra = status.singleWhere(
      (GitStatusEntry entry) => entry.path == 'extra.txt',
    );
    expect(extra.isUntracked, isTrue);
    expect(sandbox.readText(workPath, 'readme.txt'), 'changed at work\n');
    expect(sandbox.readText(workPath, 'extra.txt'), 'a new file\n');
    expect(await work.revisions.resolveRevision('HEAD'), tip);
  });

  test('keeps the conflict markers of a file both sides changed', () async {
    final GitOid tip = await advance(
      <String, String>{'readme.txt': 'changed on the origin\n'},
    );
    sandbox.write(workPath, 'readme.txt', 'changed at work\n');
    final Uint8List patch = await workPatch(base);

    await work.worktree.reset(mode: GitResetMode.hard, target: tip.value);
    final GitApplyResult result = await work.patches.apply(
      patch,
      threeWay: true,
    );

    expect(result, isA<GitApplyConflicted>());
    expect((result as GitApplyConflicted).paths, <String>['readme.txt']);
    // The clone stayed on the new tip; the file carries both sides behind the
    // markers, and no unmerged entry survives the index reset that follows.
    expect(await work.revisions.resolveRevision('HEAD'), tip);
    final String readme = sandbox.readText(workPath, 'readme.txt');
    expect(readme, contains('<<<<<<<'));
    expect(readme, contains('>>>>>>>'));
    expect(readme, contains('changed on the origin'));
    expect(readme, contains('changed at work'));
    await work.worktree.reset(mode: GitResetMode.mixed, target: tip.value);
    expect(await work.index.unmergedEntries(), isEmpty);
    expect(
      sandbox.readText(workPath, 'readme.txt'),
      contains('<<<<<<<'),
      reason: 'the reset keeps the work tree, markers included',
    );
  });

  test(
      'restores the previous state when git refuses the replay, and the '
      'work stays intact on its earlier base', () async {
    final GitOid tip = await advance(
      <String, String>{'readme.txt': 'changed on the origin\n'},
    );
    sandbox.write(workPath, 'readme.txt', 'changed at work\n');
    final Uint8List patch = await workPatch(base);

    await work.worktree.reset(mode: GitResetMode.hard, target: tip.value);
    final GitApplyResult rejection = await work.patches.apply(patch);

    expect(rejection, isA<GitApplyRefused>());
    expect((rejection as GitApplyRefused).message, isNotEmpty);
    // Nothing was applied: the clone sits clean on the tip it was moved to,
    // with the version the branch carries.
    expect(await work.revisions.resolveRevision('HEAD'), tip);
    expect(
      sandbox.readText(workPath, 'readme.txt'),
      'changed on the origin\n',
    );
    expect(await work.worktree.isClean(), isTrue);

    // The fallback of the replay: back to the earlier base, the work applied
    // there, the diff intact.
    final GitOid baseTree = (await work.objects.readCommit(base)).tree;
    await work.worktree.reset(mode: GitResetMode.hard, target: base.value);
    expect(await work.patches.apply(patch), isA<GitApplyApplied>());
    expect(
      sandbox.readText(workPath, 'readme.txt'),
      'changed at work\n',
    );
    expect(
      await work.patches.changedPathsFromTree(baseTree),
      <String>['readme.txt'],
    );
  });

  test(
      'carries the work onto a merge-shaped base rebuilt from the new tip '
      'and the side of the merge', () async {
    final GitOid tip = await advance(
      <String, String>{'content.txt': 'changed on the origin\n'},
    );
    sandbox.write(workPath, 'readme.txt', 'changed at work\n');
    sandbox.write(workPath, 'extra.txt', 'a new file\n');
    final Uint8List patch = await workPatch(base);

    // The replay rebuilds the combine: a merge commit of the tip and the
    // other side, minted locally through a temporary index, off any ref.
    final GitOid tipTree = (await work.objects.readCommit(tip)).tree;
    final GitOid combine = await work.withTemporaryIndex<GitOid>(
      (GitIndexedRepository indexed) => indexed.objects.commitTree(
        tipTree,
        <GitOid>[tip, base],
        'rebuilt combine',
        author: sandboxIdentity,
        committer: sandboxIdentity,
      ),
      fromTree: tipTree,
    );
    final GitCommit combineCommit = await work.objects.readCommit(combine);
    expect(combineCommit.parents, <GitOid>[tip, base]);

    await work.worktree.reset(mode: GitResetMode.hard, target: combine.value);
    expect(
      await work.patches.apply(patch, threeWay: true),
      isA<GitApplyApplied>(),
    );
    expect(
      sandbox.readText(workPath, 'readme.txt'),
      'changed at work\n',
    );
    expect(
      sandbox.readText(workPath, 'extra.txt'),
      'a new file\n',
    );
    // The combine stays local: the remote branch never saw it.
    expect(await origin.revisions.resolveRevision('main'), tip);
  });

  test(
      'replays on the plain tip when the side of the merge is already '
      'reached there', () async {
    final GitOid side = await advance(
      <String, String>{'content.txt': 'the side in flight\n'},
    );
    // A hand-made settlement of the two sides lands on the branch as well,
    // making [side] an ancestor of the tip the replay aims at.
    final GitOid tip = await advance(
      <String, String>{'readme.txt': 'settled on the branch\n'},
    );
    expect(await work.history.isAncestor(side, tip), isTrue);

    // Nothing to combine: the base of the replay is the tip itself. The work
    // touches a file the branch never carried, so it applies cleanly.
    sandbox.write(workPath, 'epsilon.txt', 'e0 changed at work\n');
    final Uint8List patch = await workPatch(base);
    await work.worktree.reset(mode: GitResetMode.hard, target: tip.value);
    expect(
      await work.patches.apply(patch, threeWay: true),
      isA<GitApplyApplied>(),
    );
    expect(
      sandbox.readText(workPath, 'epsilon.txt'),
      'e0 changed at work\n',
    );
    expect(await work.revisions.resolveRevision('HEAD'), tip);
  });

  test('keeps the work when the base branch carries no commit at all',
      () async {
    // A clone of an origin without any commit: the base branch is unborn,
    // there is no tree to capture a patch from and no tip to merge against.
    final GitFileBareRepository emptyOrigin =
        await sandbox.initBare('empty-origin.git');
    final GitWorkingRepository fresh =
        await sandbox.clone(emptyOrigin.path, 'unborn');
    final String freshPath = sandbox.path('unborn');
    sandbox.write(freshPath, 'thing.txt', 'made while the base was unborn\n');
    sandbox.write(freshPath, 'shared.txt', 'written at work\n');
    expect(await fresh.revisions.resolveRevision('HEAD'), isNull);

    // The branch comes to life on the origin while the work stays
    // uncommitted.
    final GitWorkingRepository born =
        await sandbox.clone(emptyOrigin.path, 'born');
    await sandbox.commit(
      born,
      <String, String>{
        'readme.txt': 'first commit\n',
        'shared.txt': 'written on the origin\n',
      },
      'the branch is born',
    );
    await sandbox.engine.push(
      born,
      remote: 'origin',
      refspecs: const <String>['main:refs/heads/main'],
    );
    await sandbox.engine.fetch(fresh, remote: 'origin');
    final GitOid tip = (await fresh.revisions.resolveRevision('origin/main'))!;

    // The replay: the work of the unborn clone is captured whole — tree and
    // untracked files through a temporary index — and combined with the tip
    // in memory, where both sides created `shared.txt`.
    final GitOid workTree = await fresh.withTemporaryIndex<GitOid>(
      (GitIndexedRepository indexed) async {
        await (indexed as GitWorkingRepository).worktree.addAll();
        return indexed.index.writeTree();
      },
    );
    final GitOid workCommit = await fresh.withTemporaryIndex<GitOid>(
      (GitIndexedRepository indexed) => indexed.objects.commitTree(
        workTree,
        const <GitOid>[],
        'the uncommitted work of an unborn base',
        author: sandboxIdentity,
        committer: sandboxIdentity,
      ),
      fromTree: workTree,
    );
    expect((await fresh.objects.readCommit(workCommit)).parents, isEmpty);
    final GitMergeTreeResult merged = await fresh.merge.mergeTree(
      workCommit,
      tip,
      allowUnrelatedHistories: true,
    );
    expect(merged.isConflicted, isTrue);
    expect(merged.conflictingFiles, <String>['shared.txt']);
    final GitOid replayed = await fresh.withTemporaryIndex<GitOid>(
      (GitIndexedRepository indexed) => indexed.objects.commitTree(
        merged.tree,
        <GitOid>[tip, workCommit],
        'the work replayed onto the born branch',
        author: sandboxIdentity,
        committer: sandboxIdentity,
      ),
      fromTree: merged.tree,
    );

    // The branch of the clone is born carrying the replay, and the work tree
    // keeps everything: the file only the work created, the file only the
    // tip created, and both sides of the file both created.
    await fresh.refs.updateRef('refs/heads/main', replayed);
    await fresh.worktree.reset(mode: GitResetMode.hard, target: 'main');
    expect(await fresh.revisions.resolveRevision('HEAD'), replayed);
    expect(await fresh.refs.resolveRef('refs/heads/main'), replayed);
    expect(
      sandbox.readText(freshPath, 'thing.txt'),
      'made while the base was unborn\n',
    );
    expect(
      sandbox.readText(freshPath, 'readme.txt'),
      'first commit\n',
    );
    final String shared = sandbox.readText(freshPath, 'shared.txt');
    expect(shared, contains('<<<<<<<'));
    expect(shared, contains('written at work'));
    expect(shared, contains('======='));
    expect(shared, contains('written on the origin'));
    expect(shared, contains('>>>>>>>'));
    expect(await fresh.index.unmergedEntries(), isEmpty);
  });
}
