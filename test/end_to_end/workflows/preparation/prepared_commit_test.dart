@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import '../../../backends/process/support/process_backend_types.dart'
    show GitCommandException;
import 'package:test/test.dart';

import 'preparation_support.dart';

void main() {
  late PreparationWorkdir workdir;

  setUp(() async {
    workdir = await PreparationWorkdir.create();
  });

  group('committing the prepared work', () {
    test('records the local configuration identity as author and committer',
        () async {
      final GitWorkingRepository copy = await workdir.createWorking('copy');
      await copy.config.set('user.name', 'Prepared Worker');
      await copy.config.set('user.email', 'worker@preparation.test');
      writeFile(copy.path, 'thing.txt', 'content\n');

      await copy.worktree.addAll();
      final GitOid commit = await copy.worktree.commit('record the work');

      final GitCommit record = await copy.objects.readCommit(commit);
      expect(record.author.name, 'Prepared Worker');
      expect(record.author.email, 'worker@preparation.test');
      expect(record.committer.name, 'Prepared Worker');
      expect(record.committer.email, 'worker@preparation.test');
    });

    test('keeps an untracked ignored file out of the commit and on disk',
        () async {
      final String originPath = await workdir.createOrigin(
        'origin',
        <String, String>{'generated.txt': 'generated content\n'},
      );
      final String copyDir = copyPath(workdir, 'copy');
      final GitWorkingRepository copy =
          await workdir.engine.clone(originPath, copyDir);
      expect(File(join(copyDir, 'generated.txt')).existsSync(), isTrue);

      writeFile(copyDir, '.gitignore', 'generated.txt\n');
      await copy.index.remove(<String>['generated.txt']);
      await copy.worktree.addAll();
      final GitOid commit = await copy.worktree.commit(
        'leave the generated file untracked',
        identity: GitIdentity(name: seedUserName, email: seedUserEmail),
      );

      expect(
        await committedTopLevelPaths(copy, commit),
        <String>{'.gitignore'},
        reason: 'the ignored file left the committed tree',
      );
      expect(await trackedPaths(copy, 'generated.txt'), isEmpty);
      expect(File(join(copyDir, 'generated.txt')).existsSync(), isTrue);
      expect(contentOf(join(copyDir, 'generated.txt')), 'generated content\n');
    });

    test('refuses to remove a path outside the repository from the index',
        () async {
      final GitWorkingRepository copy = await workdir.createWorking('copy');

      await expectLater(
        copy.index.remove(<String>[join('..', 'outside.txt')]),
        throwsA(isA<GitCommandException>()),
      );
    });
  });
}
