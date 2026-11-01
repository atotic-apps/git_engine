import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/scripted_git_runner.dart';
import 'support/synthetic_git_support.dart';

const List<String> _openKindCommand = <String>[
  'rev-parse',
  '--is-bare-repository',
];

/// The command reading the SSH command chosen in a configuration file.
const List<String> sshCommandProbe = <String>[
  'config',
  '--get',
  'core.sshCommand',
];

/// The scripted failure of a configuration without `core.sshCommand`.
GitCommandException unsetSshCommand() => GitCommandException(
      arguments: sshCommandProbe,
      exitCode: 1,
    );

void main() {
  group('repository kind recognition', () {
    test('propagates the runner not-a-repository failure', () async {
      final GitNotARepositoryException failure = GitNotARepositoryException(
        cause: GitCommandException(
          arguments: _openKindCommand,
          exitCode: 128,
          stderr: 'fatal: not a git repository (or any parent): .git\n',
        ),
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(_openKindCommand, failure);
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.open(syntheticRepositoryPath),
        throwsA(same(failure)),
      );
    });

    test('refuses to open a working repository as bare', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(_openKindCommand, GitRunResult.fromStrings('false\n'));
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.openBare(syntheticRepositoryPath),
        throwsA(
          isA<GitNotABareRepositoryException>().having(
            (GitNotABareRepositoryException error) => error.path,
            'path',
            syntheticRepositoryPath,
          ),
        ),
      );
    });

    test('refuses to open a bare repository as working', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(_openKindCommand, GitRunResult.fromStrings('true\n'));
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.openWorking(syntheticRepositoryPath),
        throwsA(
          isA<GitNotAWorkingRepositoryException>().having(
            (GitNotAWorkingRepositoryException error) => error.path,
            'path',
            syntheticRepositoryPath,
          ),
        ),
      );
    });

    test('opens the matching repository type for each kind', () async {
      final ScriptedGitRunner workingRunner = ScriptedGitRunner()
        ..replyTo(_openKindCommand, GitRunResult.fromStrings('false\n'));
      final ScriptedGitRunner bareRunner = ScriptedGitRunner()
        ..replyTo(_openKindCommand, GitRunResult.fromStrings('true\n'));

      expect(
        await syntheticEngine(workingRunner).open(syntheticRepositoryPath),
        isA<ProcessGitWorkingRepository>(),
      );
      expect(
        await syntheticEngine(bareRunner).open(syntheticRepositoryPath),
        isA<ProcessGitFileBareRepository>(),
      );
    });
  });

  group('exchange failure recognition', () {
    test('types a non-fast-forward push as rejected', () async {
      final List<String> command = <String>[
        'push',
        '--',
        'origin',
        'refs/heads/main:refs/heads/main',
      ];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 1,
        stderr: ' ! [rejected] main -> main (non-fast-forward)\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..failWith(command, failure);
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.push(
          syntheticWorkingRepository(runner),
          remote: 'origin',
          refspecs: const <String>['refs/heads/main:refs/heads/main'],
        ),
        throwsA(
          isA<GitPushRejectedException>().having(
            (GitPushRejectedException error) => error.cause,
            'cause',
            same(failure),
          ),
        ),
      );
      expect(runner.requests.last.arguments, command);
    });

    test('types a fetch-first push as rejected', () async {
      final List<String> command = <String>[
        'push',
        '--',
        'origin',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 1,
            stderr: ' ! [rejected] main -> main (fetch first)\n',
          ),
        );
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.push(syntheticWorkingRepository(runner), remote: 'origin'),
        throwsA(isA<GitPushRejectedException>()),
      );
    });

    test('types a missing remote ref during fetch', () async {
      final List<String> command = <String>[
        'fetch',
        '--no-tags',
        '--',
        'origin',
        'refs/heads/missing:refs/remotes/origin/missing',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 128,
            stderr: "fatal: couldn't find remote ref refs/heads/missing\n",
          ),
        );
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.fetch(
          syntheticWorkingRepository(runner),
          remote: 'origin',
          refspecs: const <String>[
            'refs/heads/missing:refs/remotes/origin/missing',
          ],
        ),
        throwsA(isA<GitRemoteRefNotFoundException>()),
      );
    });

    test('types an unqualified push destination as a missing remote ref',
        () async {
      final List<String> command = <String>[
        'push',
        '--',
        'origin',
        'refs/heads/new:refs/heads/new',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 1,
            stderr: 'error: unable to push to unqualified destination: '
                'refs/heads/new\n',
          ),
        );
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.push(
          syntheticWorkingRepository(runner),
          remote: 'origin',
          refspecs: const <String>['refs/heads/new:refs/heads/new'],
        ),
        throwsA(isA<GitRemoteRefNotFoundException>()),
      );
    });

    test('leaves an unrecognised exchange failure unchanged', () async {
      final List<String> command = <String>[
        'fetch',
        '--',
        'origin',
      ];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: 'fatal: unable to access the remote\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..failWith(command, failure);
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.fetch(syntheticWorkingRepository(runner), remote: 'origin'),
        throwsA(same(failure)),
      );
    });
  });

  group('connection failure recognition', () {
    /// Expects [stderr] to classify as [matcher] for a fetch from [remote].
    Future<void> expectClassified(
      String remote,
      String stderr,
      Matcher matcher,
    ) async {
      final List<String> command = <String>[
        'fetch',
        '--',
        remote,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..failWith(
          command,
          GitCommandException(
              arguments: command, exitCode: 128, stderr: stderr),
        );
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.fetch(syntheticWorkingRepository(runner), remote: remote),
        throwsA(matcher),
      );
    }

    test('types an HTTPS authentication failure', () async {
      await expectClassified(
        'https://example.com/repo.git',
        "fatal: Authentication failed for 'https://example.com/repo.git/'\n",
        isA<GitAuthenticationException>(),
      );
    });

    test('types HTTPS prompts disabled as refused authentication', () async {
      await expectClassified(
        'https://example.com/repo.git',
        'fatal: could not read Username for \'https://example.com\': '
            'terminal prompts disabled\n',
        isA<GitAuthenticationException>(),
      );
    });

    test('types an HTTPS host that cannot be resolved as unreachable',
        () async {
      await expectClassified(
        'https://example.com/repo.git',
        "fatal: unable to access 'https://example.com/repo.git/': "
            'Could not resolve host: example.com\n',
        isA<GitRemoteUnreachableException>(),
      );
    });

    test('types an HTTPS absent repository as not found', () async {
      await expectClassified(
        'https://example.com/repo.git',
        'remote: Repository not found.\n'
            "fatal: repository 'https://example.com/repo.git/' not found\n",
        isA<GitRemoteRepositoryNotFoundException>(),
      );
    });

    test('types an SSH authentication refusal', () async {
      await expectClassified(
        'ssh://git@example.com/repo.git',
        'git@example.com: Permission denied (publickey).\r\n'
            'fatal: Could not read from remote repository.\r\n',
        isA<GitAuthenticationException>(),
      );
    });

    test('types an SSH host that cannot be resolved as unreachable', () async {
      await expectClassified(
        'ssh://git@nosuchhost.example/repo.git',
        'ssh: Could not resolve hostname nosuchhost.example: '
            'Name or service not known\r\n'
            'fatal: Could not read from remote repository.\r\n',
        isA<GitRemoteUnreachableException>(),
      );
    });

    test('types an SSH absent repository as not found', () async {
      await expectClassified(
        'ssh://git@example.com/srv/git/nope.git',
        "fatal: '/srv/git/nope.git' does not appear to be a git repository\n"
            'fatal: Could not read from remote repository.\n',
        isA<GitRemoteRepositoryNotFoundException>(),
      );
    });

    test('types an SSH host key that cannot be verified as unreachable',
        () async {
      await expectClassified(
        'ssh://git@example.com/repo.git',
        'Host key verification failed.\r\n'
            'fatal: Could not read from remote repository.\r\n',
        isA<GitRemoteUnreachableException>(),
      );
    });

    test('classifies the failures of a clone the same way', () async {
      final List<String> command = <String>[
        'clone',
        '--',
        'https://example.com/repo.git',
        '/repo-clone',
      ];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr:
            "fatal: Authentication failed for 'https://example.com/repo.git/'\n",
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..failWith(command, failure);
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.clone(
          'https://example.com/repo.git',
          '/repo-clone',
        ),
        throwsA(
          isA<GitAuthenticationException>().having(
            (GitAuthenticationException error) => error.cause,
            'cause',
            same(failure),
          ),
        ),
      );
    });

    for (final bool bare in <bool>[false, true]) {
      for (final String ending in <String>['\n', '\r\n']) {
        test(
            'types an absent local ${bare ? 'bare ' : ''}clone source '
            'with ${ending.length == 1 ? 'LF' : 'CRLF'} diagnostics', () async {
          const String source = '/var/folders/test/T/client/missing';
          const String target = '/repo-clone';
          final List<String> command = <String>[
            'clone',
            if (bare) '--bare',
            '--',
            source,
            target,
          ];
          final GitCommandException failure = GitCommandException(
            arguments: command,
            exitCode: 128,
            stderr: "fatal: repository '$source' does not exist$ending",
          );
          final ScriptedGitRunner runner = ScriptedGitRunner()
            ..failWith(command, failure);
          final ProcessGitEngine engine = syntheticEngine(runner);

          await expectLater(
            bare
                ? engine.cloneBare(source, target)
                : engine.clone(source, target),
            throwsA(
              isA<GitRemoteRepositoryNotFoundException>().having(
                (GitRemoteRepositoryNotFoundException error) => error.cause,
                'cause',
                same(failure),
              ),
            ),
          );
        });
      }
    }

    for (final String diagnostic in <String>[
      "fatal: path 'missing' does not exist in 'HEAD'\n",
      "fatal: repository 'missing' does not exist in index\n",
    ]) {
      test(
          'does not classify another missing entity as a missing repository: '
          '${diagnostic.trim()}', () async {
        final List<String> command = <String>['clone', '--', '/repo', '/clone'];
        final GitCommandException failure = GitCommandException(
          arguments: command,
          exitCode: 128,
          stderr: diagnostic,
        );
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(command, failure);

        await expectLater(
          syntheticEngine(runner).clone('/repo', '/clone'),
          throwsA(same(failure)),
        );
      });
    }

    test('leaves an unrecognised clone failure unchanged', () async {
      final List<String> command = <String>[
        'clone',
        '--',
        '/repo',
        '/repo-clone',
      ];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: "fatal: destination path '/repo-clone' already exists and is "
            'not an empty directory.\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.clone('/repo', '/repo-clone'),
        throwsA(same(failure)),
      );
    });
  });
}
