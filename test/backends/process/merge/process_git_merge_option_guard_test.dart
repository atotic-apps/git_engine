import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

void main() {
  bool untouched(ScriptedGitRunner runner) => runner.requests.isEmpty;

  group('merge revisions that read like options name nothing', () {
    test('merge refuses before any command, whatever the mode', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.merge.merge('--onto=x'),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      await expectLater(
        repository.merge.merge(
          '--onto=x',
          mode: GitMergeMode.fastForwardOnly,
        ),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(untouched(runner), isTrue);
    });

    test('the merge revision stays data behind the -- marker', () async {
      final List<String> command = <String>['merge', '--no-edit', '--', 'main'];
      final GitOid head = GitOid.parse(syntheticCommitOid);
      final List<String> headResolve = <String>[
        'rev-parse',
        '--verify',
        '--quiet',
        'HEAD',
      ];
      final List<String> mergeHeadResolve = <String>[
        'rev-parse',
        '--verify',
        '--quiet',
        'MERGE_HEAD',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(headResolve, GitRunResult.fromStrings('${head.value}\n'))
        ..replyTo(command, GitRunResult.fromStrings(''))
        ..replyTo(mergeHeadResolve, GitRunResult.fromStrings(''));
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await repository.merge.merge('main');
      final GitRunRequest request = runner.requests
          .singleWhere((GitRunRequest sent) => sent.arguments.first == 'merge');
      expect(
        request.arguments,
        command,
        reason: 'the revision must come after the -- marker, never as an '
            'option',
      );
    });
  });
}
