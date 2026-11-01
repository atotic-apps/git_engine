@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/remote_test_support.dart' show cloneBareByRunner;
import '../support/test_repository.dart';
import 'worktree_test_support.dart';

void main() {
  group('checkout', () {
    test('switches to an existing branch', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'main\n', 'initial');
      await repo.runGit(<String>['checkout', '-b', 'topic']);
      await commitFile(repo, 'tracked.txt', 'topic\n', 'topic change');
      await repo.runGit(<String>['checkout', 'main']);
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.checkout('topic');

      expect(await currentBranch(repo), 'topic');
      expect(readRepoFile(repo, 'tracked.txt'), 'topic\n');
    });

    test('reads a modified tracked file name as a revision, not a path',
        () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'topic', 'committed\n', 'add topic');
      await commitFile(repo, 'tracked.txt', 'tracked\n', 'add tracked');
      repo.writeFile('topic', 'uncommitted\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);
      final String headBefore = await headOid(repo);
      final before = await repository.worktree.status();

      await expectLater(
        repository.worktree.checkout('topic'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'topic',
          ),
        ),
      );
      expect(readRepoFile(repo, 'topic'), 'uncommitted\n');
      expect(await headOid(repo), headBefore);
      expect(await repository.worktree.status(), before);
    });

    test('prefers an existing branch over a file of the same name', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'topic', 'main\n', 'add topic on main');
      await repo.runGit(<String>['checkout', '-b', 'topic']);
      await commitFile(repo, 'topic', 'branch\n', 'change topic on branch');
      await repo.runGit(<String>['checkout', 'main']);
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.checkout('topic');

      expect(await currentBranch(repo), 'topic');
      expect(readRepoFile(repo, 'topic'), 'branch\n');
    });

    test('creates a local branch from a branch only the remote holds',
        () async {
      final TestRepository repo = await createTestRepository();
      final String tip = await commitFile(repo, 'tracked.txt', 'one\n', 'one');
      final String origin = await cloneBareByRunner(
        repo,
        repo.directory.path,
        'checkout-origin.git',
      );
      await repo.runGit(
        <String>['update-ref', 'refs/heads/remote-topic', tip],
        workingDirectory: origin,
      );
      await repo.runGit(<String>['remote', 'add', 'origin', origin]);
      await repo.runGit(const <String>['fetch', 'origin']);
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.checkout('remote-topic');

      expect(await currentBranch(repo), 'remote-topic');
      expect(await oidOf(repo, 'remote-topic'), tip);
      expect(
        await oidOf(repo, 'refs/remotes/origin/remote-topic'),
        tip,
      );
      final String upstream = (await repo.runGit(
        const <String>[
          'rev-parse',
          '--abbrev-ref',
          'remote-topic@{upstream}',
        ],
      ))
          .stdout
          .trim();
      expect(upstream, 'origin/remote-topic');
    });

    test('refuses an unknown branch', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await expectLater(
        repository.worktree.checkout('missing'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'missing',
          ),
        ),
      );
      expect(await currentBranch(repo), 'main');
    });

    test('refuses to overwrite local changes', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'main\n', 'initial');
      await repo.runGit(<String>['checkout', '-b', 'topic']);
      await commitFile(repo, 'tracked.txt', 'topic\n', 'topic change');
      await repo.runGit(<String>['checkout', 'main']);
      repo.writeFile('tracked.txt', 'dirty\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await expectLater(
        repository.worktree.checkout('topic'),
        throwsA(
          isA<GitLocalChangesOverwrittenException>().having(
            (GitLocalChangesOverwrittenException error) => error.paths,
            'paths',
            contains('tracked.txt'),
          ),
        ),
      );
      expect(await currentBranch(repo), 'main');
      expect(readRepoFile(repo, 'tracked.txt'), 'dirty\n');
    });

    test('refuses to overwrite untracked files and names them', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'main\n', 'initial');
      await repo.runGit(<String>['checkout', '-b', 'topic']);
      await commitFile(repo, 'new.txt', 'committed\n', 'add new.txt');
      await repo.runGit(<String>['checkout', 'main']);
      repo.writeFile('new.txt', 'untracked\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await expectLater(
        repository.worktree.checkout('topic'),
        throwsA(
          isA<GitLocalChangesOverwrittenException>().having(
            (GitLocalChangesOverwrittenException error) => error.paths,
            'paths',
            <String>['new.txt'],
          ),
        ),
      );
      expect(await currentBranch(repo), 'main');
      expect(readRepoFile(repo, 'new.txt'), 'untracked\n');
    });
  });

  group('checkoutDetached', () {
    test('detaches HEAD at the given revision', () async {
      final TestRepository repo = await createTestRepository();
      final String first = await commitFile(repo, 'a.txt', 'a\n', 'first');
      await commitFile(repo, 'b.txt', 'b\n', 'second');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.checkoutDetached(first);

      expect(await headOid(repo), first);
      expect(await currentBranch(repo), 'HEAD');
      expect(readRepoFile(repo, 'a.txt'), 'a\n');
      expect(repoFileExists(repo, 'b.txt'), isFalse);
    });

    test('refuses an unknown revision', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'first');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await expectLater(
        repository.worktree.checkoutDetached('missing'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'missing',
          ),
        ),
      );
      expect(await currentBranch(repo), 'main');
    });
  });

  group('checkoutNewBranch', () {
    test('creates a branch at HEAD and checks it out', () async {
      final TestRepository repo = await createTestRepository();
      final String first = await commitFile(repo, 'a.txt', 'a\n', 'first');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.checkoutNewBranch('created');

      expect(await currentBranch(repo), 'created');
      expect(await headOid(repo), first);
      expect(await oidOf(repo, 'created'), first);
    });

    test('creates a branch at an explicit start point', () async {
      final TestRepository repo = await createTestRepository();
      final String first = await commitFile(repo, 'a.txt', 'a\n', 'first');
      await commitFile(repo, 'b.txt', 'b\n', 'second');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.checkoutNewBranch('created', startPoint: first);

      expect(await currentBranch(repo), 'created');
      expect(await headOid(repo), first);
      expect(repoFileExists(repo, 'b.txt'), isFalse);
    });

    test('refuses an existing branch without resetIfExists', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'first');
      await repo.runGit(<String>['branch', 'topic']);
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await expectLater(
        repository.worktree.checkoutNewBranch('topic'),
        throwsA(isA<GitCommandException>()),
      );
      expect(await currentBranch(repo), 'main');
    });

    test('refuses an unknown start point', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'first');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await expectLater(
        repository.worktree.checkoutNewBranch('created', startPoint: 'missing'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'missing',
          ),
        ),
      );
      expect(await currentBranch(repo), 'main');
    });

    test('resets an existing branch with resetIfExists', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'first');
      await repo.runGit(<String>['branch', 'topic']);
      final String second = await commitFile(repo, 'b.txt', 'b\n', 'second');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.checkoutNewBranch(
        'topic',
        startPoint: second,
        resetIfExists: true,
      );

      expect(await currentBranch(repo), 'topic');
      expect(await headOid(repo), second);
      expect(await oidOf(repo, 'topic'), second);
    });
  });
}
