import 'package:git_engine/backend.dart';
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

/// An engine on [runner] under [plainPlatform], so no test reads the machine.
ProcessGitEngine testEngine(ScriptedGitRunner runner) {
  return syntheticEngine(runner, platform: plainPlatform);
}

/// A working repository on [runner] under [plainPlatform].
ProcessGitWorkingRepository testRepository(ScriptedGitRunner runner) {
  return syntheticWorkingRepository(runner, platform: plainPlatform);
}

/// Environment bounding every clone, fetch and push to the accepted
/// transports, whatever the caller supplies.
const Map<String, String> transportEnvironment = <String, String>{
  'GIT_ALLOW_PROTOCOL': 'file:http:https:ssh',
};

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

/// Environment of an SSH-capable command when the user chose no SSH command.
const Map<String, String> defaultNonInteractiveSsh = <String, String>{
  'GIT_SSH_COMMAND': 'ssh -oBatchMode=yes',
  'SSH_ASKPASS_REQUIRE': 'never',
};

/// Environment of an SSH-capable command when the user chose one.
const Map<String, String> sshAskpassNever = <String, String>{
  'SSH_ASKPASS_REQUIRE': 'never',
};

/// The command opening a repository after a clone creates it.
const List<String> openKindCommand = <String>[
  'rev-parse',
  '--is-bare-repository',
];

/// The request of [runner] running [subcommand], whatever else ran around it.
GitRunRequest requestRunning(ScriptedGitRunner runner, String subcommand) {
  return runner.requests
      .singleWhere((GitRunRequest request) => request.arguments.contains(
            subcommand,
          ));
}

/// Whether the SSH command probe ran against [runner].
bool probeRan(ScriptedGitRunner runner) {
  final String expected = sshCommandProbe.join(' ');
  return runner.requests.any(
    (GitRunRequest request) => request.arguments.join(' ') == expected,
  );
}

void main() {
  final String target = '$syntheticRepositoryPath-clone';

  group('clone arguments for each accepted form', () {
    final Map<String, bool> forms = <String, bool>{
      // Whether the form may open an SSH connection, and therefore reads the
      // SSH command chosen by the user before running.
      '/repo': false,
      'file:///repo': false,
      'http://example.com/repo.git': false,
      'https://example.com/repo.git': false,
      'ssh://git@example.com/repo.git': true,
      'git@example.com:repo.git': true,
    };

    for (final MapEntry<String, bool> form in forms.entries) {
      test('separates ${form.key} from the options with --', () async {
        final List<String> command = <String>[
          'clone',
          '--',
          form.key,
          target,
        ];
        final ScriptedGitRunner runner = ScriptedGitRunner()
          ..replyTo(command, GitRunResult.fromStrings(''))
          ..replyTo(
            openKindCommand,
            GitRunResult.fromStrings('false\n'),
          );
        if (form.value) {
          runner.failWith(sshCommandProbe, unsetSshCommand());
        }
        final ProcessGitEngine engine = testEngine(runner);

        await engine.clone(form.key, target);

        expect(requestRunning(runner, 'clone').arguments, command);
        expect(probeRan(runner), form.value);
      });
    }

    test('carries the clone refinements before the -- separator', () async {
      final List<String> command = <String>[
        'clone',
        '--branch=feature',
        '--no-checkout',
        '--',
        '/repo',
        target,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(command, GitRunResult.fromStrings(''))
        ..replyTo(openKindCommand, GitRunResult.fromStrings('false\n'));
      final ProcessGitEngine engine = testEngine(runner);

      await engine.clone('/repo', target, branch: 'feature', noCheckout: true);

      expect(requestRunning(runner, 'clone').arguments, command);
      expect(probeRan(runner), isFalse);
    });

    test('cloneBare carries the bounding transport environment', () async {
      final List<String> command = <String>[
        'clone',
        '--bare',
        '--',
        '/repo',
        target,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(command, GitRunResult.fromStrings(''))
        ..replyTo(openKindCommand, GitRunResult.fromStrings('true\n'));
      final ProcessGitEngine engine = testEngine(runner);

      await engine.cloneBare('/repo', target);

      expect(requestRunning(runner, 'clone').arguments, command);
      expect(probeRan(runner), isFalse);
    });
  });

  group('exchange arguments', () {
    test('fetch separates a URL remote and its refspecs with --', () async {
      const String remote = 'https://example.com/repo.git';
      final List<String> command = <String>[
        'fetch',
        '--no-tags',
        '--prune',
        '--',
        remote,
        'main:refs/heads/main',
      ];
      final List<String> listing = <String>[
        'ls-remote',
        '--tags',
        '--',
        remote,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(command, GitRunResult.fromStrings(''))
        ..replyTo(listing, GitRunResult.fromStrings(''));
      final ProcessGitEngine engine = testEngine(runner);

      await engine.fetch(
        testRepository(runner),
        remote: remote,
        refspecs: const <String>['main:refs/heads/main'],
        prune: true,
      );

      expect(requestRunning(runner, 'fetch').arguments, command);
      expect(requestRunning(runner, 'ls-remote').arguments, listing);
    });

    test('push separates a URL remote and its refspecs with --', () async {
      const String remote = 'ssh://git@example.com/repo.git';
      final List<String> command = <String>[
        'push',
        '--',
        remote,
        'main:refs/heads/main',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(command, GitRunResult.fromStrings(''));
      final ProcessGitEngine engine = testEngine(runner);

      await engine.push(
        testRepository(runner),
        remote: remote,
        refspecs: const <String>['main:refs/heads/main'],
      );

      expect(requestRunning(runner, 'push').arguments, command);
    });

    test('fetch of the default remote carries the bounding environment',
        () async {
      final List<String> command = <String>[
        'fetch',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(command, GitRunResult.fromStrings(''));
      final ProcessGitEngine engine = testEngine(runner);

      await engine.fetch(testRepository(runner));

      expect(requestRunning(runner, 'fetch').arguments, command);
    });
  });

  group('refusals without launching git', () {
    const List<String> refused = <String>[
      'ext::git upload-pack /repo',
      'fd::3',
      'file::/repo',
      'git://example.com/repo.git',
      'svn::https://example.com/repo',
      'HTTPS://example.com/repo.git',
      '--upload-pack=touch /nowhere',
      '-upload-pack',
    ];

    for (final String location in refused) {
      test('clone refuses $location', () async {
        final ScriptedGitRunner runner = ScriptedGitRunner();
        final ProcessGitEngine engine = testEngine(runner);

        await expectLater(
          engine.clone(location, target),
          throwsA(isA<GitUnsupportedUrlException>().having(
            (GitUnsupportedUrlException error) => error.url,
            'url',
            location,
          )),
        );
        expect(runner.requests, isEmpty);
      });
    }

    test('cloneBare refuses a remote helper', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitEngine engine = testEngine(runner);

      await expectLater(
        engine.cloneBare('ext::git upload-pack /repo', target),
        throwsA(isA<GitUnsupportedUrlException>()),
      );
      expect(runner.requests, isEmpty);
    });

    test('fetch refuses a remote helper before running git', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitEngine engine = testEngine(runner);

      await expectLater(
        engine.fetch(
          testRepository(runner),
          remote: 'ext::git upload-pack /repo',
        ),
        throwsA(isA<GitUnsupportedUrlException>()),
      );
      expect(runner.requests, isEmpty);
    });

    test('push refuses an option-spelled remote before running git', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitEngine engine = testEngine(runner);

      await expectLater(
        engine.push(
          testRepository(runner),
          remote: '--receive-pack=touch /nowhere',
        ),
        throwsA(isA<GitUnsupportedUrlException>()),
      );
      expect(runner.requests, isEmpty);
    });
  });

  group('SSH connection environment', () {
    test('an SSH source gets a default SSH command that cannot prompt',
        () async {
      final List<String> command = <String>[
        'clone',
        '--',
        'ssh://git@example.com/repo.git',
        target,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(command, GitRunResult.fromStrings(''))
        ..replyTo(openKindCommand, GitRunResult.fromStrings('false\n'));
      final ProcessGitEngine engine = testEngine(runner);

      await engine.clone('ssh://git@example.com/repo.git', target);

      expect(
        requestRunning(runner, 'clone').environment,
        <String, String>{
          ...transportEnvironment,
          ...defaultNonInteractiveSsh,
        },
      );
    });

    test('an SSH command in the platform environment is kept unprobed',
        () async {
      final List<String> command = <String>[
        'clone',
        '--',
        'ssh://git@example.com/repo.git',
        target,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(command, GitRunResult.fromStrings(''))
        ..replyTo(openKindCommand, GitRunResult.fromStrings('false\n'));
      final GitPlatform platform = GitPlatform(
        operatingSystem: GitOperatingSystem.linux,
        environment: const <String, String>{
          'GIT_SSH_COMMAND': 'chosen-ssh -oBatchMode=yes',
        },
      );
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: platform);

      await engine.clone('ssh://git@example.com/repo.git', target);

      expect(
        requestRunning(runner, 'clone').environment,
        <String, String>{...transportEnvironment, ...sshAskpassNever},
      );
      expect(probeRan(runner), isFalse);
    });

    test('GIT_SSH in the platform environment also counts as a chosen command',
        () async {
      final List<String> command = <String>[
        'clone',
        '--',
        'git@example.com:repo.git',
        target,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(command, GitRunResult.fromStrings(''))
        ..replyTo(openKindCommand, GitRunResult.fromStrings('false\n'));
      final GitPlatform platform = GitPlatform(
        operatingSystem: GitOperatingSystem.linux,
        environment: const <String, String>{'GIT_SSH': 'legacy-ssh'},
      );
      final ProcessGitEngine engine =
          syntheticEngine(runner, platform: platform);

      await engine.clone('git@example.com:repo.git', target);

      expect(
        requestRunning(runner, 'clone').environment,
        <String, String>{...transportEnvironment, ...sshAskpassNever},
      );
      expect(probeRan(runner), isFalse);
    });

    test('a configuration-chosen SSH command is kept, never replaced',
        () async {
      final List<String> command = <String>[
        'clone',
        '--',
        'git@example.com:repo.git',
        target,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          sshCommandProbe,
          GitRunResult.fromStrings('my-ssh -oBatchMode=yes\n'),
        )
        ..replyTo(command, GitRunResult.fromStrings(''))
        ..replyTo(openKindCommand, GitRunResult.fromStrings('false\n'));
      final ProcessGitEngine engine = testEngine(runner);

      await engine.clone('git@example.com:repo.git', target);

      expect(
        requestRunning(runner, 'clone').environment,
        <String, String>{...transportEnvironment, ...sshAskpassNever},
      );
      expect(
        requestRunning(runner, 'clone').environment.containsKey(
              'GIT_SSH_COMMAND',
            ),
        isFalse,
        reason: 'the user chose the SSH command in a configuration file',
      );
    });
    test('a context-chosen SSH command is kept and skips the probe', () async {
      final List<String> command = <String>[
        'fetch',
        '--',
        'origin',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(command, GitRunResult.fromStrings(''));
      final ProcessGitEngine engine = testEngine(runner);
      final ProcessGitWorkingRepository repository =
          testRepository(runner).withEnvironment(
        <String, String>{'GIT_SSH': 'legacy-ssh'},
      );

      await engine.fetch(repository, remote: 'origin');

      expect(runner.requests, hasLength(1));
      expect(
        runner.requests.single.environment['SSH_ASKPASS_REQUIRE'],
        'never',
      );
      expect(
        runner.requests.single.environment['GIT_ALLOW_PROTOCOL'],
        transportEnvironment['GIT_ALLOW_PROTOCOL'],
      );
      expect(
        runner.requests.single.environment.containsKey('GIT_SSH_COMMAND'),
        isFalse,
        reason: 'the user chose the SSH command in the repository context',
      );
    });

    test('a source that cannot use SSH still gets the bounding environment',
        () async {
      final List<String> command = <String>[
        'clone',
        '--',
        'file:///repo',
        target,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(command, GitRunResult.fromStrings(''))
        ..replyTo(openKindCommand, GitRunResult.fromStrings('false\n'));
      final ProcessGitEngine engine = testEngine(runner);

      await engine.clone('file:///repo', target);

      expect(
        requestRunning(runner, 'clone').environment,
        transportEnvironment,
      );
    });
  });

  group('transport bounding environment', () {
    test('clone carries it', () async {
      final List<String> command = <String>['clone', '--', '/repo', target];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(command, GitRunResult.fromStrings(''))
        ..replyTo(openKindCommand, GitRunResult.fromStrings('false\n'));

      await testEngine(runner).clone('/repo', target);

      expect(
        requestRunning(runner, 'clone').environment,
        transportEnvironment,
      );
    });

    test('cloneBare carries it', () async {
      final List<String> command = <String>[
        'clone',
        '--bare',
        '--',
        '/repo',
        target,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(command, GitRunResult.fromStrings(''))
        ..replyTo(openKindCommand, GitRunResult.fromStrings('true\n'));

      await testEngine(runner).cloneBare('/repo', target);

      expect(
        requestRunning(runner, 'clone').environment,
        transportEnvironment,
      );
    });

    test('fetch carries it', () async {
      final List<String> command = <String>['fetch', '--', 'origin'];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(command, GitRunResult.fromStrings(''));

      await testEngine(runner).fetch(testRepository(runner), remote: 'origin');

      expect(
        requestRunning(runner, 'fetch').environment['GIT_ALLOW_PROTOCOL'],
        transportEnvironment['GIT_ALLOW_PROTOCOL'],
      );
    });

    test('push carries it', () async {
      final List<String> command = <String>['push', '--', 'origin'];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(command, GitRunResult.fromStrings(''));

      await testEngine(runner).push(testRepository(runner), remote: 'origin');

      expect(
        requestRunning(runner, 'push').environment['GIT_ALLOW_PROTOCOL'],
        transportEnvironment['GIT_ALLOW_PROTOCOL'],
      );
    });

    test('a wider value from the caller does not widen it', () async {
      final List<String> command = <String>['fetch', '--', 'origin'];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(sshCommandProbe, unsetSshCommand())
        ..replyTo(command, GitRunResult.fromStrings(''));
      final ProcessGitWorkingRepository repository =
          testRepository(runner).withEnvironment(
        const <String, String>{
          'GIT_ALLOW_PROTOCOL': 'ext:file:http:https:ssh',
        },
      );

      await testEngine(runner).fetch(repository, remote: 'origin');

      expect(
        requestRunning(runner, 'fetch').environment['GIT_ALLOW_PROTOCOL'],
        transportEnvironment['GIT_ALLOW_PROTOCOL'],
      );
    });
  });

  group('supportedSchemes', () {
    test('names the schemes the client accepts', () {
      final ProcessGitEngine engine = syntheticEngine(ScriptedGitRunner());

      expect(
        engine.supportedSchemes,
        <String>['file', 'http', 'https', 'ssh'],
      );
    });
  });

  group('common remote location refusal', () {
    test('accepts the forms that carry no scheme, whatever the schemes', () {
      checkRemoteLocation('/repo', schemes: const <String>[]);
      checkRemoteLocation('git@example.com:repo.git',
          schemes: const <String>[]);
      checkRemoteLocation(r'C:\repo', schemes: const <String>[]);
      checkRemoteLocation('C://repo', schemes: const <String>[]);
    });

    test('refuses through the schemes the calling engine declares', () {
      checkRemoteLocation('file:///repo', schemes: const <String>['file']);

      expect(
        () => checkRemoteLocation(
          'ssh://example.com/repo.git',
          schemes: const <String>['file', 'http'],
        ),
        throwsA(isA<GitUnsupportedUrlException>().having(
          (GitUnsupportedUrlException error) => error.message,
          'message',
          contains('"ssh" is not one of the supported schemes: file, http'),
        )),
      );
    });

    test('keeps the refusal reasons and their order', () {
      const Map<String, String> refusals = <String, String>{
        '': 'it is empty',
        '--upload-pack=touch /nowhere': 'it is spelled like an option',
        'ext::git upload-pack /repo':
            'the remote helper "ext::" is not supported',
      };

      for (final MapEntry<String, String> refusal in refusals.entries) {
        expect(
          () => checkRemoteLocation(
            refusal.key,
            schemes: const <String>['file'],
          ),
          throwsA(isA<GitUnsupportedUrlException>().having(
            (GitUnsupportedUrlException error) => error.message,
            'message',
            contains(refusal.value),
          )),
        );
      }
    });
  });
}
