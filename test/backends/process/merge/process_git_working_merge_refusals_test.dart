import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

/// Domain refusals of merging into a work tree: `GitWorkingMerge.merge` on a
/// revision that names nothing, on a history git would not overwrite, on
/// unrelated histories, and `abort` without a merge in progress; plus the
/// in-memory `mergeTree` of unrelated histories.
///
/// Every failure arrives from a scripted runner with git's own English
/// standard error (the process backend forces `LC_ALL=C`), in LF and in CRLF,
/// and one test per formulation the supported git releases print. None of
/// them is a `GitCommandException`.
void main() {
  /// A script answering the background reads `merge` performs: `HEAD` is
  /// known, and, after a failed merge, `MERGE_HEAD` is absent.
  ScriptedGitRunner backgroundRunner() {
    return ScriptedGitRunner()
      ..replyTo(
        const <String>['rev-parse', '--verify', '--quiet', 'HEAD'],
        GitRunResult.fromStrings('$syntheticCommitOid\n'),
      )
      ..failWith(
        const <String>['rev-parse', '--verify', '--quiet', 'MERGE_HEAD'],
        GitCommandException(
          arguments: const <String>[
            'rev-parse',
            '--verify',
            '--quiet',
            'MERGE_HEAD',
          ],
          exitCode: 1,
        ),
      );
  }

  List<String> mergeCommand(String rev) =>
      <String>['merge', '--no-edit', '--', rev];

  group('GitWorkingMerge.merge refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unknown revision raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String rev = 'no-such-branch';
        final List<String> command = mergeCommand(rev);
        final ScriptedGitRunner runner = backgroundRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: 'fatal: $rev - not something we can merge$ending',
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner).merge.merge(rev),
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

      test('refuses the older unknown-revision wording the same way', () async {
        const String rev = 'no-such-branch';
        final List<String> command = mergeCommand(rev);
        final ScriptedGitRunner runner = backgroundRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: 'merge: $rev - not something we can merge$ending',
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner).merge.merge(rev),
          throwsA(isA<GitUnknownRevisionException>()),
        );
      });

      test(
          'local changes it would overwrite raise the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        final List<String> command = mergeCommand('topic');
        final ScriptedGitRunner runner = backgroundRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 1,
              stderr: 'error: Your local changes to the following files '
                  'would be overwritten by merge:$ending'
                  '\tnotes.txt$ending'
                  'Please commit your changes or stash them before you '
                  'merge.$ending'
                  'Aborting$ending',
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner).merge.merge('topic'),
          throwsA(
            allOf(
              isA<GitLocalChangesOverwrittenException>().having(
                (GitLocalChangesOverwrittenException error) => error.paths,
                'paths',
                <String>['notes.txt'],
              ),
              isNot(isA<GitCommandException>()),
            ),
          ),
        );
      });

      test('paths keep the case git wrote them', () async {
        final List<String> command = mergeCommand('topic');
        final ScriptedGitRunner runner = backgroundRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 1,
              stderr: 'error: Your local changes to the following files '
                  'would be overwritten by merge:\n'
                  '\tREADME.md\n'
                  '\tsrc/Main.dart\n'
                  'Please commit your changes or stash them before you '
                  'merge.\n'
                  'Aborting\n',
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner).merge.merge('topic'),
          throwsA(
            allOf(
              isA<GitLocalChangesOverwrittenException>().having(
                (GitLocalChangesOverwrittenException error) => error.paths,
                'paths',
                <String>['README.md', 'src/Main.dart'],
              ),
              isNot(isA<GitCommandException>()),
            ),
          ),
        );
      });

      test(
          'unrelated histories raise the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        final List<String> command = mergeCommand('separate');
        final ScriptedGitRunner runner = backgroundRunner()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 128,
              stderr: 'fatal: refusing to merge unrelated '
                  'histories$ending',
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner).merge.merge('separate'),
          throwsA(
            allOf(
              isA<GitUnrelatedHistoriesException>(),
              isNot(isA<GitCommandException>()),
            ),
          ),
        );
      });

      test('an unrecognized refusal stays the command failure', () async {
        final List<String> command = mergeCommand('topic');
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: 'fatal: You have not concluded your merge '
              '(MERGE_HEAD exists).\n',
        );
        final ScriptedGitRunner runner = backgroundRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).merge.merge('topic'),
          throwsA(same(failure)),
        );
      });
    }
  });

  group('GitWorkingMerge.abort refusals', () {
    final List<String> command = const <String>['merge', '--abort'];

    test('without a merge in progress raises the domain exception', () async {
      final ScriptedGitRunner runner = backgroundRunner()
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 128,
            stderr: 'fatal: There is no merge to abort (MERGE_HEAD missing).'
                '\n',
          ),
        );
      final ScriptedGitRunner newerRunner = backgroundRunner()
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 128,
            stderr: 'fatal: There is no merge in progress (MERGE_HEAD '
                'missing).\n',
          ),
        );

      for (final ScriptedGitRunner scripted in <ScriptedGitRunner>[
        runner,
        newerRunner,
      ]) {
        await expectLater(
          syntheticWorkingRepository(scripted).merge.abort(),
          throwsA(
            allOf(
              isA<GitNoMergeInProgressException>(),
              isNot(isA<GitCommandException>()),
            ),
          ),
        );
      }
    });

    test('leaves an unrecognized refusal unchanged', () async {
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: 'fatal: cannot lock the work tree\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).merge.abort(),
        throwsA(same(failure)),
      );
    });
  });

  group('GitMerge.mergeTree refusals', () {
    List<String> treeCommand(String ours, String theirs) => <String>[
          'merge-tree',
          '--write-tree',
          '--name-only',
          '-z',
          ours,
          theirs,
        ];

    test('unrelated histories raise the domain exception', () async {
      final List<String> command = treeCommand(
        syntheticFirstParentOid,
        syntheticSecondParentOid,
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['--version'],
          GitRunResult.fromStrings('git version 2.44.0\n'),
        )
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 128,
            stderr: 'fatal: refusing to merge unrelated histories\n',
          ),
        );

      await expectLater(
        syntheticWorkingRepository(runner).merge.mergeTree(
              GitOid.parse(syntheticFirstParentOid),
              GitOid.parse(syntheticSecondParentOid),
            ),
        throwsA(
          allOf(
            isA<GitUnrelatedHistoriesException>(),
            isNot(isA<GitCommandException>()),
          ),
        ),
      );
    });

    test('leaves an unrecognized refusal unchanged', () async {
      final List<String> command = treeCommand(
        syntheticFirstParentOid,
        syntheticSecondParentOid,
      );
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: 'fatal: could not parse object '
            '${syntheticSecondParentOid}\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['--version'],
          GitRunResult.fromStrings('git version 2.44.0\n'),
        )
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).merge.mergeTree(
              GitOid.parse(syntheticFirstParentOid),
              GitOid.parse(syntheticSecondParentOid),
            ),
        throwsA(same(failure)),
      );
    });
  });
}
