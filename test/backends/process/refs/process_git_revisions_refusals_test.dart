import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

/// Domain refusals of `GitRevisions.symbolicFullName`: a revision that names
/// nothing, and an upstream that was never set.
///
/// The verification runs first (so a name that resolves to nothing never
/// reaches the symbolic read), and every failure arrives from a scripted
/// runner with git's own English standard error, in LF and in CRLF.
void main() {
  group('GitRevisions.symbolicFullName refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unset upstream raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String rev = '@{upstream}';
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(
            const <String>['rev-parse', '--verify', rev],
            GitCommandException(
              arguments: const <String>['rev-parse', '--verify', rev],
              exitCode: 128,
              stderr: 'fatal: no upstream configured for branch '
                  "'main'$ending",
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner)
              .revisions
              .symbolicFullName(rev, abbreviated: true),
          throwsA(
            isA<GitUnknownRevisionException>()
                .having(
                  (GitUnknownRevisionException error) => error.expression,
                  'expression',
                  rev,
                )
                .having(
                  (GitUnknownRevisionException error) =>
                      error is GitCommandException,
                  'not a command exception',
                  isFalse,
                ),
          ),
        );
        expect(runner.requests, hasLength(1));
        expect(runner.requests.single.arguments,
            const <String>['rev-parse', '--verify', rev]);
      });
    }

    test('an unknown revision raises the domain exception', () async {
      const String rev = 'no-such-branch';
      final List<String> command = <String>['rev-parse', '--verify', rev];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: "fatal: ambiguous argument '$rev': unknown revision or "
            'path not in the working tree.\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).revisions.symbolicFullName(rev),
        throwsA(
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

    test('a resolved revision reads its symbolic name back', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['rev-parse', '--verify', 'HEAD'],
          GitRunResult.fromStrings('${syntheticCommitOid}\n'),
        )
        ..replyTo(
          const <String>['rev-parse', '--symbolic-full-name', 'HEAD'],
          GitRunResult.fromStrings('refs/heads/main\n'),
        )
        ..replyTo(
          const <String>[
            'rev-parse',
            '--symbolic-full-name',
            '--abbrev-ref',
            'HEAD',
          ],
          GitRunResult.fromStrings('main\n'),
        );

      final GitRevisions revisions =
          syntheticWorkingRepository(runner).revisions;
      expect(await revisions.symbolicFullName('HEAD'), 'refs/heads/main');
      expect(
        await revisions.symbolicFullName('HEAD', abbreviated: true),
        'main',
      );
    });
  });
}
