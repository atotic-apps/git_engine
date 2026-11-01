import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

void main() {
  bool untouched(ScriptedGitRunner runner) => runner.requests.isEmpty;

  group('history revisions that read like options name nothing', () {
    test('lastCommitTouching refuses before any command', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.history.lastCommitTouching(
          'tracked.txt',
          rev: '-grep=x',
        ),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(untouched(runner), isTrue);
    });

    test('commitsTouching refuses on both range ends', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.history.commitsTouching(
          'tracked.txt',
          from: '-diff-filter=x',
        ),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      await expectLater(
        repository.history.commitsTouching(
          'tracked.txt',
          to: '-diff-filter=x',
        ),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(untouched(runner), isTrue);
    });

    test('commitsSince refuses before any command', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.history.commitsSince('-stat', 'HEAD'),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(untouched(runner), isTrue);
    });

    test('the walk keeps the path data behind the -- marker', () async {
      final List<String> command = <String>[
        'log',
        '--format=%H',
        '--end-of-options',
        'HEAD',
        '--',
        'tracked.txt',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(command, GitRunResult.fromStrings(''));
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(await repository.history.commitsTouching('tracked.txt'), isEmpty);
      expect(
        runner.requests.single.arguments,
        command,
        reason: 'the path must come after the -- marker, never as an option',
      );
    });
  });
}
