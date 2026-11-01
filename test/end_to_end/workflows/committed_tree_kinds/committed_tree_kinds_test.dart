@Tags(['git'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../../../backends/process/support/process_test_git.dart';
import 'committed_tree_kinds_support.dart';

/// The kinds git records in a committed tree: a regular file, an executable,
/// a symbolic link, a subdirectory and a gitlink read back with git's own
/// modes and types through the objects of the repository.
void main() {
  late KindsArea area;

  setUp(() async {
    area = await KindsArea.create();
  });

  test('a committed tree carries the five kinds git tracks', () async {
    final GitWorkingRepository working = await area.seedWorking('work');
    File(join(working.path, 'notes.md')).writeAsStringSync('# notes\n');
    await working.worktree.addAll();
    await working.worktree.commit('a regular file');

    // The special entries are staged into the index: an executable blob, a
    // symbolic link and a gitlink pointing at an orphan commit of the same
    // repository.
    final GitOid script = await working.objects.writeObject(
      GitObjectType.blob,
      utf8.encode('#!/bin/sh\necho ok\n'),
    );
    final GitOid link = await working.objects.writeObject(
      GitObjectType.blob,
      utf8.encode('notes.md'),
    );
    final GitOid head = (await working.revisions.resolveRevision('HEAD'))!;
    final GitOid headTree = (await working.objects.readCommit(head)).tree;
    final GitOid orphan = await working.objects.commitTree(
      headTree,
      const <GitOid>[],
      'a commit to point a gitlink at',
    );
    await stageIndexEntry(
      working,
      mode: '100755',
      oid: script,
      path: 'bin/run.sh',
    );
    await stageIndexEntry(
      working,
      mode: '120000',
      oid: link,
      path: 'docs/link.md',
    );
    await stageIndexEntry(
      working,
      mode: '160000',
      oid: orphan,
      path: 'vendor/dep',
    );

    final GitOid tree = await working.index.writeTree();
    final GitOid commit = await working.objects.commitTree(
      tree,
      const <GitOid>[],
      'the five kinds',
    );

    final GitTree committed = await working.objects.readTree(tree);
    expect(
      committed.entries.map((GitTreeEntry entry) => entry.path).toSet(),
      <String>{'bin', 'docs', 'notes.md', 'vendor'},
    );

    final GitTree bin =
        await working.objects.readTree(entryOf(committed, 'bin').oid);
    final GitTreeEntry scriptEntry = entryOf(bin, 'run.sh');
    expect(scriptEntry.mode, '100755');
    expect(scriptEntry.type, GitObjectType.blob);
    expect(scriptEntry.oid, script);

    final GitTree docs =
        await working.objects.readTree(entryOf(committed, 'docs').oid);
    final GitTreeEntry linkEntry = entryOf(docs, 'link.md');
    expect(linkEntry.mode, '120000');
    expect(linkEntry.type, GitObjectType.blob);
    expect(linkEntry.oid, link);

    final GitTree vendor =
        await working.objects.readTree(entryOf(committed, 'vendor').oid);
    final GitTreeEntry depEntry = entryOf(vendor, 'dep');
    expect(depEntry.mode, '160000');
    expect(depEntry.type, GitObjectType.commit);
    expect(depEntry.oid, orphan);

    final GitTreeEntry regular = entryOf(committed, 'notes.md');
    expect(regular.mode, '100644');
    expect(regular.type, GitObjectType.blob);

    // The commit records the tree of the kinds, and a path it does not carry
    // has no entry at all.
    expect((await working.objects.readCommit(commit)).tree, tree);
    expect(
      committed.entries.where(
        (GitTreeEntry entry) => entry.path == 'absent.md',
      ),
      isEmpty,
    );
  });
}

/// The entry of [tree] named [path], failing the test when it is absent.
GitTreeEntry entryOf(GitTree tree, String path) {
  return tree.entries.singleWhere(
    (GitTreeEntry entry) => entry.path == path,
    orElse: () => throw StateError('no entry "$path" in the tree'),
  );
}
