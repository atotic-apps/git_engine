import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

/// Refusals and parsing of `GitTags`.
///
/// Every refusal arrives from a scripted runner with git's own English
/// standard error (the process backend forces `LC_ALL=C`), in LF and in CRLF
/// where a message may carry either, and one test per formulation the
/// supported git releases print.
void main() {
  group('GitTags.list parsing', () {
    const List<String> listCommand = <String>[
      'for-each-ref',
      '--format=%(refname)%09%(objectname)%09%(objecttype)%09%(*objectname)',
      'refs/tags',
    ];

    test('reads annotated and lightweight tags with their final object',
        () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          listCommand,
          GitRunResult.fromStrings(
            'refs/tags/v1\t$syntheticTagOid\ttag\t$syntheticCommitOid\n'
            'refs/tags/light\t$syntheticCommitOid\tcommit\t\n'
            'refs/tags/direct-tree\t$syntheticTreeOid\ttree\t\n',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(
        await repository.tags.list(),
        <GitTagRef>[
          GitTagRef(
            name: 'v1',
            oid: GitOid.parse(syntheticTagOid),
            target: GitOid.parse(syntheticCommitOid),
            isAnnotated: true,
          ),
          GitTagRef(
            name: 'light',
            oid: GitOid.parse(syntheticCommitOid),
            target: GitOid.parse(syntheticCommitOid),
            isAnnotated: false,
          ),
          GitTagRef(
            name: 'direct-tree',
            oid: GitOid.parse(syntheticTreeOid),
            target: GitOid.parse(syntheticTreeOid),
            isAnnotated: false,
          ),
        ],
      );
    });

    test('refuses a malformed for-each-ref line', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          listCommand,
          GitRunResult.fromStrings('v1 without a tab\n'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
          repository.tags.list(), throwsA(isA<FormatException>()));
    });
  });

  group('GitTags.create refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'a taken name raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String name = 'v1';
        final List<String> command = <String>[
          'tag',
          '--',
          name,
          syntheticCommitOid,
        ];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: "fatal: tag '$name' already exists$ending",
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).tags.create(
                name,
                GitOid.parse(syntheticCommitOid),
              ),
          throwsA(
            isA<GitRefExistsException>()
                .having(
                  (GitRefExistsException error) => error.name,
                  'name',
                  name,
                )
                .having(
                  (GitRefExistsException error) => error.cause,
                  'cause',
                  same(failure),
                )
                .having(
                  (GitRefExistsException error) => error is GitCommandException,
                  'not a command exception',
                  isFalse,
                ),
          ),
        );
      });

      test(
          'an unknown target raises the unknown-revision exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String target = syntheticCommitOid;
        for (final String stderr in <String>[
          "fatal: Failed to resolve '$target' as a valid ref.$ending",
          "fatal: cannot update ref 'refs/tags/v1': trying to write ref "
              "'refs/tags/v1' with nonexistent object $target$ending",
        ]) {
          final List<String> command = <String>['tag', '--', 'v1', target];
          final GitCommandException failure = GitCommandException(
            arguments: command,
            exitCode: 128,
            stderr: stderr,
          );
          final ScriptedGitRunner runner = ScriptedGitRunner()
            ..failWith(command, failure);

          await expectLater(
            syntheticWorkingRepository(runner)
                .tags
                .create('v1', GitOid.parse(target)),
            throwsA(
              isA<GitUnknownRevisionException>().having(
                (GitUnknownRevisionException error) => error.expression,
                'expression',
                target,
              ),
            ),
          );
        }
      });
    }

    test('leaves an unrecognized refusal unchanged', () async {
      const String name = 'v1';
      final List<String> command = <String>[
        'tag',
        '--',
        name,
        syntheticCommitOid
      ];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: "fatal: '$name' is not a valid tag name\n",
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).tags.create(
              name,
              GitOid.parse(syntheticCommitOid),
            ),
        throwsA(same(failure)),
      );
    });
  });

  group('GitTags.delete refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unknown tag raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String name = 'no-such-tag';
        final List<String> command = <String>['tag', '--delete', '--', name];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 1,
          stderr: "error: tag '$name' not found.$ending",
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).tags.delete(name),
          throwsA(
            isA<GitRefNotFoundException>()
                .having(
                  (GitRefNotFoundException error) => error.name,
                  'name',
                  name,
                )
                .having(
                  (GitRefNotFoundException error) => error.cause,
                  'cause',
                  same(failure),
                )
                .having(
                  (GitRefNotFoundException error) =>
                      error is GitCommandException,
                  'not a command exception',
                  isFalse,
                ),
          ),
        );
      });
    }
    test('matches a tag name git spells with its own case', () async {
      const String name = 'V1';
      final List<String> command = <String>['tag', '--delete', '--', name];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 1,
        stderr: "error: tag 'V1' not found.\n",
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).tags.delete(name),
        throwsA(
          isA<GitRefNotFoundException>().having(
            (GitRefNotFoundException error) => error.name,
            'name',
            name,
          ),
        ),
      );
    });
  });
}
