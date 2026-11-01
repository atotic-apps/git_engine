import 'package:git_engine/src/backends/process/process_git_runner.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

/// Raw argv and environment shaping the process runner applies to a request,
/// before anything runs.
///
/// The constructor below starts no process: only the runner's `run` reaches
/// the installed git, and no test here calls it.
void main() {
  group('hardening', () {
    test('merges hardened defaults, global and per-request environment', () {
      final ProcessGitRunner runner = ProcessGitRunner.new(
        globalEnvironment: const <String, String>{'ENGINE_GLOBAL': 'g'},
      );
      final Map<String, String> environment = runner.environmentFor(
        const GitRunRequest(
          arguments: <String>['status'],
          environment: <String, String>{'ENGINE_REQUEST': 'r'},
        ),
      );

      expect(environment['GIT_TERMINAL_PROMPT'], '0');
      expect(environment['GCM_INTERACTIVE'], 'never');
      expect(environment['LC_ALL'], 'C');
      expect(environment['ENGINE_GLOBAL'], 'g');
      expect(environment['ENGINE_REQUEST'], 'r');
    });

    test('per-request environment overrides the global one', () {
      final ProcessGitRunner runner = ProcessGitRunner.new(
        globalEnvironment: const <String, String>{'ENGINE_VAR': 'global'},
      );
      final Map<String, String> environment = runner.environmentFor(
        const GitRunRequest(
          arguments: <String>['status'],
          environment: <String, String>{'ENGINE_VAR': 'request'},
        ),
      );

      expect(environment['ENGINE_VAR'], 'request');
    });

    test('arguments start with core.quotepath and end with the subcommand', () {
      final ProcessGitRunner runner = ProcessGitRunner.new(
        platform: GitPlatform.linux,
        windowsLongPaths: false,
      );
      final List<String> arguments = runner.argumentsFor(
        const GitRunRequest(arguments: <String>['status']),
      );

      expect(
        arguments,
        const <String>['-c', 'core.quotepath=false', 'status'],
      );
    });

    test('adds core.longpaths for a Windows platform', () {
      final ProcessGitRunner runner = ProcessGitRunner.new(
        platform: GitPlatform.windows,
      );
      final List<String> arguments = runner.argumentsFor(
        const GitRunRequest(arguments: <String>['status']),
      );

      expect(
        arguments,
        const <String>[
          '-c',
          'core.quotepath=false',
          '-c',
          'core.longpaths=true',
          'status',
        ],
      );
    });

    test('adds no long-path option for POSIX platforms', () {
      for (final GitPlatform platform in <GitPlatform>[
        GitPlatform.linux,
        GitPlatform.macos,
      ]) {
        final ProcessGitRunner runner = ProcessGitRunner.new(
          platform: platform,
        );
        final List<String> arguments = runner.argumentsFor(
          const GitRunRequest(arguments: <String>['status']),
        );

        expect(
          arguments,
          const <String>['-c', 'core.quotepath=false', 'status'],
          reason: '${platform.operatingSystem} uses POSIX path rules',
        );
      }
    });

    test('the long-path option can be disabled on Windows', () {
      final ProcessGitRunner runner = ProcessGitRunner.new(
        platform: GitPlatform.windows,
        windowsLongPaths: false,
      );
      final List<String> arguments = runner.argumentsFor(
        const GitRunRequest(arguments: <String>['status']),
      );

      expect(
        arguments,
        const <String>['-c', 'core.quotepath=false', 'status'],
      );
    });

    test('a non-positive default output limit is refused by name', () {
      for (final int limit in <int>[0, -1]) {
        expect(
          () => ProcessGitRunner.new(defaultMaxOutputBytes: limit),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.name,
              'name',
              'defaultMaxOutputBytes',
            ),
          ),
        );
      }
    });

    test('a non-positive request output limit is refused by name', () async {
      final ProcessGitRunner runner = ProcessGitRunner.new();

      await expectLater(
        runner.run(
          const GitRunRequest(
            arguments: <String>['status'],
            maxOutputBytes: 0,
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.name,
            'name',
            'maxOutputBytes',
          ),
        ),
      );
    });
  });
}
