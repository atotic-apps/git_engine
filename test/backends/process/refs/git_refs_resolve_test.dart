@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import 'refs_test_support.dart';

void main() {
  group('resolveRevision', () {
    test('resolves HEAD, a branch and an abbreviated object name', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      final GitOid? fromHead =
          await repository.revisions.resolveRevision('HEAD');
      expect(fromHead, GitOid.parse(commit));
      expect(
        await repository.revisions.resolveRevision('main'),
        GitOid.parse(commit),
      );
      expect(
        await repository.revisions.resolveRevision(commit.substring(0, 8)),
        GitOid.parse(commit),
      );
    });

    test('returns null for a name that resolves to nothing', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.revisions.resolveRevision('no-such-revision'),
        isNull,
      );
    });

    test('never resolves a work tree file', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      repo.writeFile('notes.txt', 'not a revision\n');
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.revisions.resolveRevision('notes.txt'),
        isNull,
      );
    });

    test('returns null in a repository without commits', () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitRepository repository = await openAt(repo);

      expect(await repository.revisions.resolveRevision('HEAD'), isNull);
      expect(
        await repository.revisions.resolveRevision('refs/heads/main'),
        isNull,
      );
    });
  });

  group('resolveRevision to a tree', () {
    test('peels a commit to its tree', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      final String expected = await oidOf(repo, '$commit^{tree}');
      expect(
        await repository.revisions.resolveRevision('HEAD^{tree}'),
        GitOid.parse(expected),
      );
      expect(
        await repository.revisions.resolveRevision('main^{tree}'),
        GitOid.parse(expected),
      );
    });

    test('a tree peels to itself', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      final GitOid tree =
          (await repository.revisions.resolveRevision('HEAD^{tree}'))!;
      expect(
        await repository.revisions.resolveRevision('${tree.value}^{tree}'),
        tree,
      );
    });

    test('returns null for a name that resolves to nothing', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.revisions.resolveRevision('no-such-revision^{tree}'),
        isNull,
      );
    });

    test('returns null in a repository without commits', () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.revisions.resolveRevision('HEAD^{tree}'),
        isNull,
      );
    });
  });

  group('exists', () {
    test('accepts full names, short names and HEAD', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      await repo.runGit(<String>['tag', 'v1']);
      final ProcessGitRepository repository = await openAt(repo);

      expect(await repository.refs.exists('refs/heads/main'), isTrue);
      expect(await repository.refs.exists('main'), isTrue);
      expect(await repository.refs.exists('HEAD'), isTrue);
      expect(await repository.refs.exists('refs/tags/v1'), isTrue);
      expect(await repository.refs.exists('v1'), isTrue);
    });

    test('returns false for an unknown ref', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      expect(await repository.refs.exists('refs/heads/missing'), isFalse);
      expect(await repository.refs.exists('refs/tags/missing'), isFalse);
    });

    test('returns false in a repository without commits', () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitRepository repository = await openAt(repo);

      expect(await repository.refs.exists('HEAD'), isFalse);
      expect(await repository.refs.exists('refs/heads/main'), isFalse);
    });
  });

  group('listRefs', () {
    test('lists every ref with its full name and object', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      await repo.runGit(<String>['tag', 'v1']);
      await repo.runGit(<String>['branch', 'topic']);
      final ProcessGitRepository repository = await openAt(repo);

      final List<GitRef> refs = await repository.refs.listRefs();

      expect(
        refs.map((GitRef ref) => ref.name).toList(),
        <String>['refs/heads/main', 'refs/heads/topic', 'refs/tags/v1'],
      );
      expect(
        refs.every((GitRef ref) => ref.oid == GitOid.parse(commit)),
        isTrue,
      );
    });

    test('filters with a prefix', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      await repo.runGit(<String>['tag', 'v1']);
      await repo.runGit(<String>['branch', 'topic']);
      final ProcessGitRepository repository = await openAt(repo);

      final List<GitRef> branches =
          await repository.refs.listRefs(prefix: 'refs/heads/');
      expect(
        branches.map((GitRef ref) => ref.name).toList(),
        <String>['refs/heads/main', 'refs/heads/topic'],
      );

      final List<GitRef> tags =
          await repository.refs.listRefs(prefix: 'refs/tags/');
      expect(
        tags.map((GitRef ref) => ref.name).toList(),
        <String>['refs/tags/v1'],
      );

      final List<GitRef> none =
          await repository.refs.listRefs(prefix: 'refs/notes/');
      expect(none, isEmpty);
    });

    test('returns an empty list in a repository without commits', () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitRepository repository = await openAt(repo);

      expect(await repository.refs.listRefs(), isEmpty);
    });
  });
}
