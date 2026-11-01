@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'preparation_support.dart';

void main() {
  late PreparationWorkdir workdir;
  late GitWorkingRepository copy;

  setUp(() async {
    workdir = await PreparationWorkdir.create();
    copy = await workdir.createWorking('copy');
    writeFile(copy.path, 'tracked.txt', 'one\n');
    writeFile(copy.path, '.gitignore', 'cache.txt\n');
    await copy.worktree.addAll();
    await copy.worktree.commit(
      'seed the working copy',
      identity: GitIdentity(name: seedUserName, email: seedUserEmail),
    );
  });

  group('state readings over a prepared working copy', () {
    test('keeps ignored writes invisible', () async {
      writeFile(copy.path, 'cache.txt', 'cached\n');

      expect(await copy.worktree.status(), isEmpty);
      expect(await copy.worktree.isClean(), isTrue);
      final GitOid head = (await copy.revisions.resolveRevision('HEAD'))!;
      final GitCommit record = await copy.objects.readCommit(head);
      expect(await copy.patches.changedPathsFromTree(record.tree), isEmpty);
      expect(File(join(copy.path, 'cache.txt')).existsSync(), isTrue);
    });

    test('reads a new file once its intent to add is recorded', () async {
      final GitOid head = (await copy.revisions.resolveRevision('HEAD'))!;
      final GitCommit record = await copy.objects.readCommit(head);
      writeFile(copy.path, 'new.txt', 'fresh line\n');

      expect(
        await copy.patches.changedPathsFromTree(record.tree),
        isNot(contains('new.txt')),
        reason: 'an untracked file stays invisible before its intent to add',
      );

      await copy.worktree.intentToAdd(<String>['new.txt']);

      expect(
        await copy.patches.changedPathsFromTree(record.tree),
        contains('new.txt'),
      );
      final String diff = await copy.patches.textDiffFromTree(record.tree);
      expect(diff, startsWith('diff --git '));
      expect(diff, contains('new.txt'));
      expect(diff, contains('+fresh line'));
    });
  });
}
