@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import 'worktree_test_support.dart';

void main() {
  group('reset', () {
    test('a hard reset discards staged and unstaged modifications', () async {
      final TestRepository repo = await createTestRepository();
      final String initial =
          await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      final ProcessGitWorkingRepository repository = await openAt(repo);
      repo.writeFile('tracked.txt', 'two\n');
      await repo.runGit(<String>['add', '--', 'tracked.txt']);

      await repository.worktree.reset(mode: GitResetMode.hard);

      expect(readRepoFile(repo, 'tracked.txt'), 'one\n');
      expect(await repository.worktree.isClean(), isTrue);
      expect(await headOid(repo), initial);
    });

    test('refuses the soft mode, which moved to GitRefs.resetSoft', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      expect(
        () => repository.worktree.reset(mode: GitResetMode.soft),
        throwsArgumentError,
      );
    });

    test('a mixed reset unstages but keeps the work tree', () async {
      final TestRepository repo = await createTestRepository();
      final String first =
          await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      final ProcessGitWorkingRepository repository = await openAt(repo);
      repo.writeFile('tracked.txt', 'two\n');
      await repo.runGit(<String>['add', '--', 'tracked.txt']);

      await repository.worktree.reset(target: first);

      final GitStatusEntry entry =
          entryFor(await repository.worktree.status(), 'tracked.txt');
      expect(entry.indexState, GitFileState.unchanged);
      expect(entry.workTreeState, GitFileState.modified);
      expect(entry.isIndexed, isFalse);
      expect(entry.isModified, isTrue);
      expect(readRepoFile(repo, 'tracked.txt'), 'two\n');
    });

    test('a hard reset keeps an untracked file outside the target tree',
        () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      final ProcessGitWorkingRepository repository = await openAt(repo);
      repo.writeFile('untracked.txt', 'keep\n');

      await repository.worktree.reset(mode: GitResetMode.hard);

      expect(readRepoFile(repo, 'untracked.txt'), 'keep\n');
    });

    test('a hard reset keeps an ignored file outside the target tree',
        () async {
      final TestRepository repo = await createTestRepository();
      repo.writeFile('.gitignore', '*.log\n');
      await repo.runGit(<String>['add', '--', '.gitignore']);
      await repo.runGit(<String>['commit', '-m', 'add ignore rules']);
      final ProcessGitWorkingRepository repository = await openAt(repo);
      repo.writeFile('ignored.log', 'keep\n');

      await repository.worktree.reset(mode: GitResetMode.hard);

      expect(readRepoFile(repo, 'ignored.log'), 'keep\n');
    });

    test('a hard reset overwrites an untracked file colliding with a file',
        () async {
      final TestRepository repo = await createTestRepository();
      final String base = await commitFile(repo, 'base.txt', 'base\n', 'base');
      final String target =
          await commitFile(repo, 'obstacle', 'tracked\n', 'add obstacle');
      await repo.runGit(<String>['reset', '--hard', base]);
      repo.writeFile('obstacle', 'UNTRACKED USER DATA\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.reset(
        mode: GitResetMode.hard,
        target: target,
      );

      expect(readRepoFile(repo, 'obstacle'), 'tracked\n');
    });

    test('a hard reset overwrites an ignored file colliding with a file',
        () async {
      final TestRepository repo = await createTestRepository();
      repo.writeFile('.gitignore', '*.log\n');
      await repo.runGit(<String>['add', '--', '.gitignore']);
      await repo.runGit(<String>['commit', '-m', 'add ignore rules']);
      final String base = await headOid(repo);
      repo.writeFile('ignored.log', 'tracked target content\n');
      await repo.runGit(<String>['add', '-f', '--', 'ignored.log']);
      await repo.runGit(<String>['commit', '-m', 'track ignored log']);
      final String target = await headOid(repo);
      await repo.runGit(<String>['reset', '--hard', base]);
      repo.writeFile('ignored.log', 'IGNORED LOCAL WORK\n');
      repo.writeFile('kept.log', 'IGNORED SURVIVOR\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      expect(await repository.worktree.isIgnored('ignored.log'), isTrue);

      await repository.worktree.reset(
        mode: GitResetMode.hard,
        target: target,
      );

      expect(readRepoFile(repo, 'ignored.log'), 'tracked target content\n');
      expect(readRepoFile(repo, 'kept.log'), 'IGNORED SURVIVOR\n');
    });

    test('a hard reset replaces an untracked directory with a tracked file',
        () async {
      final TestRepository repo = await createTestRepository();
      final String base = await commitFile(repo, 'base.txt', 'base\n', 'base');
      final String target =
          await commitFile(repo, 'obstacle', 'tracked\n', 'add obstacle');
      await repo.runGit(<String>['reset', '--hard', base]);
      repo.writeFile('obstacle/local.txt', 'UNTRACKED USER DATA\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.reset(
        mode: GitResetMode.hard,
        target: target,
      );

      expect(repoFileExists(repo, 'obstacle/local.txt'), isFalse);
      expect(readRepoFile(repo, 'obstacle'), 'tracked\n');
    });

    test(
        'a hard reset overwrites an untracked file colliding with a '
        'directory', () async {
      final TestRepository repo = await createTestRepository();
      final String base = await commitFile(repo, 'base.txt', 'base\n', 'base');
      final String target =
          await commitFile(repo, 'dir/file.txt', 'nested\n', 'add dir');
      await repo.runGit(<String>['reset', '--hard', base]);
      repo.writeFile('dir', 'UNTRACKED USER DATA\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.reset(
        mode: GitResetMode.hard,
        target: target,
      );

      expect(repoFileExists(repo, 'dir/file.txt'), isTrue);
      expect(readRepoFile(repo, 'dir/file.txt'), 'nested\n');
    });

    test('refuses an unknown reset target', () async {
      final TestRepository repo = await createTestRepository();
      final String initial =
          await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await expectLater(
        repository.worktree.reset(target: 'missing'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'missing',
          ),
        ),
      );
      expect(await headOid(repo), initial);
    });
  });

  group('clean', () {
    test('removes untracked files but keeps ignored ones', () async {
      final TestRepository repo = await createTestRepository();
      repo.writeFile('.gitignore', '*.log\n');
      await repo.runGit(<String>['add', '--', '.gitignore']);
      await repo.runGit(<String>['commit', '-m', 'add ignore rules']);
      final ProcessGitWorkingRepository repository = await openAt(repo);
      repo.writeFile('untracked.txt', 'u\n');
      repo.writeFile('ignored.log', 'i\n');
      repo.writeFile('nested/deep.txt', 'd\n');

      await repository.worktree.clean();

      expect(repoFileExists(repo, 'untracked.txt'), isFalse);
      expect(repoFileExists(repo, 'ignored.log'), isTrue);
      expect(repoFileExists(repo, 'nested/deep.txt'), isTrue);
    });

    test('removes untracked directories only when asked', () async {
      final TestRepository repo = await createTestRepository();
      repo.writeFile('.gitignore', '*.log\n');
      await repo.runGit(<String>['add', '--', '.gitignore']);
      await repo.runGit(<String>['commit', '-m', 'add ignore rules']);
      final ProcessGitWorkingRepository repository = await openAt(repo);
      repo.writeFile('nested/deep.txt', 'd\n');
      repo.writeFile('ignored/nested.log', 'i\n');

      await repository.worktree.clean(directories: true);

      expect(repoFileExists(repo, 'nested/deep.txt'), isFalse);
      expect(repoFileExists(repo, 'ignored/nested.log'), isTrue);
    });
  });
}
