import 'package:git_engine/git_engine.dart';
import 'package:git_engine/src/backends/process/git_version.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/scripted_git_runner.dart';
import 'support/synthetic_git_support.dart';

const List<String> _versionCommand = <String>['--version'];

void main() {
  group('git version parsing', () {
    test('extracts the version from git output variants', () {
      expect(
        parseGitVersion('git version 2.42.0 (synthetic build 7)'),
        (2, 42, 0),
      );
      expect(
        parseGitVersion('git version 2.39.1'),
        (2, 39, 1),
      );
      expect(parseGitVersion('git version 2.38'), (2, 38, 0));
      expect(parseGitVersion('git version 3'), (3, 0, 0));
      expect(parseGitVersion('git version 2.41.0.windows.1'), (2, 41, 0));
    });

    test('returns null when no version is present', () {
      expect(parseGitVersion('not a git version'), isNull);
      expect(parseGitVersion(''), isNull);
    });

    test('parses a version constraint and pads missing parts', () {
      expect(parseVersionConstraint('2.38'), (2, 38, 0));
      expect(parseVersionConstraint('2'), (2, 0, 0));
      expect(parseVersionConstraint('2.38.1'), (2, 38, 1));
      expect(parseVersionConstraint('2.38.1.4'), isNull);
      expect(parseVersionConstraint('2.x'), isNull);
      expect(parseVersionConstraint('-1'), isNull);
    });

    test('orders versions by major, minor and patch', () {
      expect(compareGitVersions((2, 38, 0), (2, 38, 0)), 0);
      expect(compareGitVersions((2, 37, 9), (2, 38, 0)), isNegative);
      expect(compareGitVersions((3, 0, 0), (2, 99, 99)), isPositive);
      expect(compareGitVersions((2, 38, 1), (2, 38, 0)), isPositive);
    });
  });

  group('installed git version', () {
    test('reports the trimmed git --version output', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _versionCommand,
          GitRunResult.fromStrings('git version 2.42.0 (synthetic build 7)\n'),
        );
      final ProcessGitEngine engine = syntheticEngine(runner);

      expect(
          await engine.gitVersion(), 'git version 2.42.0 (synthetic build 7)');
      expect(runner.requests.single.arguments, _versionCommand);
    });

    test('accepts a git that meets the minimum version', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _versionCommand,
          GitRunResult.fromStrings('git version 2.42.0 (synthetic build 7)\n'),
        );
      final ProcessGitEngine engine = syntheticEngine(runner);

      await engine.ensureGitVersion('2.38');
      await engine.ensureGitVersion('2.42');
    });

    test('refuses a git older than the minimum version', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _versionCommand,
          GitRunResult.fromStrings('git version 2.37.2\n'),
        );
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.ensureGitVersion('2.38'),
        throwsA(
          isA<GitVersionException>()
              .having(
                (GitVersionException error) => error.requiredVersion,
                'requiredVersion',
                '2.38',
              )
              .having(
                (GitVersionException error) => error.actualVersion,
                'actualVersion',
                'git version 2.37.2',
              ),
        ),
      );
    });

    test('refuses an unparsable git --version output', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _versionCommand,
          GitRunResult.fromStrings('unexpected output\n'),
        );
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.ensureGitVersion('2.38'),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('Cannot parse git version'),
          ),
        ),
      );
    });

    test('refuses a malformed minimum version', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _versionCommand,
          GitRunResult.fromStrings('git version 2.42.0\n'),
        );
      final ProcessGitEngine engine = syntheticEngine(runner);

      await expectLater(
        engine.ensureGitVersion('not-a-version'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
