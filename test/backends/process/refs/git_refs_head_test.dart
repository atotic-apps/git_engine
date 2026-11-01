@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import 'refs_test_support.dart';

void main() {
  group('symbolicFullName', () {
    test('reads HEAD and its abbreviated form', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.revisions.symbolicFullName('HEAD'),
        'refs/heads/main',
      );
      expect(
        await repository.revisions.symbolicFullName('HEAD', abbreviated: true),
        'main',
      );
    });

    test('reports the revision itself when HEAD is detached', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      await repo.runGit(<String>['checkout', '--detach', commit]);

      expect(await repository.revisions.symbolicFullName('HEAD'), 'HEAD');
    });

    test('reads the upstream once it is set', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String clone = await createClone(repo, 'clone');
      final ProcessGitRepository repository =
          await openAt(repo, directory: clone);
      await repo.runGit(
        <String>['branch', '--unset-upstream'],
        workingDirectory: clone,
      );

      await expectLater(
        repository.revisions.symbolicFullName('@{upstream}'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            '@{upstream}',
          ),
        ),
      );

      await repository.branches.setUpstream('main', 'origin/main');

      expect(
        await repository.revisions.symbolicFullName('@{upstream}'),
        'refs/remotes/origin/main',
      );
      expect(
        await repository.revisions.symbolicFullName(
          '@{upstream}',
          abbreviated: true,
        ),
        'origin/main',
      );
    });
  });

  group('setHead', () {
    test('points HEAD at another branch', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      await repo.runGit(<String>['branch', 'topic']);
      final ProcessGitRepository repository = await openAt(repo);

      await repository.refs.setHead('refs/heads/topic');

      expect(
        await repository.revisions.symbolicFullName('HEAD'),
        'refs/heads/topic',
      );
      expect(await repository.branches.current(), 'topic');
    });

    test('takes a bare branch name', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      await repo.runGit(<String>['branch', 'topic']);
      final ProcessGitRepository repository = await openAt(repo);

      await repository.refs.setHead('topic');

      expect(
        await repository.revisions.symbolicFullName('HEAD'),
        'refs/heads/topic',
      );
    });

    test('works in a bare repository', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      await repo.runGit(<String>['branch', 'topic']);
      final String bare = await createBareClone(repo, 'bare.git');
      final ProcessGitRepository repository =
          await openAt(repo, directory: bare);

      await repository.refs.setHead('topic');

      expect(
        await repository.revisions.symbolicFullName('HEAD'),
        'refs/heads/topic',
      );
      expect(await repository.branches.current(), 'topic');
    });
  });
}
