@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'integration_guards_support.dart';

/// The ancestry a guard reads out of a bare store: a landed commit sits in
/// the history of the branch it landed on, while a fabricated commit that no
/// reference carries belongs to no branch at all.
void main() {
  late GuardArea area;

  setUp(() async {
    area = await GuardArea.create();
  });

  test('a landed commit is an ancestor of the branch it landed on', () async {
    final GitFileBareRepository store = await area.seedStore('store');

    final GitWorkingRepository baseClone = await area.cloneOf(
      store.path,
    );
    File(join(baseClone.path, 'readme.md')).writeAsStringSync('# store\n');
    final GitOid base = await area.commitAll(baseClone, 'seed the store');
    await area.engine.push(
      baseClone,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/main'],
    );
    final GitOid baseTip = (await store.refs.resolveRef('refs/heads/main'))!;

    final GitWorkingRepository work = await area.cloneOf(store.path);
    final GitOid? recordedBase =
        await work.refs.resolveRef('refs/remotes/origin/main');
    expect(
      recordedBase,
      baseTip,
      reason: 'the clone of the store records the base it starts from',
    );
    await work.worktree.checkoutNewBranch('work-branch');
    File(join(work.path, 'notes.txt')).writeAsStringSync('the work\n');
    final GitOid workCommit = await area.commitAll(work, 'the work');
    await area.engine.push(
      work,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/work-branch'],
    );

    final GitOid? branchTip =
        await store.refs.resolveRef('refs/heads/work-branch');
    expect(branchTip, workCommit);
    expect(
      await store.history.isAncestor(workCommit, branchTip!),
      isTrue,
      reason: 'the landed commit is in the history of its branch',
    );
    expect(
      await store.history.isAncestor(base, branchTip),
      isTrue,
      reason: 'the recorded base too',
    );
    expect(await store.refs.exists('refs/heads/work-branch'), isTrue);
    expect(baseTip, isNot(workCommit));
  });

  test('a fabricated orphan commit belongs to the store but to no branch',
      () async {
    final GitFileBareRepository store = await area.seedStore('store');
    final GitWorkingRepository clone = await area.cloneOf(store.path);
    File(join(clone.path, 'readme.md')).writeAsStringSync('# store\n');
    final GitOid base = await area.commitAll(clone, 'seed the store');
    await area.engine.push(
      clone,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/main'],
    );

    // An orphan commit is written into the store without any reference:
    // valid content, no history.
    final GitOid orphan = await store.objects.commitTree(
      (await store.objects.readCommit(base)).tree,
      const <GitOid>[],
      'orphan commit outside any branch',
    );

    expect(await store.objects.objectExists(orphan), isTrue);
    expect(
      await store.history.isAncestor(orphan, base),
      isFalse,
      reason: 'an orphan commit is not in the history of the branch',
    );
    expect(
      await store.history.isAncestor(base, orphan),
      isFalse,
      reason: 'nothing points at the orphan, so no branch reaches it',
    );
    expect(
      (await store.refs.listRefs(prefix: 'refs/heads/'))
          .map((GitRef ref) => ref.oid),
      isNot(contains(orphan)),
    );
  });

  test('requires a complete hexadecimal object name before interpreting it',
      () async {
    final GitFileBareRepository store = await area.seedStore('store');
    final GitWorkingRepository clone = await area.cloneOf(store.path);
    File(join(clone.path, 'readme.md')).writeAsStringSync('# store\n');
    final GitOid base = await area.commitAll(clone, 'seed the store');
    await area.engine.push(
      clone,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/main'],
    );
    final GitOid? branchTip = await store.refs.resolveRef('refs/heads/main');

    // A guard takes values from outside and must refuse every spelling that
    // is not a complete hexadecimal object name of the expected length, so
    // an abbreviation, a branch name or an expression is never handed to the
    // store for interpretation.
    final String complete = base.value;
    final List<String> refused = <String>[
      complete.substring(0, 7),
      complete.substring(0, 39),
      'refs/heads/main',
      'main',
      'HEAD~1',
      '${complete.substring(0, 39)}g',
      '',
    ];
    for (final String candidate in refused) {
      expect(
        GitOid.tryParse(candidate),
        isNull,
        reason: '"$candidate" is not a complete hexadecimal object name',
      );
      expect(
        () => GitOid.parse(candidate),
        throwsFormatException,
        reason: '"$candidate" is refused before any resolution',
      );
    }

    final GitOid? parsed = GitOid.tryParse(complete);
    expect(parsed, base);
    expect(
      await store.revisions.resolveRevision(parsed!.value),
      branchTip,
      reason: 'only the complete object name reaches the store, and it '
          'resolves to the commit the branch carries',
    );
    expect(
      await store.history.isAncestor(parsed, branchTip!),
      isTrue,
      reason: 'the validated object name is in the history of the branch',
    );
  });
}
