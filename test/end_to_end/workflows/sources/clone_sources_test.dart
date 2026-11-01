@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'sources_support.dart';

/// Where a clone sits after it was made: on the tip the origin carries, or
/// held on a base recorded before the branch moved on.
void main() {
  late SourcesSandbox sandbox;

  setUp(() async {
    sandbox = await createSourcesSandbox();
  });

  /// Object name `HEAD` currently resolves to in [repository].
  Future<GitOid> headOf(GitWorkingRepository repository) async =>
      (await repository.revisions.resolveRevision('HEAD'))!;

  test('a clone follows a master default branch', () async {
    final String originPath = sandbox.path('origin-master.git');
    await sandbox.engine.initBare(originPath, initialBranch: 'master');
    final GitOid tip = await sandbox.pushTip(
      originPath,
      branch: 'master',
      files: <String, String>{'lib.md': '# lib\n'},
      message: 'seed the origin',
    );

    final GitWorkingRepository clone =
        await sandbox.engine.clone(originPath, sandbox.path('clone'));

    expect(await clone.branches.current(), 'master');
    expect(await headOf(clone), tip);
    expect(
      File(join(sandbox.path('clone'), 'lib.md')).readAsStringSync(),
      '# lib\n',
    );
  });

  test('a clone is held on a recorded base while its branch moved on',
      () async {
    final String targetPath = sandbox.path('target.git');
    await sandbox.engine.initBare(targetPath, initialBranch: 'main');
    final GitOid targetBase = await sandbox.pushTip(
      targetPath,
      branch: 'main',
      files: <String, String>{'start.md': 'start\n'},
      message: 'seed target',
    );
    final String neighborPath = sandbox.path('neighbor.git');
    await sandbox.engine.initBare(neighborPath, initialBranch: 'main');
    final GitOid neighborBase = await sandbox.pushTip(
      neighborPath,
      branch: 'main',
      files: <String, String>{'start.md': 'start\n'},
      message: 'seed neighbor',
    );

    // Both branches advance after the bases were recorded, so a clone made
    // now would otherwise follow commits nobody based work on.
    final GitOid targetTip = await sandbox.pushTip(
      targetPath,
      branch: 'main',
      files: <String, String>{'late.md': 'late\n'},
      message: 'advance target',
    );
    final GitOid neighborTip = await sandbox.pushTip(
      neighborPath,
      branch: 'main',
      files: <String, String>{'late.md': 'late\n'},
      message: 'advance neighbor',
    );
    expect(targetTip, isNot(targetBase));
    expect(neighborTip, isNot(neighborBase));

    final GitWorkingRepository clone =
        await sandbox.engine.clone(targetPath, sandbox.path('clone'));
    expect(await headOf(clone), targetTip,
        reason: 'a plain clone follows the current tip');

    await clone.worktree.checkoutDetached(targetBase.value);

    expect(await headOf(clone), targetBase);
    expect(await clone.branches.current(), isNull,
        reason: 'the base is held detached, not on the moved branch');
    expect(File(join(sandbox.path('clone'), 'late.md')).existsSync(), isFalse,
        reason: 'the work tree matches the base, not the tip');

    final GitWorkingRepository neighbor =
        await sandbox.engine.clone(neighborPath, sandbox.path('neighbor'));
    await neighbor.worktree.checkoutDetached(neighborBase.value);
    expect(await headOf(neighbor), neighborBase);
    expect(await headOf(neighbor), isNot(neighborTip));
  });

  test('a recorded base the clone does not know fails cleanly', () async {
    final String originPath = sandbox.path('origin.git');
    await sandbox.engine.initBare(originPath, initialBranch: 'main');
    await sandbox.pushTip(
      originPath,
      branch: 'main',
      files: <String, String>{'readme.md': '# project\n'},
      message: 'seed the origin',
    );

    // A commit of an unrelated history, as a rewritten branch leaves its old
    // commits unknown to every clone made afterwards.
    final String foreignPath = sandbox.path('foreign');
    final GitWorkingRepository foreign =
        await sandbox.engine.init(foreignPath, initialBranch: 'main');
    File(join(foreignPath, 'orphan.md')).writeAsStringSync('orphan\n');
    await foreign.worktree.addAll();
    final GitOid orphan = await foreign.worktree.commit(
      'orphan commit',
      identity: seedIdentity,
    );

    final GitWorkingRepository clone =
        await sandbox.engine.clone(originPath, sandbox.path('clone'));
    final GitOid before = await headOf(clone);

    await expectLater(
      clone.worktree.checkoutDetached(orphan.value),
      throwsA(isA<GitException>()),
    );

    expect(await headOf(clone), before,
        reason: 'the failed placement leaves the clone where it was');
    expect(await clone.worktree.isClean(), isTrue);
  });

  test('files created outside the clone stay invisible to its status',
      () async {
    final String originPath = sandbox.path('origin.git');
    await sandbox.engine.initBare(originPath, initialBranch: 'main');
    await sandbox.pushTip(
      originPath,
      branch: 'main',
      files: <String, String>{'readme.md': '# project\n'},
      message: 'seed the origin',
    );

    // The clone lives in its own folder; materialized notes are written in a
    // sibling folder of that folder, outside every work tree.
    final String sessionPath = sandbox.path('session');
    final String clonePath = join(sessionPath, 'clone');
    await sandbox.engine.clone(originPath, clonePath);
    Directory(join(sessionPath, 'notes')).createSync(recursive: true);
    File(join(sessionPath, join('notes', 'note.txt')))
        .writeAsStringSync('scratch\n');

    final GitWorkingRepository clone =
        await sandbox.engine.openWorking(clonePath);

    expect(await clone.worktree.status(), isEmpty);
    expect(await clone.worktree.isClean(), isTrue);
  });
}
