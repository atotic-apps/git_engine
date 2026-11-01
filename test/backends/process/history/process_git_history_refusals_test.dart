import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

/// Domain refusals of `GitHistory`: `lastCommitTouching`, `commitsTouching`
/// and `commitsSince` on revisions that name nothing.
///
/// Every failure arrives from a scripted runner with git's own English
/// standard error (the process backend forces `LC_ALL=C`), in LF and in CRLF,
/// and one test per formulation the supported git releases print. None of
/// them is a `GitCommandException`.
void main() {
  group('GitHistory.lastCommitTouching refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unknown starting revision raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String rev = 'no-such-branch';
        final List<String> command = <String>[
          'log',
          '-1',
          '--format=%H',
          '--end-of-options',
          rev,
          '--',
          'notes.txt',
        ];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: "fatal: ambiguous argument '$rev': unknown revision or "
              'path not in the working tree.$ending',
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner)
              .history
              .lastCommitTouching('notes.txt', rev: rev),
          throwsA(
            allOf(
              isA<GitUnknownRevisionException>()
                  .having(
                    (GitUnknownRevisionException error) => error.expression,
                    'expression',
                    rev,
                  )
                  .having(
                    (GitUnknownRevisionException error) => error.cause,
                    'cause',
                    same(failure),
                  ),
              isNot(isA<GitCommandException>()),
            ),
          ),
        );
      });

      test(
          'an object name git cannot even read raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String rev = 'dae535faac29fce97a60ef4b4d80ba8dd1e97ac0';
        final List<String> command = <String>[
          'log',
          '-1',
          '--format=%H',
          '--end-of-options',
          rev,
          '--',
          'notes.txt',
        ];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: "fatal: bad revision '$rev'$ending",
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner)
              .history
              .lastCommitTouching('notes.txt', rev: rev),
          throwsA(
            allOf(
              isA<GitUnknownRevisionException>().having(
                (GitUnknownRevisionException error) => error.expression,
                'expression',
                rev,
              ),
              isNot(isA<GitCommandException>()),
            ),
          ),
        );
      });
    }

    test('leaves an unrecognized refusal unchanged', () async {
      final List<String> command = <String>[
        'log',
        '-1',
        '--format=%H',
        '--end-of-options',
        'HEAD',
        '--',
        'notes.txt',
      ];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: 'fatal: not a git repository (or any of the parent '
            'directories): .git\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner)
            .history
            .lastCommitTouching('notes.txt', rev: 'HEAD'),
        throwsA(same(failure)),
      );
    });

    test('an unqualified walk rethrows its command failure', () async {
      final List<String> command = <String>[
        'log',
        '-1',
        '--format=%H',
        '--',
        'notes.txt',
      ];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: "fatal: your current branch 'main' does not have any "
            'commits yet\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).history.lastCommitTouching(
              'notes.txt',
            ),
        throwsA(same(failure)),
      );
    });
  });

  group('GitHistory.commitsTouching refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unknown starting revision raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String from = 'no-such-branch';
        final List<String> command = <String>[
          'log',
          '--format=%H',
          '--end-of-options',
          '$from..HEAD',
          '--',
          'notes.txt',
        ];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: "fatal: ambiguous argument '$from..HEAD': unknown "
                  'revision or path not in the working tree.$ending',
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner)
              .history
              .commitsTouching('notes.txt', from: from),
          throwsA(_unknownRange('$from..HEAD')),
        );
      });

      test(
          'an unknown end revision raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String to = 'no-such-branch';
        final List<String> command = <String>[
          'log',
          '--format=%H',
          '--end-of-options',
          'main..$to',
          '--',
          'notes.txt',
        ];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: "fatal: ambiguous argument 'main..$to': unknown "
                  'revision or path not in the working tree.$ending',
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner).history.commitsTouching(
                'notes.txt',
                from: 'main',
                to: to,
              ),
          throwsA(_unknownRange('main..$to')),
        );
      });

      test(
          'an unrecognized refusal over an implicit range stays the command '
          'failure (${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        final List<String> command = <String>[
          'log',
          '--format=%H',
          '--end-of-options',
          'HEAD',
          '--',
          'notes.txt',
        ];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: 'fatal: not a git repository (or any of the parent '
              'directories): .git$ending',
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).history.commitsTouching(
                'notes.txt',
              ),
          throwsA(same(failure)),
        );
      });
    }
  });

  group('GitHistory.commitsSince refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unknown base revision raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String base = 'no-such-base';
        final List<String> command = <String>[
          'log',
          '--format=%H%x1f%s',
          '--end-of-options',
          '$base..main',
        ];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: "fatal: ambiguous argument '$base..main': unknown revision "
              'or path not in the working tree.$ending',
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).history.commitsSince(base, 'main'),
          throwsA(
            allOf(
              _unknownRange('$base..main').having(
                (GitUnknownRevisionException error) => error.cause,
                'cause',
                same(failure),
              ),
              isNot(isA<GitCommandException>()),
            ),
          ),
        );
      });

      test(
          'an unknown tip revision raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String tip = 'no-such-tip';
        final List<String> command = <String>[
          'log',
          '--format=%H%x1f%s',
          '--end-of-options',
          'main..$tip',
        ];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: "fatal: bad revision 'main..$tip'$ending",
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner).history.commitsSince('main', tip),
          throwsA(_unknownRange('main..$tip')),
        );
      });

      test(
          'an unrecognized refusal stays the command failure '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        final List<String> command = <String>[
          'log',
          '--format=%H%x1f%s',
          '--end-of-options',
          'main..other',
        ];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: 'fatal: not a git repository (or any of the parent '
              'directories): .git$ending',
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).history.commitsSince(
                'main',
                'other',
              ),
          throwsA(same(failure)),
        );
      });
    }
  });
}

/// Matcher of the unknown-revision domain failure for [expression].
TypeMatcher<GitUnknownRevisionException> _unknownRange(String expression) {
  return isA<GitUnknownRevisionException>().having(
    (GitUnknownRevisionException error) => error.expression,
    'expression',
    expression,
  );
}
