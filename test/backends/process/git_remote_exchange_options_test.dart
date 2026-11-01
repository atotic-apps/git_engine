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

/// The scripted failure of a revision that resolves to nothing.
GitCommandException noSuchRevision(String expression) => GitCommandException(
      arguments: <String>['rev-parse', '--verify', '--quiet', expression],
      exitCode: 1,
    );

/// The request of [runner] running [subcommand], whatever else ran around it.
GitRunRequest requestRunning(ScriptedGitRunner runner, String subcommand) {
  return runner.requests.singleWhere(
    (GitRunRequest request) => request.arguments.contains(subcommand),
  );
}

/// The exchange commands [runner] received in order, without the SSH command
/// probe the connection environment asks before each of them.
List<List<String>> exchangeCommands(ScriptedGitRunner runner) {
  bool isProbe(GitRunRequest request) {
    if (request.arguments.length != sshCommandProbe.length) {
      return false;
    }
    for (var index = 0; index < sshCommandProbe.length; index++) {
      if (request.arguments[index] != sshCommandProbe[index]) {
        return false;
      }
    }
    return true;
  }

  return runner.requests
      .where((GitRunRequest request) => !isProbe(request))
      .map((GitRunRequest request) => request.arguments)
      .toList();
}

void main() {
  group('fetch tag arguments', () {
    const List<(GitTagFetch, List<String>)> cases =
        <(GitTagFetch, List<String>)>[
      (GitTagFetch.follow, <String>[]),
      (GitTagFetch.all, <String>['--tags']),
      (GitTagFetch.none, <String>['--no-tags']),
    ];

    for (final (GitTagFetch tags, List<String> extra) in cases) {
      test('${tags.name} emits ${extra.isEmpty ? 'no tag flag' : extra.single}',
          () async {
        final List<String> command = <String>[
          'fetch',
          ...extra,
          '--',
          'origin',
        ];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(sshCommandProbe, unsetSshCommand())
          ..replyTo(command, GitRunResult.fromStrings(''));
        final ProcessGitEngine engine =
            syntheticEngine(runner, platform: plainPlatform);

        await engine.fetch(
          syntheticWorkingRepository(runner, platform: plainPlatform),
          remote: 'origin',
          tags: tags,
        );

        expect(requestRunning(runner, 'fetch').arguments, command);
      });
    }
  });

  group('push tag and upstream arguments', () {
    test('tags emits the flag before the remote', () async {
      final List<String> command = <String>[
        'push',
        '--tags',
        '--',
        'origin',
        'main',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(command, GitRunResult.fromStrings(''));
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);

      await engine.push(
        syntheticWorkingRepository(runner, platform: plainPlatform),
        remote: 'origin',
        refspecs: const <String>['main'],
        tags: true,
      );

      expect(requestRunning(runner, 'push').arguments, command);
    });

    test('setUpstream with a branch refspec emits the flag', () async {
      final List<String> command = <String>[
        'push',
        '--set-upstream',
        '--',
        'origin',
        'main',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', 'refs/heads/main'],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(command, GitRunResult.fromStrings(''));
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);

      await engine.push(
        syntheticWorkingRepository(runner, platform: plainPlatform),
        remote: 'origin',
        refspecs: const <String>['main'],
        setUpstream: true,
      );

      expect(requestRunning(runner, 'push').arguments, command);
    });

    test('tags and setUpstream combine in one command', () async {
      final List<String> command = <String>[
        'push',
        '--tags',
        '--set-upstream',
        '--',
        'origin',
        'main',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', 'refs/heads/main'],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        )
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(command, GitRunResult.fromStrings(''));
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);

      await engine.push(
        syntheticWorkingRepository(runner, platform: plainPlatform),
        remote: 'origin',
        refspecs: const <String>['main'],
        tags: true,
        setUpstream: true,
      );

      expect(requestRunning(runner, 'push').arguments, command);
    });

    test('setUpstream without refspecs pushes the checked out branch by name',
        () async {
      final List<String> command = <String>[
        'push',
        '--set-upstream',
        '--',
        'origin',
        'main',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['symbolic-ref', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('refs/heads/main\n'),
        )
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(command, GitRunResult.fromStrings(''));
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);

      await engine.push(
        syntheticWorkingRepository(runner, platform: plainPlatform),
        remote: 'origin',
        setUpstream: true,
      );

      expect(requestRunning(runner, 'push').arguments, command);
    });
  });

  group('fetch follow with explicit refspecs', () {
    const List<String> fetchCommand = <String>[
      'fetch',
      '--no-tags',
      '--',
      'origin',
      'refs/heads/main',
    ];
    const List<String> lsRemoteCommand = <String>[
      'ls-remote',
      '--tags',
      '--',
      'origin',
    ];
    const List<String> batchCheckCommand = <String>[
      'cat-file',
      '--batch-check'
    ];

    test('the tags of the retrieved commits are fetched by name afterwards',
        () async {
      const String annotatedOid = syntheticTagOid;
      const String annotatedTarget = syntheticFirstParentOid;
      const String lightTarget = syntheticSecondParentOid;
      const String absentTarget = syntheticBlobOid;
      final List<String> tagFetchCommand = <String>[
        'fetch',
        '--no-tags',
        '--',
        'origin',
        'refs/tags/annotated:refs/tags/annotated',
        'refs/tags/light:refs/tags/light',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(fetchCommand, GitRunResult.fromStrings(''))
        ..replyTo(
          lsRemoteCommand,
          GitRunResult.fromStrings(
            '$annotatedOid\trefs/tags/annotated\n'
            '$annotatedTarget\trefs/tags/annotated^{}\n'
            '$lightTarget\trefs/tags/light\n'
            '$absentTarget\trefs/tags/away\n',
          ),
        )
        ..replyTo(
          batchCheckCommand,
          GitRunResult.fromStrings(
            '$annotatedTarget commit 167\n'
            '$lightTarget commit 167\n'
            '$absentTarget missing\n',
          ),
        )
        ..replyTo(tagFetchCommand, GitRunResult.fromStrings(''));
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);

      await engine.fetch(
        syntheticWorkingRepository(runner, platform: plainPlatform),
        remote: 'origin',
        refspecs: const <String>['refs/heads/main'],
      );

      expect(requestRunning(runner, 'ls-remote').arguments, lsRemoteCommand);
      final GitRunRequest check = runner.requests.singleWhere(
        (GitRunRequest request) => request.arguments.contains('cat-file'),
      );
      expect(
        String.fromCharCodes(check.stdin!),
        '$annotatedTarget\n$lightTarget\n$absentTarget\n',
      );
      final List<GitRunRequest> fetches = runner.requests
          .where((GitRunRequest request) => request.arguments.contains('fetch'))
          .toList();
      expect(fetches, hasLength(2));
      expect(fetches.first.arguments, fetchCommand);
      expect(fetches.last.arguments, tagFetchCommand);
    });

    test('a remote without tags runs no object check', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(fetchCommand, GitRunResult.fromStrings(''))
        ..replyTo(lsRemoteCommand, GitRunResult.fromStrings(''));
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);

      await engine.fetch(
        syntheticWorkingRepository(runner, platform: plainPlatform),
        remote: 'origin',
        refspecs: const <String>['refs/heads/main'],
      );

      expect(
        exchangeCommands(runner),
        <List<String>>[fetchCommand, lsRemoteCommand],
      );
    });

    test('no tag designating a retrieved commit runs no second fetch',
        () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(fetchCommand, GitRunResult.fromStrings(''))
        ..replyTo(
          lsRemoteCommand,
          GitRunResult.fromStrings(
            '${syntheticBlobOid}\trefs/tags/away\n',
          ),
        )
        ..replyTo(
          batchCheckCommand,
          GitRunResult.fromStrings('${syntheticBlobOid} missing\n'),
        );
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);

      await engine.fetch(
        syntheticWorkingRepository(runner, platform: plainPlatform),
        remote: 'origin',
        refspecs: const <String>['refs/heads/main'],
      );

      expect(
        exchangeCommands(runner),
        <List<String>>[fetchCommand, lsRemoteCommand, batchCheckCommand],
      );
    });

    test('all and none keep a single fetch with refspecs', () async {
      for (final (GitTagFetch tags, List<String> flag)
          in const <(GitTagFetch, List<String>)>[
        (GitTagFetch.all, <String>['--tags']),
        (GitTagFetch.none, <String>['--no-tags']),
      ]) {
        final List<String> command = <String>[
          'fetch',
          ...flag,
          '--',
          'origin',
          'refs/heads/main',
        ];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..failWith(sshCommandProbe, unsetSshCommand())
          ..replyTo(command, GitRunResult.fromStrings(''));
        final ProcessGitEngine engine =
            syntheticEngine(runner, platform: plainPlatform);

        await engine.fetch(
          syntheticWorkingRepository(runner, platform: plainPlatform),
          remote: 'origin',
          refspecs: const <String>['refs/heads/main'],
          tags: tags,
        );

        expect(requestRunning(runner, 'fetch').arguments, command);
        expect(exchangeCommands(runner), <List<String>>[command]);
      }
    });
  });

  group('setUpstream refusals', () {
    test('several refspecs are refused before git runs', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);

      await expectLater(
        engine.push(
          syntheticWorkingRepository(runner, platform: plainPlatform),
          remote: 'origin',
          refspecs: const <String>['main', 'topic'],
          setUpstream: true,
        ),
        throwsArgumentError,
      );
      expect(runner.requests, isEmpty);
    });

    test('a refspec naming no local branch is refused', () async {
      final GitCommandException absent =
          noSuchRevision('refs/heads/refs/tags/v1');
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(absent.arguments, absent);
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);

      await expectLater(
        engine.push(
          syntheticWorkingRepository(runner, platform: plainPlatform),
          remote: 'origin',
          refspecs: const <String>['refs/tags/v1'],
          setUpstream: true,
        ),
        throwsArgumentError,
      );
      expect(
        runner.requests.where(
          (GitRunRequest request) => request.arguments.contains('push'),
        ),
        isEmpty,
      );
    });

    test('a detached HEAD without refspecs is refused', () async {
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

      await expectLater(
        engine.push(
          syntheticWorkingRepository(runner, platform: plainPlatform),
          remote: 'origin',
          setUpstream: true,
        ),
        throwsArgumentError,
      );
      expect(
        runner.requests.where(
          (GitRunRequest request) => request.arguments.contains('push'),
        ),
        isEmpty,
      );
    });
  });

  group('refused tag classification', () {
    test('a tag the remote holds with another value is a push rejection',
        () async {
      final List<String> command = <String>[
        'push',
        '--tags',
        '--',
        'origin',
        'main',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 1,
            stderr: ' ! [rejected]        v1 -> v1 (already exists)\r\n'
                'error: failed to push some refs to the remote\n'
                'hint: Updates were rejected because the tag already exists '
                'in the remote.\n',
          ),
        );
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: plainPlatform);

      await expectLater(
        engine.push(
          syntheticWorkingRepository(runner, platform: plainPlatform),
          remote: 'origin',
          refspecs: const <String>['main'],
          tags: true,
        ),
        throwsA(isA<GitPushRejectedException>()),
      );
    });
  });
}
