import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

void main() {
  group('readTree', () {
    test('runs read-tree with the given tree', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          <String>['cat-file', '-t', syntheticTreeOid],
          GitRunResult.fromStrings('tree\n'),
        )
        ..replyTo(
          <String>['read-tree', syntheticTreeOid],
          GitRunResult.fromStrings(''),
        );
      final ProcessGitIndexedRepository repository =
          syntheticIndexedRepository(runner);

      await repository.index.readTree(GitOid.parse(syntheticTreeOid));

      expect(runner.requests, hasLength(2));
      expect(
        runner.requests.first.arguments,
        <String>['cat-file', '-t', syntheticTreeOid],
      );
      expect(
        runner.requests.last.arguments,
        <String>['read-tree', syntheticTreeOid],
      );
      expect(
        runner.requests.last.workingDirectory,
        repository.context.path,
      );
    });

    test('refuses a blob without running read-tree', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          <String>['cat-file', '-t', syntheticBlobOid],
          GitRunResult.fromStrings('blob\n'),
        );
      final ProcessGitIndexedRepository repository =
          syntheticIndexedRepository(runner);

      await expectLater(
        repository.index.readTree(GitOid.parse(syntheticBlobOid)),
        throwsA(isA<GitException>()),
      );

      expect(runner.requests.single.arguments,
          <String>['cat-file', '-t', syntheticBlobOid]);
    });

    test('refuses an unknown object without running read-tree', () async {
      const String unknown = '9999999999999999999999999999999999999999';
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(
          <String>['cat-file', '-t', unknown],
          GitCommandException(
            arguments: <String>['cat-file', '-t', unknown],
            exitCode: 1,
            stderr: 'fatal: Not a valid object name $unknown\n',
          ),
        );
      final ProcessGitIndexedRepository repository =
          syntheticIndexedRepository(runner);

      await expectLater(
        repository.index.readTree(GitOid.parse(unknown)),
        throwsA(isA<GitException>()),
      );

      expect(runner.requests.single.arguments,
          <String>['cat-file', '-t', unknown]);
    });
  });
}
