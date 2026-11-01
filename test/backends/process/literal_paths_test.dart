@Tags(['git'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../../support/index_tree_paths.dart';
import 'support/test_repository.dart';
import 'worktree/worktree_test_support.dart';

void main() {
  group('literal paths in add', () {
    test('stages only the literal [x].txt path, not a glob match', () async {
      final TestRepository repo = await createTestRepository();
      repo.writeFile('x.txt', 'glob match\n');
      repo.writeFile('[x].txt', 'literal\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.add(const <String>['[x].txt']);

      expect(await _staged(repository), <String>['[x].txt']);
    });

    test('stages a literal a*b.txt without expanding it', () async {
      final TestRepository repo = await createTestRepository();
      repo.writeFile('axb.txt', 'glob match\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      if (Platform.isWindows) {
        // Windows file names cannot contain `*`, so the literal pathspec
        // matches nothing; a glob would have staged axb.txt instead.
        await expectLater(
          repository.worktree.add(const <String>['a*b.txt']),
          throwsA(isA<GitCommandException>()),
        );
        expect(await _staged(repository), isEmpty);
      } else {
        repo.writeFile('a*b.txt', 'literal\n');
        await repository.worktree.add(const <String>['a*b.txt']);
        expect(await _staged(repository), <String>['a*b.txt']);
      }
    });

    test('stages a directory with its content', () async {
      final TestRepository repo = await createTestRepository();
      repo.writeFile('dir/one.txt', 'one\n');
      repo.writeFile('dir/nested/two.txt', 'two\n');
      repo.writeFile('outside.txt', 'outside\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.add(const <String>['dir']);

      expect(
        await _staged(repository),
        <String>['dir/nested/two.txt', 'dir/one.txt'],
      );
    });

    test('stages the whole repository through .', () async {
      final TestRepository repo = await createTestRepository();
      repo.writeFile('one.txt', 'one\n');
      repo.writeFile('dir/two.txt', 'two\n');
      final ProcessGitWorkingRepository repository = await openAt(repo);

      await repository.worktree.add(const <String>['.']);

      expect(
        await _staged(repository),
        <String>['dir/two.txt', 'one.txt'],
      );
    });
  });

  test('isIgnored treats its path literally', () async {
    final TestRepository repo = await createTestRepository();
    repo.writeFile('axb.txt', 'ignored\n');
    repo.writeFile('.gitignore', 'axb.txt\n');
    final ProcessGitWorkingRepository repository = await openAt(repo);

    expect(
      await repository.worktree.isIgnored('axb.txt', noIndex: true),
      isTrue,
    );
    expect(
      await repository.worktree.isIgnored('a*b.txt', noIndex: true),
      isFalse,
      reason: 'a*b.txt is a literal name, not a glob matching axb.txt',
    );
  });

  test('commitsTouching matches a literal path containing *', () async {
    final TestRepository repo = await createTestRepository();
    final ProcessGitWorkingRepository repository = await openAt(repo);
    final GitOid first = await _syntheticCommit(
      repo,
      repository,
      <String, String>{'axb.txt': 'one\n'},
      'add a glob match',
    );
    final GitOid second = await _syntheticCommit(
      repo,
      repository,
      <String, String>{'axb.txt': 'one\n', 'a*b.txt': 'two\n'},
      'add the literal path',
      parent: first,
    );

    expect(
      await repository.history.commitsTouching('a*b.txt'),
      <GitOid>[second],
    );
    expect(await repository.history.lastCommitTouching('a*b.txt'), second);
  });

  test('textDiff is restricted to a literal path containing ?', () async {
    final TestRepository repo = await createTestRepository();
    final ProcessGitWorkingRepository repository = await openAt(repo);
    final GitOid first = await _syntheticCommit(
      repo,
      repository,
      <String, String>{'a?b.txt': 'one\n', 'axb.txt': 'one\n'},
      'first',
    );
    final GitOid second = await _syntheticCommit(
      repo,
      repository,
      <String, String>{'a?b.txt': 'two\n', 'axb.txt': 'two\n'},
      'second',
      parent: first,
    );

    final String shown = await repository.patches.textDiff(
      first,
      second,
      paths: const <String>['a?b.txt'],
    );

    expect(shown, contains('a?b.txt'));
    expect(shown, isNot(contains('axb.txt')));
  });

  test('commands without paths keep working', () async {
    final TestRepository repo = await createTestRepository();
    repo.writeFile('one.txt', 'one\n');
    repo.writeFile('dir/two.txt', 'two\n');
    final ProcessGitWorkingRepository repository = await openAt(repo);

    await repository.worktree.addAll();
    expect(await repository.worktree.status(), isNotEmpty);
    final GitOid first = await repository.worktree.commit('initial');

    repo.writeFile('one.txt', 'changed\n');
    await repository.worktree.addAll();
    final GitOid second = await repository.worktree.commit('second');
    expect(
      await repository.patches.textDiff(first, second),
      contains('one.txt'),
    );

    repo.writeFile('junk.txt', 'junk\n');
    await repository.worktree.clean();
    expect(
      File(TestRepository.join(repo.directory.path, 'junk.txt')).existsSync(),
      isFalse,
    );

    await repository.worktree.checkoutNewBranch('topic');
    expect(await repository.branches.current(), 'topic');
    repo.writeFile('topic.txt', 'topic\n');
    await repository.worktree.addAll();
    await repository.worktree.commit('topic');
    await repository.worktree.checkout('main');
    expect(
      await repository.merge.merge('topic'),
      isA<GitMergeFastForward>(),
    );
  });
}

/// Paths staged in [repository]'s index, sorted.
Future<List<String>> _staged(
  ProcessGitWorkingRepository repository,
) =>
    indexPaths(repository);

/// Writes [files] into a synthetic commit on `refs/heads/main` and returns it.
///
/// The paths live only in the tree, so names that the host file system cannot
/// create — `a*b.txt`, `a?b.txt` — still exercise path handling.
Future<GitOid> _syntheticCommit(
  TestRepository repo,
  ProcessGitWorkingRepository repository,
  Map<String, String> files,
  String message, {
  GitOid? parent,
}) async {
  final StringBuffer entries = StringBuffer();
  for (final MapEntry<String, String> file in files.entries) {
    final GitOid blob = await repository.objects.writeObject(
      GitObjectType.blob,
      utf8.encode(file.value),
    );
    entries.write('100644 blob ${blob.value}\t${file.key}\n');
  }
  final GitRunResult treeResult = await repo.runGit(
    const <String>['mktree'],
    stdin: Uint8List.fromList(utf8.encode(entries.toString())),
  );
  final String tree = treeResult.stdout.trim();
  final GitRunResult commitResult = await repo.runGit(<String>[
    'commit-tree',
    tree,
    if (parent != null) ...<String>['-p', parent.value],
    '-m',
    message,
  ]);
  final GitOid commit = GitOid.parse(commitResult.stdout.trim());
  await repo.runGit(<String>['update-ref', 'refs/heads/main', commit.value]);
  return commit;
}
