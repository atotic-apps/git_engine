@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../refs/refs_test_support.dart';
import '../support/test_repository.dart';

void main() {
  group('list', () {
    test('reads the tag name when a branch shares it', () async {
      final TestRepository repo = await createTestRepository();
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      await repo.runGit(<String>['tag', 'main']);
      final ProcessGitRepository repository = await openAt(repo);

      final List<GitTagRef> tags = await repository.tags.list();
      expect(
        tags.map((GitTagRef tag) => tag.name),
        contains('main'),
      );
      expect(
        tags.map((GitTagRef tag) => tag.name),
        isNot(contains('tags/main')),
      );

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
}
