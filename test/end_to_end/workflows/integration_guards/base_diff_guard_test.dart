@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'integration_guards_support.dart';

/// What a guard reads out of the diff a working copy carries: an untouched
/// copy diffs to nothing, and the diff between the branch tip and the copy
/// names a file exactly when the tip does not already hold the content of
/// the copy.
void main() {
  late GuardArea area;

  setUp(() async {
    area = await GuardArea.create();
  });

  test('the diff between a copy and its recorded base is empty', () async {
    final GitFileBareRepository store = await area.seedStore('store');
    final GitWorkingRepository clone = await area.cloneOf(store.path);
    File(join(clone.path, 'notes.txt')).writeAsStringSync('base\n');
    final GitOid base = await area.commitAll(clone, 'record the base');
    await area.engine.push(
      clone,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/main'],
    );

    // The untouched copy holds exactly what its base holds.
    final GitOid baseTree = (await store.objects.readCommit(base)).tree;
    final GitTree committed = await store.objects.readTree(baseTree);
    expect(committed.entries, hasLength(1));
    expect(
      await store.patches.changedPaths(baseTree, baseTree),
      isEmpty,
      reason: 'nothing differs between the base and itself',
    );
    expect(await store.patches.textDiff(baseTree, baseTree), isEmpty);
  });

  test('the diff of a copy is empty once the tip holds its content', () async {
    final GitFileBareRepository store = await area.seedStore('store');
    final GitWorkingRepository clone = await area.cloneOf(store.path);
    File(join(clone.path, 'notes.txt')).writeAsStringSync('base\n');
    await area.commitAll(clone, 'record the base');
    await area.engine.push(
      clone,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/main'],
    );

    // The copy carries uncommitted work; its content reaches the store
    // through a scratch landing, the way any exchange would. Another writer
    // lands the same content on the branch meanwhile.
    File(join(clone.path, 'notes.txt')).writeAsStringSync('the work\n');
    final GitOid workCommit = await area.commitAll(clone, 'the work');
    await area.engine.push(
      clone,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/work-copy'],
    );
    final GitOid workTree = (await store.objects.readCommit(workCommit)).tree;

    final String writerPath = area.path('writer');
    final GitWorkingRepository writer = await area.engine.clone(
      store.path,
      writerPath,
    );
    File(join(writer.path, 'notes.txt')).writeAsStringSync('the work\n');
    final GitOid writerCommit =
        await area.commitAll(writer, 'land the same content');
    await area.engine.push(
      writer,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/landed'],
    );
    await deleteRecursively(Directory(writerPath));

    // Comparing the branch tip with the content of the copy yields nothing:
    // the work is already there, nothing would be lost.
    final GitOid tipTree = (await store.objects.readCommit(writerCommit)).tree;
    expect(await store.patches.changedPaths(tipTree, workTree), isEmpty);
    expect(await store.patches.textDiff(tipTree, workTree), isEmpty);
  });

  test('the diff of a copy survives a tip holding other content', () async {
    final GitFileBareRepository store = await area.seedStore('store');
    final GitWorkingRepository clone = await area.cloneOf(store.path);
    File(join(clone.path, 'notes.txt')).writeAsStringSync('base\n');
    await area.commitAll(clone, 'record the base');
    await area.engine.push(
      clone,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/main'],
    );

    // The copy carries uncommitted work; its content reaches the store
    // through a scratch landing, the way any exchange would. Another writer
    // lands DIFFERENT content on the branch meanwhile.
    File(join(clone.path, 'notes.txt')).writeAsStringSync('the work\n');
    final GitOid workCommit = await area.commitAll(clone, 'the work');
    await area.engine.push(
      clone,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/work-copy'],
    );
    final GitOid workTree = (await store.objects.readCommit(workCommit)).tree;

    final String writerPath = area.path('writer');
    final GitWorkingRepository writer = await area.engine.clone(
      store.path,
      writerPath,
    );
    File(join(writer.path, 'notes.txt')).writeAsStringSync('other\n');
    final GitOid writerCommit =
        await area.commitAll(writer, 'land other content');
    await area.engine.push(
      writer,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/landed'],
    );
    await deleteRecursively(Directory(writerPath));

    // Comparing the branch tip with the content of the copy names the file:
    // the work is nowhere in the tip, so the guard refuses.
    final GitOid tipTree = (await store.objects.readCommit(writerCommit)).tree;
    expect(
      await store.patches.changedPaths(tipTree, workTree),
      <String>['notes.txt'],
    );
    final String diff = await store.patches.textDiff(tipTree, workTree);
    expect(diff, contains('-other\n'));
    expect(diff, contains('+the work\n'));
  });
}
