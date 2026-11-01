import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

/// Refusals and parsing of `GitBranches`.
///
/// Every refusal arrives from a scripted runner with git's own English
/// standard error (the process backend forces `LC_ALL=C`), in LF and in CRLF
/// where a message may carry either, and one test per formulation the
/// supported git releases print.
void main() {
  group('GitBranches.current reading', () {
    test('reads the current branch through symbolic-ref', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['symbolic-ref', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('refs/heads/main\n'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(await repository.branches.current(), 'main');
    });
  });

  group('GitBranches.list parsing', () {
    const List<String> listCommand = <String>[
      'for-each-ref',
      '--format=%(refname)%09%(objectname)%09%(HEAD)%09%(upstream)',
      'refs/heads',
    ];

    test('reads the short name, the tip, the marker and the upstream',
        () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          listCommand,
          GitRunResult.fromStrings(
            'refs/heads/main\t$syntheticCommitOid\t*\t'
            'refs/remotes/origin/main\n'
            'refs/heads/topic\t$syntheticTreeOid\t\t\n',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(
        await repository.branches.list(),
        <GitBranch>[
          GitBranch(
            name: 'main',
            oid: GitOid.parse(syntheticCommitOid),
            isCurrent: true,
            upstream: 'origin/main',
          ),
          GitBranch(
            name: 'topic',
            oid: GitOid.parse(syntheticTreeOid),
            isCurrent: false,
          ),
        ],
      );
    });

    test('refuses a malformed for-each-ref line', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          listCommand,
          GitRunResult.fromStrings('main without a tab\n'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.branches.list(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('GitBranches.listRemote parsing', () {
    const List<String> listCommand = <String>[
      'for-each-ref',
      '--format=%(refname)%09%(objectname)%09%(symref)',
      'refs/remotes',
    ];

    test('skips the symbolic remote HEAD reference', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          listCommand,
          GitRunResult.fromStrings(
            'refs/remotes/origin/HEAD\t$syntheticCommitOid\t'
            'refs/remotes/origin/main\n'
            'refs/remotes/origin/main\t$syntheticCommitOid\t\n',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(
        await repository.branches.listRemote(),
        <GitRef>[
          GitRef(
            name: 'refs/remotes/origin/main',
            oid: GitOid.parse(syntheticCommitOid),
          ),
        ],
      );
    });

    test('asks only one remote when one is given', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>[
            'for-each-ref',
            '--format=%(refname)%09%(objectname)%09%(symref)',
            'refs/remotes/origin',
          ],
          GitRunResult.fromStrings(
            'refs/remotes/origin/main\t$syntheticCommitOid\t\n',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(
        await repository.branches.listRemote(remote: 'origin'),
        <GitRef>[
          GitRef(
            name: 'refs/remotes/origin/main',
            oid: GitOid.parse(syntheticCommitOid),
          ),
        ],
      );
      expect(
        runner.requests.single.arguments,
        const <String>[
          'for-each-ref',
          '--format=%(refname)%09%(objectname)%09%(symref)',
          'refs/remotes/origin',
        ],
      );
    });
  });

  group('GitBranches.create refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      final String label = ending.length == 1 ? 'LF' : 'CRLF';

      test('a taken name raises the domain exception ($label stderr)',
          () async {
        const String name = 'topic';
        final List<String> command = <String>['branch', '--', name];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: "fatal: a branch named '$name' already exists$ending",
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).branches.create(name),
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
          'an unknown start point raises the unknown-revision exception '
          '($label stderr)', () async {
        const String start = 'no-such-start';
        final List<String> command = <String>['branch', '--', 'topic', start];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: "fatal: not a valid object name: '$start'$ending",
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).branches.create(
                'topic',
                startPoint: start,
              ),
          throwsA(
            isA<GitUnknownRevisionException>()
                .having(
                  (GitUnknownRevisionException error) => error.expression,
                  'expression',
                  start,
                )
                .having(
                  (GitUnknownRevisionException error) => error.cause,
                  'cause',
                  same(failure),
                ),
          ),
        );
      });
    }

    test('leaves an unrecognized refusal unchanged', () async {
      const String name = 'topic';
      final List<String> command = <String>['branch', '--', name];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: "fatal: '$name' is a forbidden branch name\n",
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).branches.create(name),
        throwsA(same(failure)),
      );
    });
  });

  group('GitBranches.rename refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      final String label = ending.length == 1 ? 'LF' : 'CRLF';

      test('a taken new name raises the domain exception ($label stderr)',
          () async {
        const String name = 'topic';
        const String newName = 'main';
        final List<String> command = <String>[
          'branch',
          '-m',
          '--',
          name,
          newName
        ];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: "fatal: a branch named '$newName' already exists$ending",
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).branches.rename(name, newName),
          throwsA(
            isA<GitRefExistsException>().having(
              (GitRefExistsException error) => error.name,
              'name',
              newName,
            ),
          ),
        );
      });

      test(
          'an unknown branch raises the domain exception on every '
          'formulation ($label stderr)', () async {
        const String name = 'no-such-branch';
        for (final String stderr in <String>[
          "fatal: No branch named '$name'.$ending",
          'error: refname refs/heads/$name not found${ending}fatal: branch '
              'rename failed$ending',
        ]) {
          final List<String> command = <String>[
            'branch',
            '-m',
            '--',
            name,
            'renamed',
          ];
          final GitCommandException failure = GitCommandException(
            arguments: command,
            exitCode: 128,
            stderr: stderr,
          );
          final ScriptedGitRunner runner = ScriptedGitRunner()
            ..failWith(command, failure);

          await expectLater(
            syntheticWorkingRepository(runner).branches.rename(
                  name,
                  'renamed',
                ),
            throwsA(
              isA<GitRefNotFoundException>().having(
                (GitRefNotFoundException error) => error.name,
                'name',
                name,
              ),
            ),
          );
        }
      });
    }
  });

  group('GitBranches.delete refusals', () {
    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unmerged branch raises the domain exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String branch = 'topic';
        final List<String> command = <String>['branch', '-d', '--', branch];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..detachHead()
          ..failWith(
            command,
            GitCommandException(
              arguments: command,
              exitCode: 1,
              stderr: "error: the branch '$branch' is not fully merged.$ending"
                  "If you are sure you want to delete it, run 'git branch -D "
                  "$branch'.$ending",
            ),
          );

        await expectLater(
          syntheticWorkingRepository(runner).branches.delete(branch),
          throwsA(
            isA<GitBranchNotMergedException>()
                .having(
                  (GitBranchNotMergedException error) => error.branch,
                  'branch',
                  branch,
                )
                .having(
                  (GitBranchNotMergedException error) =>
                      error is GitCommandException,
                  'not a command exception',
                  isFalse,
                ),
          ),
        );
      });
    }

    for (final bool force in <bool>[false, true]) {
      test(
          'an unknown branch raises the domain exception '
          '(force: $force)', () async {
        const String branch = 'no-such-branch';
        final List<String> command = <String>[
          'branch',
          force ? '-D' : '-d',
          '--',
          branch,
        ];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 1,
          stderr: "error: branch '$branch' not found.\n",
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..detachHead()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).branches.delete(
                branch,
                force: force,
              ),
          throwsA(
            isA<GitRefNotFoundException>()
                .having(
                  (GitRefNotFoundException error) => error.name,
                  'name',
                  branch,
                )
                .having(
                  (GitRefNotFoundException error) => error.cause,
                  'cause',
                  same(failure),
                ),
          ),
        );
      });
    }

    test('refuses the branch HEAD points at before running git', () async {
      const String branch = 'topic';
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['symbolic-ref', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('refs/heads/$branch\n'),
        );

      await expectLater(
        syntheticWorkingRepository(runner).branches.delete(
              branch,
              force: true,
            ),
        throwsA(
          isA<GitException>()
              .having(
                (GitException error) => error is GitCommandException,
                'not a command exception',
                isFalse,
              )
              .having(
                (GitException error) => error.message,
                'message',
                contains(branch),
              ),
        ),
      );
      expect(runner.requests, hasLength(1));
    });

    test('matches a branch name git spells with its own case', () async {
      const String branch = 'Topic';
      final List<String> command = <String>['branch', '-D', '--', branch];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 1,
        stderr: "error: branch 'Topic' not found.\n",
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..detachHead()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).branches.delete(
              branch,
              force: true,
            ),
        throwsA(
          isA<GitRefNotFoundException>().having(
            (GitRefNotFoundException error) => error.name,
            'name',
            branch,
          ),
        ),
      );
    });

    test('leaves an unrecognized refusal unchanged', () async {
      const String branch = 'topic';
      final List<String> command = <String>['branch', '-d', '--', branch];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 1,
        stderr: "error: Cannot delete branch 'topic' checked out at '/repo'\n",
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..detachHead()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).branches.delete(branch),
        throwsA(same(failure)),
      );
    });
  });

  group('GitBranches.setUpstream refusals', () {
    test('an unknown branch raises the domain exception', () async {
      const String branch = 'no-such-branch';
      final List<String> command = <String>[
        'branch',
        '--set-upstream-to=origin/main',
        '--',
        branch,
      ];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: "fatal: branch '$branch' does not exist\n",
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);

      await expectLater(
        syntheticWorkingRepository(runner).branches.setUpstream(
              branch,
              'origin/main',
            ),
        throwsA(
          isA<GitRefNotFoundException>().having(
            (GitRefNotFoundException error) => error.name,
            'name',
            branch,
          ),
        ),
      );
    });

    for (final String ending in <String>['\n', '\r\n']) {
      test(
          'an unknown upstream raises the unknown-revision exception '
          '(${ending.length == 1 ? 'LF' : 'CRLF'} stderr)', () async {
        const String upstream = 'origin/no-such';
        final List<String> command = <String>[
          'branch',
          '--set-upstream-to=$upstream',
          '--',
          'main',
        ];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: "fatal: the requested upstream branch '$upstream' does not "
              'exist$ending',
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticWorkingRepository(runner).branches.setUpstream(
                'main',
                upstream,
              ),
          throwsA(
            isA<GitUnknownRevisionException>().having(
              (GitUnknownRevisionException error) => error.expression,
              'expression',
              upstream,
            ),
          ),
        );
      });
    }
  });
}
