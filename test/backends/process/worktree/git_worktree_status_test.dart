@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import 'worktree_test_support.dart';

void main() {
  group('status', () {
    late TestRepository repo;
    late ProcessGitWorkingRepository repository;

    setUp(() async {
      repo = await createTestRepository();
      await commitFile(repo, 'tracked.txt', 'one\n', 'initial');
      repository = await openAt(repo);
    });

    test('is empty and clean for an untouched repository', () async {
      expect(await repository.worktree.status(), isEmpty);
      expect(await repository.worktree.isClean(), isTrue);
    });

    test('reports a staged addition as indexed', () async {
      repo.writeFile('added.txt', 'content\n');
      await repo.runGit(<String>['add', '--', 'added.txt']);

      final List<GitStatusEntry> entries = await repository.worktree.status();
      final GitStatusEntry entry = entryFor(entries, 'added.txt');

      expect(entries, hasLength(1));
      expect(entry.code, 'A ');
      expect(entry.indexState, GitFileState.added);
      expect(entry.workTreeState, GitFileState.unchanged);
      expect(entry.isIndexed, isTrue);
      expect(entry.isUntracked, isFalse);
      expect(await repository.worktree.isClean(), isFalse);
    });

    test('reports an unstaged modification', () async {
      repo.writeFile('tracked.txt', 'two\n');

      final List<GitStatusEntry> entries = await repository.worktree.status();
      final GitStatusEntry entry = entryFor(entries, 'tracked.txt');

      expect(entry.code, ' M');
      expect(entry.indexState, GitFileState.unchanged);
      expect(entry.workTreeState, GitFileState.modified);
      expect(entry.isModified, isTrue);
      expect(entry.isIndexed, isFalse);
    });

    test('reports a modification staged and modified again once', () async {
      repo.writeFile('tracked.txt', 'two\n');
      await repo.runGit(<String>['add', '--', 'tracked.txt']);
      repo.writeFile('tracked.txt', 'three\n');

      final List<GitStatusEntry> entries = await repository.worktree.status();
      final GitStatusEntry entry = entryFor(entries, 'tracked.txt');

      expect(entry.code, 'MM');
      expect(entry.isIndexed, isTrue);
      expect(entry.isModified, isTrue);
    });

    test('reports an untracked file', () async {
      repo.writeFile('untracked.txt', 'content\n');

      final List<GitStatusEntry> entries = await repository.worktree.status();
      final GitStatusEntry entry = entryFor(entries, 'untracked.txt');

      expect(entry.code, '??');
      expect(entry.indexState, GitFileState.untracked);
      expect(entry.workTreeState, GitFileState.untracked);
      expect(entry.isUntracked, isTrue);
      expect(entry.isIndexed, isFalse);
    });

    test('reports a deleted file', () async {
      repoFile(repo, 'tracked.txt').deleteSync();

      final List<GitStatusEntry> entries = await repository.worktree.status();
      final GitStatusEntry entry = entryFor(entries, 'tracked.txt');

      expect(entry.code, ' D');
      expect(entry.workTreeState, GitFileState.deleted);
      expect(entry.isDeleted, isTrue);
      expect(entry.isModified, isFalse);
    });

    test('reports a rename together with its original path', () async {
      repo.writeFile('old name.txt', 'content\n');
      await repo.runGit(<String>['add', '--', 'old name.txt']);
      await repo.runGit(<String>['commit', '-m', 'add old name']);
      await repo.runGit(<String>[
        'mv',
        '--',
        'old name.txt',
        'new name.txt',
      ]);

      final List<GitStatusEntry> entries = await repository.worktree.status();
      final GitStatusEntry entry = entryFor(entries, 'new name.txt');

      expect(entry.code, 'R ');
      expect(entry.originalPath, 'old name.txt');
      expect(entry.indexState, GitFileState.renamed);
      expect(entry.workTreeState, GitFileState.unchanged);
      expect(entry.isRenamed, isTrue);
      expect(entry.isIndexed, isTrue);
      expect(entries, hasLength(1));
    });

    test('keeps accented names and spaces intact', () async {
      const String path = 'fichier accentué.txt';
      repo.writeFile(path, 'contenu\n');

      List<GitStatusEntry> entries = await repository.worktree.status();
      GitStatusEntry entry = entryFor(entries, path);
      expect(entry.isUntracked, isTrue);
      expect(entry.path, path);

      await repository.worktree.add(<String>[path]);
      entries = await repository.worktree.status();
      entry = entryFor(entries, path);
      expect(entry.isIndexed, isTrue);
      expect(entry.path, path);
      expect(entry.isUntracked, isFalse);
    });

    test('reports a conflicted path', () async {
      await commitFile(repo, 'conflict.txt', 'base\n', 'base');
      await repo.runGit(<String>['checkout', '-b', 'side']);
      await commitFile(repo, 'conflict.txt', 'side\n', 'side change');
      await repo.runGit(<String>['checkout', 'main']);
      await commitFile(repo, 'conflict.txt', 'main\n', 'main change');
      try {
        await repo.runGit(<String>['merge', 'side']);
      } on GitCommandException {
        // The conflicting merge exits with a non-zero code, as expected.
      }

      final List<GitStatusEntry> entries = await repository.worktree.status();
      final GitStatusEntry entry = entryFor(entries, 'conflict.txt');

      expect(entry.code, 'UU');
      expect(entry.indexState, GitFileState.unmerged);
      expect(entry.workTreeState, GitFileState.unmerged);
      expect(entry.isConflicted, isTrue);
      expect(entry.isIndexed, isFalse);
    });
  });

  group('status in a subdirectory', () {
    test('reports paths relative to the repository root', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'nested/tracked.txt', 'one\n', 'initial');
      repo.writeFile('nested/changed.txt', 'new\n');
      final ProcessGitWorkingRepository repository = await openAt(
        repo,
        directory: TestRepository.join(repo.directory.path, 'nested'),
      );

      final List<GitStatusEntry> entries = await repository.worktree.status();

      expect(
        entries.map((GitStatusEntry entry) => entry.path).toList(),
        <String>['nested/changed.txt'],
      );
    });
  });
}
