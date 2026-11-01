@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import 'refs_test_support.dart';

void main() {
  group('updateRef', () {
    test('creates and overwrites a ref', () async {
      final TestRepository repo = await createTestRepository();
      final String first = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String second = await commitFile(repo, 'b.txt', 'b\n', 'add b');
      final ProcessGitRepository repository = await openAt(repo);

      await repository.refs.updateRef(
        'refs/heads/created',
        GitOid.parse(first),
      );
      expect(
        await repository.refs.resolveRef('refs/heads/created'),
        GitOid.parse(first),
      );

      await repository.refs.updateRef(
        'refs/heads/created',
        GitOid.parse(second),
      );
      expect(
        await repository.refs.resolveRef('refs/heads/created'),
        GitOid.parse(second),
      );
    });

    test('accepts a matching expected old value', () async {
      final TestRepository repo = await createTestRepository();
      final String first = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String second = await commitFile(repo, 'b.txt', 'b\n', 'add b');
      final ProcessGitRepository repository = await openAt(repo);

      await repository.refs.updateRef(
        'refs/heads/main',
        GitOid.parse(first),
        expectedOld: GitOid.parse(second),
      );

      expect(
        await repository.revisions.resolveRevision('main'),
        GitOid.parse(first),
      );
    });

    test('fails with a typed error when the expected old value is wrong',
        () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      GitRefMismatchException? failure;
      try {
        await repository.refs.updateRef(
          'refs/heads/main',
          GitOid.parse(commit),
          expectedOld: GitOid.parse('a' * 40),
        );
      } on GitRefMismatchException catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      final GitRefMismatchException error = failure!;
      final GitCommandException cause = error.cause as GitCommandException;
      expect(cause.exitCode, isNot(0));
      expect(cause.stderr, isNotEmpty);

      expect(
        await repository.revisions.resolveRevision('main'),
        GitOid.parse(commit),
        reason: 'the failed update must leave the ref alone',
      );
    });

    test('fails when the expected old value is set on a missing ref', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        () => repository.refs.updateRef(
          'refs/heads/missing',
          GitOid.parse(commit),
          expectedOld: GitOid.parse(commit),
        ),
        throwsA(
          allOf(
            isA<GitCommandException>(),
            isNot(isA<GitRefMismatchException>()),
          ),
        ),
      );
      expect(await repository.refs.exists('refs/heads/missing'), isFalse);
    });
  });

  group('deleteRef', () {
    test('deletes an existing ref', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);
      await repository.refs
          .updateRef('refs/heads/created', GitOid.parse(commit));

      await repository.refs.deleteRef('refs/heads/created');

      expect(await repository.refs.exists('refs/heads/created'), isFalse);
    });

    test('deleting a missing ref succeeds silently', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      await repository.refs.deleteRef('refs/heads/missing');

      expect(await repository.refs.exists('refs/heads/missing'), isFalse);
    });

    test('honours a matching expected old value', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);
      await repository.refs
          .updateRef('refs/heads/created', GitOid.parse(commit));

      await repository.refs.deleteRef(
        'refs/heads/created',
        expectedOld: GitOid.parse(commit),
      );

      expect(await repository.refs.exists('refs/heads/created'), isFalse);
    });

    test('fails with a typed error when the expected old value is wrong',
        () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);
      await repository.refs
          .updateRef('refs/heads/created', GitOid.parse(commit));

      expect(
        () => repository.refs.deleteRef(
          'refs/heads/created',
          expectedOld: GitOid.parse('b' * 40),
        ),
        throwsA(isA<GitRefMismatchException>()),
      );
      expect(await repository.refs.exists('refs/heads/created'), isTrue);
    });
  });
}
