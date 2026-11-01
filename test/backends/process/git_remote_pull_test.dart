import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/scripted_git_runner.dart';
import 'support/synthetic_git_support.dart';

/// A platform with no environment variable, identical on every machine.
final GitPlatform plainPlatform = GitPlatform(
  operatingSystem: GitOperatingSystem.linux,
  currentDirectory: '/',
);

/// The command reading the SSH command chosen in a configuration file; a
/// fetch or a push probes it before running.
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

/// The scripted failure of a configuration key that holds no value.
GitCommandException unsetConfigKey(String key) => GitCommandException(
      arguments: <String>['config', '--local', '--get', '--', key],
      exitCode: 1,
    );

/// The request of [runner] running [subcommand], whatever else ran around it.
GitRunRequest requestRunning(ScriptedGitRunner runner, String subcommand) {
  return runner.requests.singleWhere(
    (GitRunRequest request) => request.arguments.contains(subcommand),
  );
}

void main() {
  group('pull arguments', () {
    test('a pull without arguments follows the upstream of the branch',
        () async {
      const String trackingRef = 'refs/remotes/origin/main';
      final List<String> fetchCommand = <String>[
        'fetch',
        '--no-tags',
        '--',
        'origin',
        'main'
      ];
      final List<String> mergeCommand = <String>[
        'merge',
        '--no-edit',
        '--',
        trackingRef,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['symbolic-ref', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('refs/heads/main\n'),
        )
        ..replyTo(
          const <String>[
            'config',
            '--local',
            '--get',
            '--',
            'branch.main.remote'
          ],
          GitRunResult.fromStrings('origin\n'),
        )
        ..replyTo(
          const <String>[
            'config',
            '--local',
            '--get',
            '--',
            'branch.main.merge'
          ],
          GitRunResult.fromStrings('refs/heads/main\n'),
        )
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(fetchCommand, GitRunResult.fromStrings(''))
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', 'FETCH_HEAD'],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..replyTo(
          const <String>['ls-remote', '--tags', '--', 'origin'],
          GitRunResult.fromStrings(''),
        )
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', trackingRef],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..replyTo(mergeCommand, GitRunResult.fromStrings(''))
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
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);
      final GitWorkingRepository repository =
          syntheticWorkingRepository(runner, platform: plainPlatform);

      final GitMergeResult result = await engine.pull(repository);

      expect(result, isA<GitMergeUpToDate>());
      expect(requestRunning(runner, 'fetch').arguments, fetchCommand);
      expect(requestRunning(runner, 'merge').arguments, mergeCommand);
    });

    test('an explicit remote and branch fetch that branch', () async {
      const String trackingRef = 'refs/remotes/upstream/topic';
      final List<String> fetchCommand = <String>[
        'fetch',
        '--no-tags',
        '--',
        'upstream',
        'topic',
      ];
      final List<String> mergeCommand = <String>[
        'merge',
        '--no-edit',
        '--',
        trackingRef,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(fetchCommand, GitRunResult.fromStrings(''))
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', 'FETCH_HEAD'],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..replyTo(
          const <String>['ls-remote', '--tags', '--', 'upstream'],
          GitRunResult.fromStrings(''),
        )
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', trackingRef],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..replyTo(mergeCommand, GitRunResult.fromStrings(''))
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
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);
      final GitWorkingRepository repository =
          syntheticWorkingRepository(runner, platform: plainPlatform);

      await engine.pull(repository, remote: 'upstream', branch: 'topic');

      expect(requestRunning(runner, 'fetch').arguments, fetchCommand);
      expect(requestRunning(runner, 'merge').arguments, mergeCommand);
    });

    test('a remote without a tracking ref merges the fetched commit', () async {
      final List<String> fetchCommand = <String>[
        'fetch',
        '--no-tags',
        '--',
        'https://example.com/repo.git',
        'main',
      ];
      final List<String> mergeCommand = <String>[
        'merge',
        '--no-edit',
        '--',
        syntheticCommitOid,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(fetchCommand, GitRunResult.fromStrings(''))
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', 'FETCH_HEAD'],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..replyTo(
          const <String>[
            'ls-remote',
            '--tags',
            '--',
            'https://example.com/repo.git',
          ],
          GitRunResult.fromStrings(''),
        )
        ..failWith(
          const <String>[
            'rev-parse',
            '--verify',
            '--quiet',
            'refs/remotes/https://example.com/repo.git/main',
          ],
          GitCommandException(
            arguments: const <String>[
              'rev-parse',
              '--verify',
              '--quiet',
              'refs/remotes/https://example.com/repo.git/main',
            ],
            exitCode: 1,
          ),
        )
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..replyTo(mergeCommand, GitRunResult.fromStrings(''))
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
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);
      final GitWorkingRepository repository =
          syntheticWorkingRepository(runner, platform: plainPlatform);

      await engine.pull(
        repository,
        remote: 'https://example.com/repo.git',
        branch: 'main',
      );

      expect(requestRunning(runner, 'merge').arguments, mergeCommand);
    });

    test('a remote helper is refused before git runs', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);
      final GitWorkingRepository repository =
          syntheticWorkingRepository(runner, platform: plainPlatform);

      await expectLater(
        engine.pull(
          repository,
          remote: 'ext::git upload-pack /repo',
          branch: 'main',
        ),
        throwsA(isA<GitUnsupportedUrlException>()),
      );
      expect(runner.requests, isEmpty);
    });

    test('the fetch of a pull carries the bounding transport environment',
        () async {
      final List<String> fetchCommand = <String>[
        'fetch',
        '--no-tags',
        '--',
        'origin',
        'main',
      ];
      final List<String> mergeCommand = <String>[
        'merge',
        '--no-edit',
        '--',
        'refs/remotes/origin/main',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['symbolic-ref', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('refs/heads/main\n'),
        )
        ..replyTo(
          const <String>[
            'config',
            '--local',
            '--get',
            '--',
            'branch.main.remote',
          ],
          GitRunResult.fromStrings('origin\n'),
        )
        ..replyTo(
          const <String>[
            'config',
            '--local',
            '--get',
            '--',
            'branch.main.merge',
          ],
          GitRunResult.fromStrings('refs/heads/main\n'),
        )
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(fetchCommand, GitRunResult.fromStrings(''))
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', 'FETCH_HEAD'],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..replyTo(
          const <String>['ls-remote', '--tags', '--', 'origin'],
          GitRunResult.fromStrings(''),
        )
        ..replyTo(
          const <String>[
            'rev-parse',
            '--verify',
            '--quiet',
            'refs/remotes/origin/main',
          ],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..replyTo(mergeCommand, GitRunResult.fromStrings(''))
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
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);
      // A wider value the repository context carries does not widen the
      // bounding environment of the exchange.
      final GitWorkingRepository repository =
          syntheticWorkingRepository(runner, platform: plainPlatform)
              .withEnvironment(
        const <String, String>{'GIT_ALLOW_PROTOCOL': 'ext:file'},
      );

      await engine.pull(repository);

      expect(
        requestRunning(runner, 'fetch').environment['GIT_ALLOW_PROTOCOL'],
        'file:http:https:ssh',
      );
      expect(
        requestRunning(runner, 'ls-remote').environment['GIT_ALLOW_PROTOCOL'],
        'file:http:https:ssh',
      );
    });
  });

  group('pull without a branch to follow', () {
    test('a detached HEAD is refused without running git', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(
          const <String>['symbolic-ref', '--quiet', 'HEAD'],
          GitCommandException(
            arguments: const <String>[
              'symbolic-ref',
              '--quiet',
              'HEAD',
            ],
            exitCode: 1,
          ),
        );
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);
      final GitWorkingRepository repository =
          syntheticWorkingRepository(runner, platform: plainPlatform);

      await expectLater(
        engine.pull(repository),
        throwsA(isA<GitNoUpstreamException>()),
      );
      expect(runner.requests, hasLength(1));
    });

    test('a branch without an upstream is refused without fetching', () async {
      final GitCommandException missingRemote =
          unsetConfigKey('branch.main.remote');
      final GitCommandException missingMerge =
          unsetConfigKey('branch.main.merge');
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['symbolic-ref', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('refs/heads/main\n'),
        )
        ..failWith(missingRemote.arguments, missingRemote)
        ..failWith(missingMerge.arguments, missingMerge);
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);
      final GitWorkingRepository repository =
          syntheticWorkingRepository(runner, platform: plainPlatform);

      await expectLater(
        engine.pull(repository),
        throwsA(isA<GitNoUpstreamException>()),
      );
      expect(
        runner.requests.where(
          (GitRunRequest request) => request.arguments.contains('fetch'),
        ),
        isEmpty,
      );
    });

    test('a branch without a remote is refused', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);
      final GitWorkingRepository repository =
          syntheticWorkingRepository(runner, platform: plainPlatform);

      await expectLater(
        engine.pull(repository, branch: 'main'),
        throwsArgumentError,
      );
      expect(runner.requests, isEmpty);
    });
  });
}
