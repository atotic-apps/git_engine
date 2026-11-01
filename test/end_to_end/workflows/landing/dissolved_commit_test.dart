@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'landing_support.dart';

void main() {
  group('a landing commit with imposed parents', () {
    test('is fabricated from the in-memory merge of two diverged tips',
        () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final _Fixture fixture = await _conflictingFixture(sandbox);

      // The in-memory merge of the two diverged tips conflicts on the file
      // both sides edited.
      final GitMergeTreeResult predicted = await fixture.work.merge.mergeTree(
        fixture.namedTip,
        fixture.mainTip,
      );
      expect(predicted.isConflicted, isTrue);
      expect(predicted.conflictingFiles, <String>['lib.txt']);

      // The merge base is committed with the two tips as imposed parents and
      // becomes the head the resolution work starts from.
      final GitOid base = await fixture.work.objects.commitTree(
        predicted.tree,
        <GitOid>[fixture.namedTip, fixture.mainTip],
        'merge base of the two sides',
      );
      await fixture.work.worktree.reset(
        mode: GitResetMode.hard,
        target: base.value,
      );

      expect(
        await parentsOf(fixture.work, 'HEAD'),
        <GitOid>[fixture.namedTip, fixture.mainTip],
      );
      final String marked = readFile(fixture.work.path, 'lib.txt');
      expect(marked, contains('<<<<<<<'));
      expect(marked, contains('incoming side'));
      expect(marked, contains('main side'));
    });

    test(
        'lands on the named branch with its own tree and its imposed '
        'parents', () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final (_Fixture, GitOid, GitOid) prepared =
          await _resolvedFixture(sandbox);
      final _Fixture fixture = prepared.$1;
      final GitOid base = prepared.$2;
      final GitOid workCommit = prepared.$3;

      // The landing commit: the resolved tree, the two imposed parents.
      final GitOid tree =
          (await fixture.work.objects.readCommit(workCommit)).tree;
      final GitOid landing = await _landingCommit(
        fixture,
        tree,
        DateTime.utc(2026, 1, 1),
      );

      // The named branch still names the first imposed parent: the push is a
      // plain fast-forward, and it carries the landing commit itself.
      await sandbox.engine.push(
        fixture.work,
        remote: 'origin',
        refspecs: <String>['${landing.value}:refs/heads/incoming'],
      );

      expect(await resolve(fixture.origin, 'refs/heads/incoming'), landing);
      expect(
        await parentsOf(fixture.origin, 'refs/heads/incoming'),
        <GitOid>[fixture.namedTip, fixture.mainTip],
      );
      expect(
        await contentAt(fixture.origin, 'incoming', 'lib.txt'),
        'resolved\n',
      );
      // The fabricated base never becomes reachable from the named branch:
      // it is no ancestor of the landing commit, and it never even reached
      // the remote.
      expect(await fixture.work.history.isAncestor(base, landing), isFalse);
      expect(await fixture.origin.objects.objectExists(base), isFalse);
      // Redoing the landing commit from the same tree, parents, message,
      // identity and dates reproduces the very same object.
      final GitOid redone = await _landingCommit(
        fixture,
        tree,
        DateTime.utc(2026, 1, 1),
      );
      expect(redone, landing);
      expect(await branchNames(fixture.origin), <String>['incoming', 'main']);
    });

    test(
        'is folded onto an advanced named branch with the branch tip as '
        'first parent', () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final (_Fixture, GitOid, GitOid) prepared =
          await _resolvedFixture(sandbox);
      final _Fixture fixture = prepared.$1;
      final GitOid workCommit = prepared.$3;
      final GitOid tree =
          (await fixture.work.objects.readCommit(workCommit)).tree;
      final GitOid landing = await _landingCommit(
        fixture,
        tree,
        DateTime.utc(2026, 1, 1),
      );

      // Another landing advances the named branch while the resolution is
      // being finished.
      final GitOid rival = await fixture.writer.commitOnBranch(
        'incoming',
        <String, String>{'aside.txt': 'aside\n'},
        'another landing on the named branch',
      );

      // The work branch moves onto the fetched tip, then the landing commit
      // is folded with a merge commit: first parent the branch tip, second
      // the landing commit.
      await sandbox.engine.fetch(fixture.work, remote: 'origin');
      await fixture.work.worktree.reset(
        mode: GitResetMode.hard,
        target: 'refs/remotes/origin/incoming',
      );
      await fixture.work.merge.merge(
        landing.value,
        mode: GitMergeMode.noFastForward,
        message: 'fold the resolution',
      );
      await sandbox.engine.push(
        fixture.work,
        remote: 'origin',
        refspecs: <String>['HEAD:refs/heads/incoming'],
      );

      expect(
        await parentsOf(fixture.origin, 'refs/heads/incoming'),
        <GitOid>[rival, landing],
      );
      // The landing commit keeps its imposed parents.
      expect(
        await parentsOf(fixture.origin, landing.value),
        <GitOid>[fixture.namedTip, fixture.mainTip],
      );
      expect(
        await contentAt(fixture.origin, 'incoming', 'lib.txt'),
        'resolved\n',
      );
      expect(
        await contentAt(fixture.origin, 'incoming', 'aside.txt'),
        'aside\n',
      );
    });

    test('lands even when the two sides leave nothing to resolve', () async {
      final LandingSandbox sandbox = await LandingSandbox.create();
      final GitFileBareRepository origin = await sandbox.initBare('origin.git');
      final RemoteWriter writer =
          await RemoteWriter.create(sandbox, origin.path, 'writer');
      await writer.commitOnBranch(
        'main',
        <String, String>{'base.md': 'base\n'},
        'seed the origin',
      );
      final GitWorkingRepository work =
          await sandbox.clone(origin.path, 'work');
      // The two sides touch disjoint files: the in-memory merge is clean.
      final GitOid namedTip = await writer.commitOnBranch(
        'incoming',
        <String, String>{'named-side.md': 'named\n'},
        'disjoint edit on the named branch',
      );
      final GitOid mainTip = await writer.commitOnBranch(
        'main',
        <String, String>{'main-side.md': 'main\n'},
        'disjoint edit on the integration branch',
      );
      await sandbox.engine.fetch(work, remote: 'origin');

      final GitMergeTreeResult predicted = await work.merge.mergeTree(
        namedTip,
        mainTip,
      );
      expect(predicted.isConflicted, isFalse);
      final GitOid base = await work.objects.commitTree(
        predicted.tree,
        <GitOid>[namedTip, mainTip],
        'clean merge base',
      );
      await work.worktree.reset(mode: GitResetMode.hard, target: base.value);
      expect(await work.worktree.status(), isEmpty);

      // The work commit on top of the clean base is empty.
      final GitOid workCommit = await work.worktree.commit(
        'nothing to resolve',
        allowEmpty: true,
      );
      expect(await parentsOf(work, workCommit.value), <GitOid>[base]);

      // The landing commit folds both sides with the imposed parents.
      final GitOid landing = await work.objects.commitTree(
        (await work.objects.readCommit(workCommit)).tree,
        <GitOid>[namedTip, mainTip],
        'nothing to resolve',
      );
      await sandbox.engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['${landing.value}:refs/heads/incoming'],
      );

      expect(await resolve(origin, 'refs/heads/incoming'), landing);
      expect(
        await parentsOf(origin, 'refs/heads/incoming'),
        <GitOid>[namedTip, mainTip],
      );
      expect(
        await contentAt(origin, 'incoming', 'named-side.md'),
        'named\n',
      );
      expect(
        await contentAt(origin, 'incoming', 'main-side.md'),
        'main\n',
      );
    });
  });
}

/// A bare origin whose named branch and integration branch edited the same
/// file in opposite directions.
final class _Fixture {
  const _Fixture({
    required this.origin,
    required this.writer,
    required this.work,
    required this.namedTip,
    required this.mainTip,
  });

  final GitFileBareRepository origin;
  final RemoteWriter writer;
  final GitWorkingRepository work;

  /// Tip of the named branch the resolution lands on.
  final GitOid namedTip;

  /// Tip of the integration branch folded into the resolution.
  final GitOid mainTip;
}

/// Builds [_Fixture] with both sides edited: the in-memory merge of the two
/// tips conflicts on `lib.txt`.
Future<_Fixture> _conflictingFixture(LandingSandbox sandbox) async {
  final GitFileBareRepository origin = await sandbox.initBare('origin.git');
  final RemoteWriter writer =
      await RemoteWriter.create(sandbox, origin.path, 'writer');
  await writer.commitOnBranch(
    'main',
    <String, String>{'lib.txt': 'base line\n'},
    'seed the origin',
  );
  final GitWorkingRepository work = await sandbox.clone(origin.path, 'work');
  final GitOid namedTip = await writer.commitOnBranch(
    'incoming',
    <String, String>{'lib.txt': 'incoming side\n'},
    'edit the file on the named branch',
  );
  final GitOid mainTip = await writer.commitOnBranch(
    'main',
    <String, String>{'lib.txt': 'main side\n'},
    'edit the file on the integration branch',
  );
  await sandbox.engine.fetch(work, remote: 'origin');
  return _Fixture(
    origin: origin,
    writer: writer,
    work: work,
    namedTip: namedTip,
    mainTip: mainTip,
  );
}

/// Adds the resolution work to [_Fixture]: the fabricated merge base with
/// the two tips as imposed parents, then the commit carrying the resolved
/// file on top of it. Returns the fixture, the base and that work commit.
Future<(_Fixture, GitOid, GitOid)> _resolvedFixture(
  LandingSandbox sandbox,
) async {
  final _Fixture fixture = await _conflictingFixture(sandbox);
  final GitMergeTreeResult predicted = await fixture.work.merge.mergeTree(
    fixture.namedTip,
    fixture.mainTip,
  );
  final GitOid base = await fixture.work.objects.commitTree(
    predicted.tree,
    <GitOid>[fixture.namedTip, fixture.mainTip],
    'merge base of the two sides',
  );
  await fixture.work.worktree.reset(
    mode: GitResetMode.hard,
    target: base.value,
  );
  writeFile(fixture.work.path, 'lib.txt', 'resolved\n');
  final GitOid workCommit =
      await commitAll(fixture.work, 'resolve the conflict');
  return (fixture, base, workCommit);
}

/// The landing commit of a resolution: the given [tree] with the two imposed
/// parents, stamped with [when] so a redo reproduces the same object.
Future<GitOid> _landingCommit(
  _Fixture fixture,
  GitOid tree,
  DateTime when,
) {
  return fixture.work.objects.commitTree(
    tree,
    <GitOid>[fixture.namedTip, fixture.mainTip],
    'resolve the conflict',
    author: GitIdentity(name: 'Resolver', email: 'resolver@example.com'),
    committer: GitIdentity(name: 'Resolver', email: 'resolver@example.com'),
    authorDate: when,
    committerDate: when,
  );
}
