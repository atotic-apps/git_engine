@Tags(['git'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import '../../../backends/process/support/process_backend_types.dart'
    show GitCommandException;
import 'package:test/test.dart';

import 'sandbox.dart';

/// In-memory merging of uncommitted work against a tip of the same repository
/// on a real git: the work commit is fabricated from the index and the work
/// tree through a temporary index, untracked files included, so the merge can
/// run tree against tree without moving the work tree, the real index or any
/// ref.
///
/// The real index, the work tree and the refs are compared before and after
/// each merge to prove the in-memory nature of the operation.
void main() {
  var mintedCount = 0;

  late ReplaySandbox sandbox;
  late GitWorkingRepository repository;
  late GitOid base;

  setUp(() async {
    sandbox = await ReplaySandbox.create();
    repository = await sandbox.initWorking('repo');
    base = await sandbox.commit(
      repository,
      <String, String>{'a.txt': 'a0\n', 'b.txt': 'b0\n', 'c.txt': 'c0\n'},
      'base',
    );
  });

  /// Builds a tip commit on [branch] from [files], minted in a separate clone
  /// so the work tree of [repository] never needs to leave [base]; the tip is
  /// published on the branch [branch] of the repository itself.
  Future<GitOid> tipFrom(
    String branch,
    Map<String, String> files,
  ) async {
    final GitWorkingRepository minted = await sandbox.clone(
      sandbox.path('repo'),
      'mint-${mintedCount++}',
    );
    await minted.worktree.checkoutNewBranch(branch, startPoint: base.value);
    final GitOid tip = await sandbox.commit(minted, files, 'tip');
    await sandbox.engine.push(
      minted,
      remote: 'origin',
      refspecs: <String>['$branch:refs/heads/$branch'],
    );
    return tip;
  }

  /// The fabricated commit holding the uncommitted work of [repository]:
  /// every work-tree change and untracked file, on top of the tree of the
  /// commit [at].
  Future<GitOid> workCommit(GitOid at) async {
    final GitOid atTree = (await repository.objects.readCommit(at)).tree;
    final GitOid tree = await sandbox.workTree(atTree, repository);
    return sandbox.commitWorkTree(
      repository,
      tree: tree,
      parents: <GitOid>[at],
      message: 'work in progress',
    );
  }

  /// The content of the top-level blob [name] of [tree], as stored.
  Future<String> blobIn(GitTree tree, String name) async {
    final Uint8List bytes = await repository.objects.readBlob(
      tree.entries.singleWhere((GitTreeEntry entry) => entry.path == name).oid,
    );
    return utf8.decode(bytes, allowMalformed: true);
  }

  test('integrates uncommitted work, new files included, without conflict',
      () async {
    final GitOid tip = await tipFrom(
      'integration',
      <String, String>{'c.txt': 'c1\n'},
    );
    sandbox.write(sandbox.path('repo'), 'a.txt', 'a0 changed\n');
    sandbox.write(sandbox.path('repo'), 'kept.txt', 'a new file\n');

    final GitMergeTreeResult result = await repository.merge.mergeTree(
      await workCommit(base),
      tip,
    );

    expect(result.isConflicted, isFalse);
    expect(result.conflictingFiles, isEmpty);

    // The merged tree carries both sides: the work on a.txt and its new file,
    // and the change the tip brought to c.txt.
    final GitTree merged = await repository.objects.readTree(result.tree);
    expect(await blobIn(merged, 'a.txt'), 'a0 changed\n');
    expect(await blobIn(merged, 'kept.txt'), 'a new file\n');
    expect(await blobIn(merged, 'c.txt'), 'c1\n');
    expect(await blobIn(merged, 'b.txt'), 'b0\n');
  });

  test('names every path where both sides moved the file', () async {
    final GitOid tip = await tipFrom(
      'integration',
      <String, String>{'a.txt': 'a on the tip\n', 'b.txt': 'b on the tip\n'},
    );
    sandbox.write(sandbox.path('repo'), 'a.txt', 'a at work\n');
    sandbox.write(sandbox.path('repo'), 'b.txt', 'b at work\n');

    final GitMergeTreeResult result = await repository.merge.mergeTree(
      await workCommit(base),
      tip,
    );

    expect(result.isConflicted, isTrue);
    expect(
      result.conflictingFiles.toList()..sort(),
      <String>['a.txt', 'b.txt'],
    );
    // The merged tree itself carries conflict markers.
    final GitTree merged = await repository.objects.readTree(result.tree);
    final String conflicted = await blobIn(merged, 'a.txt');
    expect(conflicted, contains('<<<<<<<'));
    expect(conflicted, contains('>>>>>>>'));
  });

  test('reports add/add when the tip created the same new path', () async {
    final GitOid tip = await tipFrom(
      'integration',
      <String, String>{'kept.txt': 'created on the tip\n'},
    );
    sandbox.write(sandbox.path('repo'), 'kept.txt', 'created at work\n');

    final GitMergeTreeResult result = await repository.merge.mergeTree(
      await workCommit(base),
      tip,
    );

    expect(result.isConflicted, isTrue);
    expect(result.conflictingFiles, contains('kept.txt'));
  });

  test('does not conflict when the tip already is the base', () async {
    sandbox.write(sandbox.path('repo'), 'a.txt', 'a at work\n');
    sandbox.write(sandbox.path('repo'), 'kept.txt', 'new\n');

    final GitMergeTreeResult result = await repository.merge.mergeTree(
      await workCommit(base),
      base,
    );

    expect(result.isConflicted, isFalse);
    expect(result.conflictingFiles, isEmpty);
  });

  test('leaves the work tree, the real index and the refs untouched', () async {
    final GitOid tip = await tipFrom(
      'integration',
      <String, String>{'c.txt': 'c1\n'},
    );
    sandbox.write(sandbox.path('repo'), 'a.txt', 'a at work\n');
    sandbox.write(sandbox.path('repo'), 'kept.txt', 'new\n');
    final String workPath = sandbox.path('repo');
    final String statusBefore = await sandbox.ok(
      workPath,
      const <String>['status', '--porcelain=v1'],
    );
    final String headBefore = await sandbox.head(workPath);
    final String refsBefore = await sandbox.ok(
      workPath,
      const <String>['for-each-ref', '--format=%(refname) %(objectname)'],
    );
    final Uint8List indexBefore = sandbox.readBytes(
      join(workPath, '.git'),
      'index',
    );

    final GitMergeTreeResult result = await repository.merge.mergeTree(
      await workCommit(base),
      tip,
    );

    expect(result.isConflicted, isFalse);
    expect(
      await sandbox.ok(workPath, const <String>['status', '--porcelain=v1']),
      statusBefore,
    );
    expect(await sandbox.head(workPath), headBefore);
    expect(
      await sandbox.ok(
        workPath,
        const <String>['for-each-ref', '--format=%(refname) %(objectname)'],
      ),
      refsBefore,
    );
    expect(
      sandbox.readBytes(join(workPath, '.git'), 'index'),
      indexBefore,
    );
    // The new file stays untracked; only the fabrication and the merge, both
    // in memory, ever saw it.
    expect(
      await sandbox.ok(
        workPath,
        const <String>['ls-files', '--others', '--exclude-standard'],
      ),
      'kept.txt',
    );
  });

  test('raises when the tip object cannot be read', () async {
    // A commit of another repository is a well-formed object name git knows
    // nothing about here: an unreadable tip, never a false conflict.
    final GitWorkingRepository elsewhere = await sandbox.initWorking(
      'other',
    );
    final GitOid tip = await sandbox.commit(
      elsewhere,
      <String, String>{'far.txt': 'far\n'},
      'elsewhere',
    );
    sandbox.write(sandbox.path('repo'), 'a.txt', 'a at work\n');

    await expectLater(
      repository.merge.mergeTree(await workCommit(base), tip),
      throwsA(isA<GitCommandException>()),
    );
  });
}
