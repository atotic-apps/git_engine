@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import 'worktree_test_support.dart';

void main() {
  group('add', () {
    test('stages only the given paths', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      repo.writeFile('a.txt', 'a\n');
      repo.writeFile('b.txt', 'b\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.add(<String>['a.txt']);

      final List<GitStatusEntry> entries = await repository.worktree.status();
      expect(entryFor(entries, 'a.txt').isIndexed, isTrue);
      expect(entryFor(entries, 'b.txt').isUntracked, isTrue);
    });

    test('does nothing without paths', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.add(const <String>[]);

      expect(await repository.worktree.isClean(), isTrue);
    });
  });

  group('addAll', () {
    test('stages additions, modifications and deletions', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      final ProcessGitWorkingRepository repository = await openAt(repo);
      repo.writeFile('tracked.txt', 'two\n');
      repo.writeFile('nested/new.txt', 'new\n');

      await repository.worktree.addAll();

      final List<GitStatusEntry> entries = await repository.worktree.status();
      expect(
        entries.every((GitStatusEntry entry) => entry.isIndexed),
        isTrue,
      );
      expect(
          entryFor(entries, 'tracked.txt').indexState, GitFileState.modified);
      expect(
          entryFor(entries, 'nested/new.txt').indexState, GitFileState.added);
    });

    test('stages deletions', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      final ProcessGitWorkingRepository repository = await openAt(repo);
      repoFile(repo, 'tracked.txt').deleteSync();

      await repository.worktree.addAll();

      final GitStatusEntry entry =
          entryFor(await repository.worktree.status(), 'tracked.txt');
      expect(entry.indexState, GitFileState.deleted);
      expect(entry.isIndexed, isTrue);
    });
  });

  group('intentToAdd', () {
    test('records intent without staging content', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      repo.writeFile('new file.txt', 'new\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.intentToAdd(<String>['.']);

      final GitStatusEntry entry =
          entryFor(await repository.worktree.status(), 'new file.txt');
      expect(entry.isUntracked, isFalse);
      expect(
          entry.workTreeState,
          anyOf(
            GitFileState.added,
            GitFileState.unchanged,
          ));
      expect(entry.isIndexed, isFalse);
    });

    test('leaves the repository index intact with an alternate index',
        () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      repo.writeFile('new file.txt', 'new\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);
      final String indexFile =
          TestRepository.join(repo.sandbox.path, 'alternate-index');
      final List<int> before = repoFile(repo, '.git/index').readAsBytesSync();
      final ProcessGitWorkingRepository alternate =
          repository.withIndexFile(indexFile);

      await alternate.worktree.intentToAdd(<String>['.']);

      expect(
        repoFile(repo, '.git/index').readAsBytesSync(),
        before,
        reason: 'the repository index must not be touched',
      );
      final GitStatusEntry recorded =
          entryFor(await alternate.worktree.status(), 'new file.txt');
      expect(recorded.isUntracked, isFalse);
      expect(recorded.isIndexed, isFalse);
    });

    test('does nothing without paths', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.intentToAdd(const <String>[]);

      expect(await repository.worktree.isClean(), isTrue);
    });
  });

  group('isIgnored', () {
    late TestRepository repo;
    late ProcessGitWorkingRepository repository;

    setUp(() async {
      repo = await createTestRepository();
      repo.writeFile('.gitignore', '*.log\n');
      await repo.runGit(<String>['add', '--', '.gitignore']);
      await repo.runGit(
        <String>['commit', '-m', 'add ignore rules'],
      );
      repo.writeFile('tracked.log', 'tracked\n');
      await repo.runGit(<String>['add', '--force', '--', 'tracked.log']);
      await repo.runGit(<String>['commit', '-m', 'track a matching path']);
      repo.writeFile('debug.log', 'ignored\n');
      repository = await openAt(repo);
    });

    test('recognizes an ignored untracked path with --no-index', () async {
      expect(
        await repository.worktree.isIgnored('debug.log', noIndex: true),
        isTrue,
      );
    });

    test('recognizes an ignored untracked path without --no-index', () async {
      expect(await repository.worktree.isIgnored('debug.log'), isTrue);
    });

    test('honours the index unless --no-index is given', () async {
      expect(await repository.worktree.isIgnored('tracked.log'), isFalse);
      expect(
        await repository.worktree.isIgnored('tracked.log', noIndex: true),
        isTrue,
      );
    });

    test('reports a path matched by no rule', () async {
      repo.writeFile('plain.txt', 'plain\n');
      expect(await repository.worktree.isIgnored('plain.txt'), isFalse);
    });
  });
}
