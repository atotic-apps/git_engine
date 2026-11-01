import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

const List<String> _versionCommand = <String>['--version'];

List<String> _mergeTreeCommand(String ours, String theirs) => <String>[
      'merge-tree',
      '--write-tree',
      '--name-only',
      '-z',
      ours,
      theirs,
    ];

void main() {
  final GitOid ours = GitOid.parse(syntheticFirstParentOid);
  final GitOid theirs = GitOid.parse(syntheticSecondParentOid);

  group('merge-tree output', () {
    test('reports a clean merge with no conflicting file', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _versionCommand,
          GitRunResult.fromStrings('git version 2.42.0\n'),
        )
        ..replyTo(
          _mergeTreeCommand(ours.value, theirs.value),
          GitRunResult.fromStrings('$syntheticTreeOid\u0000'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitMergeTreeResult result =
          await repository.merge.mergeTree(ours, theirs);

      expect(result.tree, GitOid.parse(syntheticTreeOid));
      expect(result.conflictingFiles, isEmpty);
      expect(result.isConflicted, isFalse);
      expect(
        runner.requests.map((GitRunRequest request) => request.arguments),
        <List<String>>[
          _versionCommand,
          _mergeTreeCommand(ours.value, theirs.value),
        ],
      );
    });

    test('reports conflicting files beside the merged tree', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _versionCommand,
          GitRunResult.fromStrings('git version 2.42.0\n'),
        )
        ..replyTo(
          _mergeTreeCommand(ours.value, theirs.value),
          GitRunResult.fromStrings(
            '$syntheticTreeOid\u0000src/main.dart\u0000docs/readme.md\u0000',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitMergeTreeResult result =
          await repository.merge.mergeTree(ours, theirs);

      expect(result.tree, GitOid.parse(syntheticTreeOid));
      expect(
        result.conflictingFiles,
        <String>['src/main.dart', 'docs/readme.md'],
      );
      expect(result.isConflicted, isTrue);
    });

    test('ignores the information section after the file list', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _versionCommand,
          GitRunResult.fromStrings('git version 2.42.0\n'),
        )
        ..replyTo(
          _mergeTreeCommand(ours.value, theirs.value),
          GitRunResult.fromStrings(
            '$syntheticTreeOid\u0000src/main.dart\u0000\u0000'
            'Auto-merging src/main.dart\u0000'
            'CONFLICT (content): Merge conflict in src/main.dart\u0000',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitMergeTreeResult result =
          await repository.merge.mergeTree(ours, theirs);

      expect(result.conflictingFiles, <String>['src/main.dart']);
    });

    test('accepts conflicts reported through exit code 1', () async {
      final List<String> command = _mergeTreeCommand(ours.value, theirs.value);
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _versionCommand,
          GitRunResult.fromStrings('git version 2.42.0\n'),
        )
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 1,
            stdout: '$syntheticTreeOid\u0000src/main.dart\u0000\u0000'
                'Auto-merging src/main.dart\u0000',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitMergeTreeResult result =
          await repository.merge.mergeTree(ours, theirs);

      expect(result.tree, GitOid.parse(syntheticTreeOid));
      expect(result.conflictingFiles, <String>['src/main.dart']);
    });

    test('rethrows an exit code other than 1', () async {
      final List<String> command = _mergeTreeCommand(ours.value, theirs.value);
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 2,
        stderr: 'fatal: not a valid object name',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _versionCommand,
          GitRunResult.fromStrings('git version 2.42.0\n'),
        )
        ..failWith(command, failure);
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.merge.mergeTree(ours, theirs),
        throwsA(same(failure)),
      );
    });

    test('reports merge-tree as unavailable on an older git', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _versionCommand,
          GitRunResult.fromStrings('git version 2.30.0\n'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.merge.mergeTree(ours, theirs),
        throwsA(
          isA<GitFeatureUnavailableException>()
              .having(
                (GitFeatureUnavailableException error) => error.operation,
                'operation',
                'mergeTree',
              )
              .having(
                (GitFeatureUnavailableException error) => error.requiredVersion,
                'requiredVersion',
                '2.38',
              )
              .having(
                (GitFeatureUnavailableException error) =>
                    error.installedVersion,
                'installedVersion',
                'git version 2.30.0',
              ),
        ),
      );
      expect(runner.requests, hasLength(1));
      expect(runner.requests.single.arguments, _versionCommand);
    });
  });
}
