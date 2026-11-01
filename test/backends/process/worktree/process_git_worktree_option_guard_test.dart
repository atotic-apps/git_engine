import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

void main() {
  bool untouched(ScriptedGitRunner runner) => runner.requests.isEmpty;

  group('worktree revisions that read like options name nothing', () {
    test('reset refuses before any command', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.worktree.reset(target: '--refile=x'),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(untouched(runner), isTrue);
    });

    test('checkout refuses before any command', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.worktree.checkout('-b-escape'),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(untouched(runner), isTrue);
    });

    test('checkoutDetached refuses before any command', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.worktree.checkoutDetached('--dry-run'),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(untouched(runner), isTrue);
    });

    test('checkoutNewBranch refuses on both parameters', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.worktree.checkoutNewBranch('--optionrush'),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      await expectLater(
        repository.worktree.checkoutNewBranch(
          'topic',
          startPoint: '-checkout-escape',
        ),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(untouched(runner), isTrue);
    });
  });

  group('paths stay data after the -- marker', () {
    test('add stages the literal path behind --', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['add', '--', '-staged-escape'],
          GitRunResult.fromStrings(''),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await repository.worktree.add(const <String>['-staged-escape']);

      expect(
        runner.requests.single.arguments,
        const <String>['add', '--', '-staged-escape'],
      );
    });

    test('isIgnored checks the literal path behind --', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(
          const <String>['check-ignore', '--quiet', '--', '-ignored-escape'],
          GitCommandException(
            arguments: const <String>[
              'check-ignore',
              '--quiet',
              '--',
              '-ignored-escape',
            ],
            exitCode: 1,
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(await repository.worktree.isIgnored('-ignored-escape'), isFalse);
      expect(
        runner.requests.single.arguments,
        const <String>['check-ignore', '--quiet', '--', '-ignored-escape'],
      );
    });
  });
}
