import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

/// Domain refusals of `GitWorktree`: a reset, a checkout, a detached
/// checkout or a new-branch checkout whose revision names nothing, and a
/// checkout refused because git would overwrite local changes or untracked
/// files.
///
/// Every failure arrives from a scripted runner with git's own English
/// standard error (the process backend forces `LC_ALL=C`), in LF and in CRLF,
/// and one test per formulation the supported git releases print. None of
/// them is a `GitCommandException`.
void main() {
  group('GitWorktree.checkout refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unknown branch raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String branch = 'no-such-branch';
        final List<String> command = <String>['checkout', branch, '--'];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 1,
              stderr: "error: pathspec '$branch' did not match any file(s) "
                  'known to git$ending',
            ),
          );
        final ScriptedGitRunner newerRunner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: 'fatal: invalid reference: $branch$ending',
            ),
          );

        for (final ScriptedGitRunner scripted in <ScriptedGitRunner>[
          runner,
          newerRunner,
        ]) {
          await expectLater(
            syntheticWorkingRepository(scripted).worktree.checkout(branch),
            throwsA(_notACommand(_unknownRevision(branch))),
          );
        }
      });

      test(
          'local changes it would overwrite raise the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String branch = 'topic';
        final List<String> command = <String>['checkout', branch, '--'];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 1,
              stderr: 'error: Your local changes to the following files '
                  'would be overwritten by checkout:$ending'
                  '\tnotes.txt$ending'
                  'Please commit your changes or stash them before you '
                  'switch branches.$ending'
                  'Aborting$ending',
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner).worktree.checkout(branch),
          throwsA(
            _notACommand(
              isA<GitLocalChangesOverwrittenException>().having(
                (GitLocalChangesOverwrittenException error) => error.paths,
                'paths',
                <String>['notes.txt'],
              ),
            ),
          ),
        );
      });
    }

    test('untracked files it would overwrite name their paths', () async {
      const String branch = 'topic';
      final List<String> command = <String>['checkout', branch, '--'];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 1,
            stderr: 'error: The following untracked working tree files '
                'would be overwritten by checkout:\n'
                '\tnew.txt\n'
                '\tother.txt\n'
                'Please move or remove them before you switch branches.\n'
                'Aborting\n',
          ),
        );

      await expectLater(
        syntheticWorkingRepository(runner).worktree.checkout(branch),
        throwsA(
          _notACommand(
            isA<GitLocalChangesOverwrittenException>().having(
              (GitLocalChangesOverwrittenException error) => error.paths,
              'paths',
              <String>['new.txt', 'other.txt'],
            ),
          ),
        ),
      );
    });

    test('paths keep the case git wrote them', () async {
      const String branch = 'topic';
      final List<String> command = <String>['checkout', branch, '--'];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 1,
            stderr: 'error: The following untracked working tree files '
                'would be overwritten by checkout:\n'
                '\tREADME.md\n'
                '\tsrc/Main.dart\n'
                'Please move or remove them before you switch branches.\n'
                'Aborting\n',
          ),
        );

      await expectLater(
        syntheticWorkingRepository(runner).worktree.checkout(branch),
        throwsA(
          _notACommand(
            isA<GitLocalChangesOverwrittenException>().having(
              (GitLocalChangesOverwrittenException error) => error.paths,
              'paths',
              <String>['README.md', 'src/Main.dart'],
            ),
          ),
        ),
      );
    });

    test('an unrecognized refusal stays the command failure', () async {
      const String branch = 'topic';
      final List<String> command = <String>['checkout', branch, '--'];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: 'error: you need to resolve your current index first\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).worktree.checkout(branch),
        throwsA(same(failure)),
      );
    });
  });

  group('GitWorktree.checkoutDetached refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unknown revision raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String rev = 'no-such-revision';
        final List<String> command = <String>['checkout', '--detach', rev];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: 'fatal: invalid reference: $rev$ending',
            ),
          );
        final ScriptedGitRunner olderRunner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: 'fatal: git checkout: --detach does not take a path '
                  "argument '$rev'$ending",
            ),
          );

        for (final ScriptedGitRunner scripted in <ScriptedGitRunner>[
          runner,
          olderRunner,
        ]) {
          await expectLater(
            syntheticWorkingRepository(scripted).worktree.checkoutDetached(rev),
            throwsA(_notACommand(_unknownRevision(rev))),
          );
        }
      });

      test(
          'untracked files it would overwrite raise the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String rev = 'dae535faac29fce97a60ef4b4d80ba8dd1e97ac0';
        final List<String> command = <String>['checkout', '--detach', rev];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 1,
              stderr: 'error: The following untracked working tree files '
                  'would be overwritten by checkout:$ending'
                  '\tnew.txt$ending'
                  'Please move or remove them before you change '
                  'branches.$ending'
                  'Aborting$ending',
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner).worktree.checkoutDetached(rev),
          throwsA(
            _notACommand(
              isA<GitLocalChangesOverwrittenException>().having(
                (GitLocalChangesOverwrittenException error) => error.paths,
                'paths',
                <String>['new.txt'],
              ),
            ),
          ),
        );
      });
    }
  });

  group('GitWorktree.checkoutNewBranch refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unknown start point raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String name = 'created';
        const String startPoint = 'no-such-start';
        final List<String> command = <String>[
          'checkout',
          '-b',
          name,
          startPoint,
        ];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: 'fatal: invalid reference: $startPoint$ending',
            ),
          );
        final ScriptedGitRunner olderRunner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 1,
              stderr: "error: pathspec '$startPoint' did not match any "
                  'file(s) known to git$ending',
            ),
          );
        final ScriptedGitRunner lastRunner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: "fatal: '$startPoint' is not a commit and a branch "
                  "'$name' cannot be created from it$ending",
            ),
          );

        for (final ScriptedGitRunner scripted in <ScriptedGitRunner>[
          runner,
          olderRunner,
          lastRunner,
        ]) {
          await expectLater(
            syntheticWorkingRepository(scripted).worktree.checkoutNewBranch(
                  name,
                  startPoint: startPoint,
                ),
            throwsA(_notACommand(_unknownRevision(startPoint))),
          );
        }
      });
    }

    test('local changes it would overwrite raise the domain exception',
        () async {
      const String name = 'created';
      const String startPoint = 'other-base';
      final List<String> command = <String>[
        'checkout',
        '-B',
        name,
        startPoint,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 1,
            stderr: 'error: Your local changes to the following files '
                'would be overwritten by checkout:\n'
                '\tnotes.txt\n'
                'Please commit your changes or stash them before you '
                'switch branches.\n'
                'Aborting\n',
          ),
        );

      await expectLater(
        syntheticWorkingRepository(runner).worktree.checkoutNewBranch(
              name,
              startPoint: startPoint,
              resetIfExists: true,
            ),
        throwsA(
          _notACommand(
            isA<GitLocalChangesOverwrittenException>().having(
              (GitLocalChangesOverwrittenException error) => error.paths,
              'paths',
              <String>['notes.txt'],
            ),
          ),
        ),
      );
    });
  });

  group('GitWorktree.reset refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unknown target raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        final List<String> mixedCommand = <String>[
          'reset',
          '--mixed',
          'no-such-target',
        ];
        final GitCommandException mixedFailure = GitCommandException(
          arguments: mixedCommand,
          exitCode: 128,
          stderr: "fatal: ambiguous argument 'no-such-target': unknown "
              'revision or path not in the working tree.$ending',
        );
        final ScriptedGitRunner mixedRunner = ScriptedGitRunner()
          ..failWith(mixedCommand, mixedFailure);
        const List<String> hardCommand = <String>[
          'reset',
          '--hard',
          'no-such-target',
        ];
        final GitCommandException hardFailure = GitCommandException(
          arguments: hardCommand,
          exitCode: 128,
          stderr: "fatal: bad revision 'no-such-target'$ending",
        );
        final ScriptedGitRunner hardRunner = ScriptedGitRunner()
          ..failWith(hardCommand, hardFailure);

        await expectLater(
          syntheticWorkingRepository(mixedRunner)
              .worktree
              .reset(target: 'no-such-target'),
          throwsA(
            _notACommand(
              _unknownRevision('no-such-target').having(
                (GitUnknownRevisionException error) => error.cause,
                'cause',
                same(mixedFailure),
              ),
            ),
          ),
        );
        await expectLater(
          syntheticWorkingRepository(hardRunner).worktree.reset(
                mode: GitResetMode.hard,
                target: 'no-such-target',
              ),
          throwsA(_notACommand(_unknownRevision('no-such-target'))),
        );
      });
    }
  });
}

/// Matcher of the unknown-revision domain failure for [expression].
TypeMatcher<GitUnknownRevisionException> _unknownRevision(String expression) {
  return isA<GitUnknownRevisionException>().having(
    (GitUnknownRevisionException error) => error.expression,
    'expression',
    expression,
  );
}

/// Matcher requiring [matcher] and a value that is no `GitCommandException`.
Matcher _notACommand(Matcher matcher) {
  return allOf(matcher, isNot(isA<GitCommandException>()));
}
