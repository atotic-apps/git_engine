@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/fake_git_process_launcher.dart';
import 'support/scripted_git_runner.dart';

/// Configuration of the process engine, observed on the runner its commands
/// go through, before any process is started.
void main() {
  group('ProcessGitEngine configuration', () {
    test('defaults match the process runner defaults', () {
      final ProcessGitRunner runner = ProcessGitRunner();
      ProcessGitEngine(runner: runner);

      expect(runner.executable, 'git');
      expect(runner.globalEnvironment, isEmpty);
      expect(runner.windowsLongPaths, isTrue);
      expect(runner.defaultTimeout, const Duration(minutes: 5));
      expect(runner.defaultMaxOutputBytes, isNull);
    });

    test('the default output limit reaches the commands of the engine',
        () async {
      final ProcessGitEngine engine = ProcessGitEngine(
        defaultMaxOutputBytes: 1,
      );

      await expectLater(
        engine.gitVersion(),
        throwsA(
          isA<GitOutputLimitException>().having(
            (GitOutputLimitException error) => error.limit,
            'limit',
            1,
          ),
        ),
      );
    });

    test('the configured executable is the one commands launch', () {
      final ProcessGitRunner runner = ProcessGitRunner(
        executable: 'custom-git',
      );
      ProcessGitEngine(runner: runner);

      expect(runner.executable, 'custom-git');
    });

    test('the global environment reaches every command', () {
      const Map<String, String> global = <String, String>{
        'ENGINE_GLOBAL': 'global',
      };
      final ProcessGitRunner runner = ProcessGitRunner(
        globalEnvironment: global,
      );
      ProcessGitEngine(runner: runner);

      final Map<String, String> environment = runner.environmentFor(
        const GitRunRequest(arguments: <String>['status']),
      );

      expect(environment['ENGINE_GLOBAL'], 'global');
    });

    test('the default timeout applies to a command that names none', () {
      const Duration timeout = Duration(seconds: 7);
      final ProcessGitRunner runner = ProcessGitRunner(defaultTimeout: timeout);
      ProcessGitEngine(runner: runner);

      expect(runner.defaultTimeout, timeout);
    });

    test('the long-path setting reaches the Windows command line', () {
      final ProcessGitRunner disabled = ProcessGitRunner(
        platform: GitPlatform.windows,
        windowsLongPaths: false,
      );
      ProcessGitEngine(runner: disabled);
      expect(
        disabled.argumentsFor(
          const GitRunRequest(arguments: <String>['status']),
        ),
        const <String>['-c', 'core.quotepath=false', 'status'],
      );

      final ProcessGitRunner enabled = ProcessGitRunner(
        platform: GitPlatform.windows,
      );
      ProcessGitEngine(runner: enabled);
      expect(
        enabled.argumentsFor(
          const GitRunRequest(arguments: <String>['status']),
        ),
        const <String>[
          '-c',
          'core.quotepath=false',
          '-c',
          'core.longpaths=true',
          'status',
        ],
      );
    });
  });

  group('ProcessGitEngine configuration with a runner', () {
    late ScriptedGitRunner scripted;

    setUp(() {
      scripted = ScriptedGitRunner();
    });

    test('a provided runner is used as is', () async {
      scripted.replyTo(
        const <String>['--version'],
        GitRunResult.fromStrings('git version 2.41.0\n'),
      );
      final ProcessGitEngine engine = ProcessGitEngine(runner: scripted);

      expect(await engine.gitVersion(), 'git version 2.41.0');
      expect(scripted.requests.single.arguments, const <String>['--version']);
    });

    test('every option given with a runner is refused by name', () {
      expect(
        () => ProcessGitEngine(runner: scripted, executable: 'other-git'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.name,
            'name',
            'executable',
          ),
        ),
      );
      expect(
        () => ProcessGitEngine(
          runner: scripted,
          globalEnvironment: const <String, String>{'ENGINE_GLOBAL': 'global'},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.name,
            'name',
            'globalEnvironment',
          ),
        ),
      );
      expect(
        () => ProcessGitEngine(runner: scripted, windowsLongPaths: false),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.name,
            'name',
            'windowsLongPaths',
          ),
        ),
      );
      expect(
        () => ProcessGitEngine(
          runner: scripted,
          defaultTimeout: const Duration(seconds: 1),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.name,
            'name',
            'defaultTimeout',
          ),
        ),
      );
      expect(
        () => ProcessGitEngine(runner: scripted, defaultMaxOutputBytes: 1024),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.name,
            'name',
            'defaultMaxOutputBytes',
          ),
        ),
      );
    });
  });

  group('ProcessGitUploadPackService configuration', () {
    ProcessGitUploadPackService buildService(
      FakeGitProcessLauncher launcher, {
      String executable = 'git',
      Map<String, String>? globalEnvironment,
    }) {
      return ProcessGitUploadPackService(
        resolveRepository: (_) => null,
        launcher: launcher,
        executable: executable,
        globalEnvironment: globalEnvironment,
        inactivityTimeout: const Duration(seconds: 1),
        bufferBytes: 16,
      );
    }

    test('a launcher alone still builds the service', () {
      expect(buildService(FakeGitProcessLauncher()), isNotNull);
    });

    test('its options given with a launcher are refused by name', () {
      final FakeGitProcessLauncher launcher = FakeGitProcessLauncher();

      expect(
        () => buildService(launcher, executable: 'other-git'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.name,
            'name',
            'executable',
          ),
        ),
      );
      expect(
        () => buildService(
          launcher,
          globalEnvironment: const <String, String>{'ENGINE_GLOBAL': 'global'},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.name,
            'name',
            'globalEnvironment',
          ),
        ),
      );
    });
  });
}
