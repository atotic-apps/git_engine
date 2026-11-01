@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/src/backends/process/refs/process_git_refs.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import 'refs_test_support.dart';

void main() {
  group('bare repository', () {
    late TestRepository repo;
    late ProcessGitRepository repository;
    late String first;
    late String second;

    setUp(() async {
      repo = await createTestRepository();
      first = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      second = await commitFile(repo, 'b.txt', 'b\n', 'add b');
      final String bare = await createBareClone(repo, 'bare.git');
      repository = await openAt(repo, directory: bare);
    });

    test('resolves revisions and trees', () async {
      expect(
        await repository.revisions.resolveRevision('HEAD'),
        GitOid.parse(second),
      );
      expect(
        await repository.revisions.resolveRevision('main'),
        GitOid.parse(second),
      );
      expect(
        await repository.revisions.resolveRevision('missing'),
        isNull,
      );

      final String tree = await oidOf(repo, '$second^{tree}');
      expect(
        await repository.revisions.resolveRevision('HEAD^{tree}'),
        GitOid.parse(tree),
      );
    });

    test('reads the branch and moves HEAD', () async {
      expect(await repository.branches.current(), 'main');

      await repository.refs.setHead('refs/heads/main');

      expect(
        await repository.revisions.symbolicFullName('HEAD'),
        'refs/heads/main',
      );
    });

    test('lists, updates and deletes refs', () async {
      final List<GitRef> refs = await repository.refs.listRefs();
      expect(
        refs.map((GitRef ref) => ref.name).toList(),
        <String>['refs/heads/main'],
      );

      await repository.refs
          .updateRef('refs/heads/created', GitOid.parse(first));
      expect(await repository.refs.resolveRef('refs/heads/created'),
          GitOid.parse(first));

      await repository.refs.deleteRef('refs/heads/created');
      expect(await repository.refs.exists('refs/heads/created'), isFalse);
    });

    test('reads history', () async {
      expect(
        await repository.history
            .isAncestor(GitOid.parse(first), GitOid.parse(second)),
        isTrue,
      );
      expect(
        await repository.history
            .mergeBase(GitOid.parse(first), GitOid.parse(second)),
        GitOid.parse(first),
      );
      final GitCommit secondCommit =
          await repository.objects.readCommit(GitOid.parse(second));
      expect(secondCommit.parents, <GitOid>[GitOid.parse(first)]);
      expect(secondCommit.message, 'add b');
      expect(await repository.history.lastCommitTouching('a.txt'),
          GitOid.parse(first));
      expect(
        await repository.history
            .commitsTouching('a.txt', from: first, to: second),
        isEmpty,
      );
      expect(
        await repository.history.commitsTouching('a.txt'),
        <GitOid>[GitOid.parse(first)],
      );
    });
  });

  group('clone', () {
    test('exposes the same domains as the origin it was cloned from', () async {
      final TestRepository repo = await createTestRepository();
      final String first = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String second = await commitFile(repo, 'a.txt', 'a2\n', 'touch a');
      final String clone = await createClone(repo, 'clone');
      final ProcessGitRepository repository =
          await openAt(repo, directory: clone);

      expect(await repository.branches.current(), 'main');
      expect(
        await repository.revisions.resolveRevision('HEAD'),
        GitOid.parse(second),
      );
      expect(await repository.history.lastCommitTouching('a.txt'),
          GitOid.parse(second));
      expect(
        await repository.history
            .commitsTouching('a.txt', from: first, to: second),
        <GitOid>[GitOid.parse(second)],
      );

      await repository.branches.setUpstream('main', 'origin/main');
      expect(
        await repository.revisions.symbolicFullName('@{upstream}'),
        'refs/remotes/origin/main',
      );

      await repo.runGit(<String>['branch', 'topic'], workingDirectory: clone);
      await repository.branches.delete('topic', force: true);
      expect(await repository.refs.exists('refs/heads/topic'), isFalse);
    });
  });

  group('repository without commits', () {
    test('resolves nothing but still reads HEAD and the ref list', () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        await repository.revisions.resolveRevision('HEAD'),
        isNull,
      );
      expect(
        await repository.revisions.resolveRevision('HEAD^{tree}'),
        isNull,
      );
      expect(await repository.refs.exists('HEAD'), isFalse);
      expect(await repository.branches.current(), 'main');
      expect(await repository.refs.listRefs(), isEmpty);
    });

    test('history commands report the unborn branch as a typed failure',
        () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitRepository repository = await openAt(repo);

      expect(
        () => repository.history.lastCommitTouching('a.txt'),
        throwsA(isA<GitCommandException>()),
      );
      expect(
        () => repository.history.commitsTouching('a.txt'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'HEAD',
          ),
        ),
      );
    });
  });

  group('repository context', () {
    test('a derived view hands its context to its domains', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final ProcessGitRepository repository = await openAt(repo);

      final ProcessGitRepository layered = repository
          .withEnvironment(const <String, String>{'ENGINE_LAYER': '1'});

      await layered.withTemporaryIndex<void>(
        (GitIndexedRepository view) async {
          final ProcessGitRepository process = view as ProcessGitRepository;
          final ProcessGitRefs refs = process.refs;

          expect(refs.repository.context.environment['ENGINE_LAYER'], '1');
          expect(
            refs.repository.context.environment['GIT_INDEX_FILE'],
            isNotNull,
          );
          expect(await refs.resolveRef('HEAD'), GitOid.parse(commit));
          expect(await process.branches.current(), 'main');
        },
      );
    });
  });
}
