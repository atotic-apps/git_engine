@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import '../refs/refs_test_support.dart';

void main() {
  group('current', () {
    test('reads the branch HEAD points at, before and after commits', () async {
      final TestRepository repo = await createTestRepository();
      final ProcessGitRepository repository = await openAt(repo);

      expect(await repository.branches.current(), 'main');

      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      expect(await repository.branches.current(), 'main');
    });

    test('reads the branch name when a tag shares it', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      await repo.runGit(<String>['tag', 'main']);
      final ProcessGitRepository repository = await openAt(repo);

      expect(await repository.branches.current(), 'main');

      final List<GitBranch> branches = await repository.branches.list();
      expect(
        branches.map((GitBranch branch) => branch.name),
        contains('main'),
      );
      expect(
        branches.map((GitBranch branch) => branch.name),
        isNot(contains('heads/main')),
      );
    });
  });

  group('list', () {
    test('keeps the short upstream form beside a tag of the same name',
        () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String clone = await createClone(repo, 'clone');
      await repo.runGit(<String>['tag', 'main'], workingDirectory: clone);
      final ProcessGitRepository repository =
          await openAt(repo, directory: clone);

      final GitBranch branch = (await repository.branches.list()).single;
      expect(branch.name, 'main');
      expect(branch.upstream, 'origin/main');
    });
  });

  group('create', () {
    test('works in a bare repository', () async {
      final TestRepository repo = await createTestRepository();
      final String commit = await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String bare = await createBareClone(repo, 'bare.git');
      final ProcessGitRepository repository = await openAt(
        repo,
        directory: bare,
      );

      await repository.branches.create('topic', startPoint: commit);

      expect(
        await repository.refs.resolveRef('refs/heads/topic'),
        GitOid.parse(commit),
      );
    });
  });

  group('rename', () {
    test('works in a bare repository', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      await repo.runGit(<String>['branch', 'topic']);
      final String bare = await createBareClone(repo, 'bare.git');
      final ProcessGitRepository repository = await openAt(
        repo,
        directory: bare,
      );

      await repository.branches.rename('topic', 'feature');

      expect(await repository.refs.exists('refs/heads/topic'), isFalse);
      expect(await repository.refs.exists('refs/heads/feature'), isTrue);
    });
  });

  group('delete', () {
    test('refuses to delete the branch HEAD points at beside a tag', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      await repo.runGit(<String>['tag', 'main']);
      final ProcessGitRepository repository = await openAt(repo);

      await expectLater(
        repository.branches.delete('main', force: true),
        throwsA(isA<GitException>()),
      );
      expect(await repository.refs.exists('refs/heads/main'), isTrue);
      expect(await repository.branches.current(), 'main');
    });
  });
}
