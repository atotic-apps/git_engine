@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import 'worktree_test_support.dart';

void main() {
  group('commit', () {
    test('records the given identity as author and committer', () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitWorkingRepository repository = await openAt(repo);
      repo.writeFile('a.txt', 'a\n');
      await repository.worktree.add(<String>['a.txt']);

      final GitOid oid = await repository.worktree.commit(
        'feat: add a',
        identity: GitIdentity(
          name: 'Fixed User',
          email: 'fixed@example.com',
        ),
      );

      expect(oid, GitOid.parse(await headOid(repo)));
      final String log = (await repo.runGit(<String>[
        'log',
        '-1',
        '--format=%an%n%ae%n%cn%n%ce%n%s',
      ]))
          .stdout
          .trim();
      expect(
        log.split('\n'),
        <String>[
          'Fixed User',
          'fixed@example.com',
          'Fixed User',
          'fixed@example.com',
          'feat: add a',
        ],
      );
    });

    test('fails when nothing is staged', () async {
      final TestRepository repo = await createTestRepository();
      final String before = await commitFile(repo, 'a.txt', 'a\n', 'initial');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await expectLater(
        repository.worktree.commit('empty'),
        throwsA(isA<GitCommandException>()),
      );

      expect(await headOid(repo), before);
    });

    test('creates an empty commit when allowEmpty is set', () async {
      final TestRepository repo = await createTestRepository();
      final String before = await commitFile(repo, 'a.txt', 'a\n', 'initial');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      final GitOid oid =
          await repository.worktree.commit('empty', allowEmpty: true);

      expect(oid, GitOid.parse(await headOid(repo)));
      expect(oid, isNot(GitOid.parse(before)));
      final String parents = (await repo.runGit(<String>[
        'log',
        '-1',
        '--format=%P',
      ]))
          .stdout
          .trim();
      expect(parents, before);
    });
  });
}
