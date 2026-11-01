@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import 'refs_test_support.dart';

void main() {
  group('isAncestor', () {
    test('true for a parent and for a commit itself', () async {
      final TestRepository repo = await createTestRepository();
      final String parent = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String child = await commitFile(repo, 'b.txt', 'b\n', 'add b');
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.history
            .isAncestor(GitOid.parse(parent), GitOid.parse(child)),
        isTrue,
      );
      expect(
        await repository.history
            .isAncestor(GitOid.parse(child), GitOid.parse(child)),
        isTrue,
      );
    });

    test('false the other way around', () async {
      final TestRepository repo = await createTestRepository();
      final String parent = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String child = await commitFile(repo, 'b.txt', 'b\n', 'add b');
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.history
            .isAncestor(GitOid.parse(child), GitOid.parse(parent)),
        isFalse,
      );
    });

    test('false across unrelated root commits', () async {
      final TestRepository repo = await createTestRepository();
      final String first = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String root = await addOrphanRootCommit(repo);
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.history
            .isAncestor(GitOid.parse(first), GitOid.parse(root)),
        isFalse,
      );
      expect(
        await repository.history
            .isAncestor(GitOid.parse(root), GitOid.parse(first)),
        isFalse,
      );
    });

    test('throws when an object is absent from the repository', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        () => repository.history.isAncestor(
          GitOid.parse('a' * 40),
          GitOid.parse(commit),
        ),
        throwsA(isA<GitCommandException>()),
      );
    });
  });

  group('mergeBase', () {
    test('finds the fork point of two branches', () async {
      final TestRepository repo = await createTestRepository();
      final String base = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      await repo.runGit(<String>['checkout', '-b', 'topic']);
      final String topicTip =
          await commitFile(repo, 'topic.txt', 't\n', 'topic work');
      await repo.runGit(<String>['checkout', 'main']);
      final String mainTip = await commitFile(repo, 'b.txt', 'b\n', 'add b');
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.history
            .mergeBase(GitOid.parse(mainTip), GitOid.parse(topicTip)),
        GitOid.parse(base),
      );
      expect(
        await repository.history
            .mergeBase(GitOid.parse(mainTip), GitOid.parse(topicTip)),
        GitOid.parse(base),
      );
    });

    test('a commit is its own merge base', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.history
            .mergeBase(GitOid.parse(commit), GitOid.parse(commit)),
        GitOid.parse(commit),
      );
    });

    test('returns null across unrelated root commits', () async {
      final TestRepository repo = await createTestRepository();
      final String first = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String root = await addOrphanRootCommit(repo);
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.history
            .mergeBase(GitOid.parse(first), GitOid.parse(root)),
        isNull,
      );
    });

    test('throws when an object is absent from the repository', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        () => repository.history.mergeBase(
          GitOid.parse('a' * 40),
          GitOid.parse(commit),
        ),
        throwsA(isA<GitCommandException>()),
      );
    });
  });

  group('merge commit', () {
    test('both parents are ancestors of the merge', () async {
      final MergeHistory mergeHistory = await createMergeHistory();
      final GitHistory history = mergeHistory.repository.history;

      expect(
        await history.isAncestor(
          GitOid.parse(mergeHistory.mainTip),
          GitOid.parse(mergeHistory.merge),
        ),
        isTrue,
      );
      expect(
        await history.isAncestor(
          GitOid.parse(mergeHistory.sideTip),
          GitOid.parse(mergeHistory.merge),
        ),
        isTrue,
      );
      expect(
        await history.isAncestor(
          GitOid.parse(mergeHistory.merge),
          GitOid.parse(mergeHistory.mainTip),
        ),
        isFalse,
      );
      expect(
        await history.mergeBase(
          GitOid.parse(mergeHistory.mainTip),
          GitOid.parse(mergeHistory.sideTip),
        ),
        GitOid.parse(mergeHistory.base),
      );
      expect(
        (await mergeHistory.repository.objects.readCommit(
          GitOid.parse(mergeHistory.merge),
        ))
            .message,
        'merge side',
      );
    });
  });

  group('lastCommitTouching', () {
    late TestRepository repo;
    late ProcessGitRepository repository;
    late String first;
    late String second;
    late String third;

    setUp(() async {
      repo = await createTestRepository();
      first = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      second = await commitFile(repo, 'b.txt', 'b\n', 'add b');
      third = await commitFile(repo, 'a.txt', 'a2\n', 'touch a');
      repository = await openAt(repo);
    });

    test('finds the newest commit touching the path', () async {
      expect(
        await repository.history.lastCommitTouching('a.txt'),
        GitOid.parse(third),
      );
      expect(
        await repository.history.lastCommitTouching('b.txt'),
        GitOid.parse(second),
      );
    });

    test('returns null when no commit touched the path', () async {
      expect(await repository.history.lastCommitTouching('never.txt'), isNull);
    });

    test('walks from the requested revision', () async {
      expect(
        await repository.history.lastCommitTouching('a.txt', rev: first),
        GitOid.parse(first),
      );
      expect(
        await repository.history.lastCommitTouching('b.txt', rev: first),
        isNull,
      );
    });
  });

  group('commitsTouching', () {
    late TestRepository repo;
    late ProcessGitRepository repository;
    late String first;
    late String second;
    late String third;
    late String tip;

    setUp(() async {
      repo = await createTestRepository();
      first = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      second = await commitFile(repo, 'b.txt', 'b\n', 'add b');
      third = await commitFile(repo, 'a.txt', 'a2\n', 'touch a');
      tip = await commitFile(repo, 'a.txt', 'a3\n', 'touch a again');
      repository = await openAt(repo);
    });

    test('lists only the commits of the range touching the path, newest first',
        () async {
      expect(
        await repository.history.commitsTouching('a.txt', from: first, to: tip),
        <GitOid>[GitOid.parse(tip), GitOid.parse(third)],
      );
      expect(
        await repository.history.commitsTouching('b.txt', from: first, to: tip),
        <GitOid>[GitOid.parse(second)],
      );
    });

    test('returns an empty list when the path is touched by nobody in range',
        () async {
      expect(
        await repository.history
            .commitsTouching('never.txt', from: first, to: tip),
        isEmpty,
      );
      expect(
        await repository.history.commitsTouching('a.txt', from: tip, to: tip),
        isEmpty,
      );
    });

    test('walks the whole history without a range', () async {
      expect(
        await repository.history.commitsTouching('a.txt'),
        <GitOid>[GitOid.parse(tip), GitOid.parse(third), GitOid.parse(first)],
      );
    });
  });
}

/// Repository plus the object names of a merge commit with two parents:
/// [mainTip] merged [sideTip], both forked from [base].
class MergeHistory {
  final ProcessGitRepository repository;
  final String base;
  final String mainTip;
  final String sideTip;
  final String merge;

  MergeHistory({
    required this.repository,
    required this.base,
    required this.mainTip,
    required this.sideTip,
    required this.merge,
  });
}

/// Builds a repository whose history contains a merge commit with two
/// parents.
Future<MergeHistory> createMergeHistory() async {
  final TestRepository repo = await createTestRepository();
  final String base = await commitFile(repo, 'a.txt', 'a\n', 'add a');
  await repo.runGit(<String>['checkout', '-b', 'topic']);
  await commitFile(repo, 'topic.txt', 't\n', 'topic work');
  final String sideTip = await headOid(repo);
  await repo.runGit(<String>['checkout', 'main']);
  final String mainTip = await commitFile(repo, 'b.txt', 'b\n', 'add b');
  await repo.runGit(<String>['merge', '--no-ff', '-m', 'merge side', 'topic']);
  final String merge = await headOid(repo);
  return MergeHistory(
    repository: await openAt(repo),
    base: base,
    mainTip: mainTip,
    sideTip: sideTip,
    merge: merge,
  );
}

/// Adds a root commit with no parents to the repository and returns it.
Future<String> addOrphanRootCommit(TestRepository repo) async {
  await repo.runGit(<String>['checkout', '--orphan', 'orphan']);
  await repo.runGit(<String>['commit', '--allow-empty', '-m', 'root']);
  final String root = await headOid(repo);
  await repo.runGit(<String>['checkout', 'main']);
  return root;
}
