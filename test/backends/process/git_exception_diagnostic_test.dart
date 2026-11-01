import 'package:git_engine/backend.dart' show maxDiagnosticChainLength;
import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'support/process_backend_types.dart';

const String _secret = 'secret';
const String _url = 'https://user:$_secret@host/x.git';

GitCommandException _commandFailure() => GitCommandException(
      arguments: const <String>['clone', _url],
      workingDirectory: '/work',
      exitCode: 128,
      stdout: 'checking $_url\n',
      stderr: 'fatal: cannot reach $_url\n',
    );

void main() {
  group('GitCommandException.diagnostic', () {
    test('carries the command, its output and never the password', () {
      final GitCommandException error = _commandFailure();

      final String diagnostic = error.diagnostic;

      expect(diagnostic, isNot(contains(_secret)));
      expect(diagnostic, contains('https://***@host/x.git'));
      expect(diagnostic, contains('command:'));
      expect(diagnostic, contains('/work'));
      expect(diagnostic, contains('exit code: 128'));
      expect(diagnostic, contains('stdout:'));
      expect(diagnostic, contains('stderr:'));
      expect(diagnostic, contains('checking https://***@host/x.git'));
      expect(
        diagnostic,
        contains('fatal: cannot reach https://***@host/x.git'),
      );
    });

    test('keeps its raw fields unchanged', () {
      final GitCommandException error = _commandFailure();

      expect(error.arguments, contains(_url));
      expect(error.stdout, contains(_url));
      expect(error.stderr, contains(_url));
      expect(error.arguments, const <String>['clone', _url]);
    });
  });

  group('domain exception diagnostics', () {
    test('include the diagnostic of a command cause without its password', () {
      final GitCommandException cause = _commandFailure();
      final GitNotARepositoryException error =
          GitNotARepositoryException(cause: cause);

      final String diagnostic = error.diagnostic;

      expect(diagnostic, contains(error.message));
      expect(diagnostic, contains(cause.diagnostic));
      expect(diagnostic, isNot(contains(_secret)));
    });

    test('render a two-level domain chain in order', () {
      final GitCommandException command = _commandFailure();
      final GitMergeNotFastForwardException middle =
          GitMergeNotFastForwardException('middle level', cause: command);
      final GitMergeNotFastForwardException outer =
          GitMergeNotFastForwardException('outer level', cause: middle);

      final String diagnostic = outer.diagnostic;

      final int outerAt = diagnostic.indexOf('outer level');
      final int middleAt = diagnostic.indexOf('middle level');
      final int commandAt = diagnostic.indexOf(command.message);
      expect(outerAt, isNonNegative);
      expect(middleAt, greaterThan(outerAt));
      expect(commandAt, greaterThan(middleAt));
      expect(diagnostic, isNot(contains(_secret)));
    });

    test('stop after the maximum chain length', () {
      GitException chain = _commandFailure();
      for (var level = 0; level < 24; level++) {
        chain = GitMergeNotFastForwardException(
          'level $level',
          cause: chain,
        );
      }

      final String diagnostic = chain.diagnostic;

      expect(
        RegExp('level ').allMatches(diagnostic).length,
        maxDiagnosticChainLength,
      );
      expect(diagnostic, isNot(contains(_secret)));
    });
  });
}
