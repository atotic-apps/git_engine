@Tags(['git'])
library;

import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/process_test_git.dart';
import '../support/test_repository.dart';
import 'objects_test_support.dart';

void main() {
  late TestRepository repo;
  late ProcessGitRepository repository;

  setUp(() async {
    repo = await createTestRepository();
    repository = await openRepository(repo);
  });

  test('fabricates a commit from a temporary index without side effects',
      () async {
    await commitFile(repo, 'tracked.txt', 'baseline\n', 'baseline');
    final String indexBefore = TestRepository.join(
      TestRepository.join(repo.directory.path, '.git'),
      'index',
    );
    final List<int>? indexBytes = snapshot(indexBefore);
    final List<int>? workTreeBytes =
        snapshot(TestRepository.join(repo.directory.path, 'tracked.txt'));
    final String headBefore = await headOid(repo);

    final GitOid note = await repository.objects.writeObject(
      GitObjectType.blob,
      utf8.encode('fabricated from a temporary index\n'),
    );
    final GitOid readme = await writeBlob(repo, 'readme\n');

    final GitOid commit = await repository.withTemporaryIndex<GitOid>(
      (GitIndexedRepository view) async {
        await stageIndexEntry(
          view,
          mode: '100644',
          oid: note,
          path: 'generated/note.txt',
        );
        await stageIndexEntry(
          view,
          mode: '100644',
          oid: readme,
          path: 'generated/readme.txt',
        );

        final GitOid tree = await view.index.writeTree();
        final GitTree read = await view.objects.readTree(tree);
        expect(read.oid, tree);
        expect(
          read.entries.map((GitTreeEntry entry) => entry.path).toList(),
          <String>['generated'],
        );
        expect(read.entries.single.type.name, 'tree');
        expect(read.entries.single.mode, '040000');

        final GitTree generated = await view.objects.readTree(
          GitOid.parse(await oidOf(repo, '${tree.value}:generated')),
        );
        expect(
          generated.entries.map((GitTreeEntry entry) => entry.path).toList(),
          <String>['note.txt', 'readme.txt'],
        );
        expect(generated.entries.first.type.name, 'blob');
        expect(generated.entries.first.mode, '100644');
        expect(generated.entries.first.oid, note);

        return view.objects.commitTree(
          tree,
          const <GitOid>[],
          'fabricated commit\n',
        );
      },
    );

    expect(
      (await repo.runGit(<String>['log', '-1', '--format=%P', commit.value]))
          .stdout
          .trim(),
      isEmpty,
    );
    final GitOid commitTree =
        (await repository.objects.readCommit(commit)).tree;
    expect(
      (await repo.runGit(<String>['rev-parse', '${commit.value}^{tree}']))
          .stdout
          .trim(),
      commitTree.value,
    );
    expect(
      (await repo.runGit(
        <String>['ls-tree', '-r', '--name-only', commit.value],
      ))
          .stdout
          .split('\n')
          .where((String line) => line.isNotEmpty)
          .toList(),
      <String>['generated/note.txt', 'generated/readme.txt'],
    );

    expect(snapshot(indexBefore), indexBytes);
    expect(
      snapshot(TestRepository.join(repo.directory.path, 'tracked.txt')),
      workTreeBytes,
    );
    expect(await headOid(repo), headBefore);
    expect(
        (await repo.runGit(<String>['status', '--porcelain'])).stdout, isEmpty);
  });

  test('keeps non-ASCII paths through writeTree, readTree and commitTree',
      () async {
    const String accentedPath = 'café/naïve.txt';
    const String otherPath = 'plain.txt';

    final GitOid accented = await writeBlob(repo, 'héllo\n');
    final GitOid plain = await writeBlob(repo, 'plain\n');

    final GitOid commit = await repository.withTemporaryIndex<GitOid>(
      (GitIndexedRepository view) async {
        await stageIndexEntry(
          view,
          mode: '100644',
          oid: accented,
          path: accentedPath,
        );
        await stageIndexEntry(
          view,
          mode: '100644',
          oid: plain,
          path: otherPath,
        );

        final GitOid tree = await view.index.writeTree();
        final GitTree read = await view.objects.readTree(tree);
        expect(
          read.entries.map((GitTreeEntry entry) => entry.path).toSet(),
          <String>{'café', otherPath},
        );

        final GitTree accentedTree = await view.objects.readTree(
          GitOid.parse(await oidOf(repo, '${tree.value}:café')),
        );
        expect(
          accentedTree.entries.map((GitTreeEntry entry) => entry.path).toList(),
          <String>['naïve.txt'],
        );
        expect(accentedTree.entries.single.oid, accented);

        return view.objects.commitTree(
          tree,
          const <GitOid>[],
          'accented paths\n',
          author: GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com'),
        );
      },
    );
    expect(
      (await repo.runGit(
        <String>['ls-tree', '-r', '--name-only', commit.value],
      ))
          .stdout
          .split('\n')
          .where((String line) => line.isNotEmpty)
          .toSet(),
      <String>{accentedPath, otherPath},
    );
  });
}
