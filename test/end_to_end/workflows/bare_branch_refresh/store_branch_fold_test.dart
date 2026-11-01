@Tags(['git'])
library;

import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'bare_branch_refresh_support.dart';

/// Folding an advanced integration branch into a landed branch of a bare
/// store, without any clone: the in-memory merge predicts the folded tree, a
/// two-parent commit records it with the landed tip first, and only the
/// landed branch moves. A conflict keeps every branch where it was.
void main() {
  late FoldArea area;

  setUp(() async {
    area = await FoldArea.create();
  });

  test('a clean fold advances the landed branch and leaves the rest alone',
      () async {
    final GitFileBareRepository store = await area.seedStore('store');
    await area.landOnBranch(
      store,
      'main',
      <String, String>{'shared.txt': 'base\n'},
      message: 'seed the integration branch',
    );
    final GitOid workTip = await area.landOnBranch(
      store,
      'work',
      <String, String>{'work.txt': 'work\n'},
      message: 'land the work',
    );
    final GitOid mainTip = await area.landOnBranch(
      store,
      'main',
      <String, String>{'main.txt': 'advanced\n'},
      message: 'advance the integration branch',
    );

    final GitMergeTreeResult merged = await store.merge.mergeTree(
      workTip,
      mainTip,
    );
    expect(merged.isConflicted, isFalse);
    final GitOid folded = await store.objects.commitTree(
      merged.tree,
      <GitOid>[workTip, mainTip],
      'fold the integration branch',
    );
    await store.refs.updateRef('refs/heads/work', folded);

    expect(
      (await store.objects.readCommit(folded)).parents,
      <GitOid>[workTip, mainTip],
      reason: 'the landed branch is the first parent, the integration '
          'branch the second',
    );
    expect(await store.refs.resolveRef('refs/heads/work'), folded);
    expect(await store.refs.resolveRef('refs/heads/main'), mainTip,
        reason: 'folding never moves the integration branch');
    // Both sides are readable from the folded tree through the objects of
    // the store.
    final GitTree tree = await store.objects.readTree(
      (await store.objects.readCommit(folded)).tree,
    );
    expect(
      tree.entries.map((GitTreeEntry entry) => entry.path).toSet(),
      <String>{'shared.txt', 'work.txt', 'main.txt'},
    );
  });

  test('an integration tip already contained in the branch needs no fold',
      () async {
    final GitFileBareRepository store = await area.seedStore('store');
    await area.landOnBranch(
      store,
      'main',
      <String, String>{'shared.txt': 'base\n'},
      message: 'seed the integration branch',
    );
    final GitOid mainTip = await area.landOnBranch(
      store,
      'main',
      <String, String>{'main.txt': 'advanced\n'},
      message: 'advance the integration branch',
    );
    // The landed branch is created on the tip the store carries: the advance
    // is part of its history.
    final GitOid workTip = await area.landOnBranch(
      store,
      'work',
      <String, String>{'work.txt': 'work\n'},
      message: 'land the work',
    );

    // The guard sees the containment and the branch keeps its tip: no fold
    // is needed, and none is made.
    expect(await store.history.isAncestor(mainTip, workTip), isTrue);
    expect(await store.refs.resolveRef('refs/heads/work'), workTip);
    expect(await store.refs.resolveRef('refs/heads/main'), mainTip);
  });

  test('a textual conflict keeps every branch where it was', () async {
    final GitFileBareRepository store = await area.seedStore('store');
    await area.landOnBranch(
      store,
      'main',
      <String, String>{'shared.txt': 'base\n'},
      message: 'seed the integration branch',
    );
    final GitOid workTip = await area.landOnBranch(
      store,
      'work',
      <String, String>{'shared.txt': 'landed version\n'},
      message: 'land an edit of the shared file',
    );
    final GitOid mainTip = await area.landOnBranch(
      store,
      'main',
      <String, String>{'shared.txt': 'integration version\n'},
      message: 'edit the same line on the integration branch',
    );

    final GitMergeTreeResult merged = await store.merge.mergeTree(
      workTip,
      mainTip,
    );
    expect(merged.isConflicted, isTrue);
    expect(merged.conflictingFiles, <String>['shared.txt']);
    // The conflicted tree carries the markers of both sides.
    final GitTree tree = await store.objects.readTree(merged.tree);
    final GitTreeEntry entry = tree.entries.singleWhere(
      (GitTreeEntry candidate) => candidate.path == 'shared.txt',
    );
    final String conflicted = utf8.decode(
      await store.objects.readBlob(entry.oid),
    );
    expect(conflicted, contains('<<<<<<<'));
    expect(conflicted, contains('landed version'));
    expect(conflicted, contains('integration version'));
    expect(conflicted, contains('>>>>>>>'));

    // Nothing is written: the conflict refuses the fold, both tips stay.
    expect(await store.refs.resolveRef('refs/heads/work'), workTip);
    expect(await store.refs.resolveRef('refs/heads/main'), mainTip);
  });
}
