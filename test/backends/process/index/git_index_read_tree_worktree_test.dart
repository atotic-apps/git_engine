@Tags(['git'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';

void main() {
  group('readTree', () {
    test('leaves the files of the work tree unchanged', () async {
      final TestRepository repo = await createTestRepository();
      repo.writeFile('tracked.txt', 'one\n');
      await repo.runGit(<String>['add', '--', 'tracked.txt']);
      await repo.runGit(<String>['commit', '-m', 'initial']);
      final ProcessGitWorkingRepository repository =
          await ProcessGitEngine(runner: repo.runner)
              .openWorking(repo.directory.path) as ProcessGitWorkingRepository;
      final GitOid tree = await _treeWithFile(
        repository,
        'tracked.txt',
        'two\n',
      );

      await repository.index.readTree(tree);

      expect(await repository.index.writeTree(), tree);
      expect(
        File(TestRepository.join(repo.directory.path, 'tracked.txt'))
            .readAsStringSync(),
        'one\n',
      );
    });
  });
}

/// Writes a tree holding [name] with [content] and returns its object name.
Future<GitOid> _treeWithFile(
  GitRepository repository,
  String name,
  String content,
) async {
  final GitOid blob = await repository.objects.writeObject(
    GitObjectType.blob,
    utf8.encode(content),
  );
  final List<int> entry = <int>[...utf8.encode('100644 $name'), 0];
  for (var index = 0; index < blob.value.length; index += 2) {
    entry.add(int.parse(blob.value.substring(index, index + 2), radix: 16));
  }
  return repository.objects.writeObject(GitObjectType.tree, entry);
}
