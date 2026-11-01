import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

/// Domain refusals of `GitRefs`: `resetSoft` on a revision that names
/// nothing.
///
/// Every failure arrives from a scripted runner with git's own English
/// standard error (the process backend forces `LC_ALL=C`), in LF and in CRLF,
/// and one test per formulation the supported git releases print.
void main() {
  group('GitRefs.resetSoft refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unknown target raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String target = 'no-such-branch';
        final List<String> command = <String>['reset', '--soft', target];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: "fatal: ambiguous argument '$target': unknown revision or "
              'path not in the working tree.$ending',
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).refs.resetSoft(target),
          throwsA(
            isA<GitUnknownRevisionException>()
                .having(
                  (GitUnknownRevisionException error) => error.expression,
                  'expression',
                  target,
                )
                .having(
                  (GitUnknownRevisionException error) => error.cause,
                  'cause',
                  same(failure),
                )
                .having(
                  (GitUnknownRevisionException error) =>
                      error is GitCommandException,
                  'not a command exception',
                  isFalse,
                ),
          ),
        );
      });
    }

    test('leaves an unrecognized refusal unchanged', () async {
      const String target = 'refs/heads/main';
      final List<String> command = <String>['reset', '--soft', target];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: "fatal: multiple updates for ref '$target' (via HEAD and "
            '$target)\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).refs.resetSoft(target),
        throwsA(same(failure)),
      );
    });
  });
}
