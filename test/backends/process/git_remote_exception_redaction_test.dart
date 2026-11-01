import 'package:git_engine/src/backends/process/git_command_exception.dart';
import 'package:git_engine/src/backends/process/git_remote_failure.dart';
import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

const String _secret = 'SECRET';

GitException _rawMessage() => GitException(
      "fatal: unable to access 'https://u:$_secret@example.invalid/r/'",
    );

GitCommandException _commandFailure(String stderr) => GitCommandException(
      arguments: const <String>['fetch', 'origin'],
      exitCode: 128,
      stderr: stderr,
    );

void main() {
  group('client exceptions mask the userinfo of their cause', () {
    final Map<String, GitException Function(GitException)> builders =
        <String, GitException Function(GitException)>{
      'authentication': (GitException cause) =>
          GitAuthenticationException(cause: cause),
      'unreachable': (GitException cause) =>
          GitRemoteUnreachableException(cause: cause),
      'repository not found': (GitException cause) =>
          GitRemoteRepositoryNotFoundException(cause: cause),
      'ref not found': (GitException cause) =>
          GitRemoteRefNotFoundException(cause: cause),
      'push rejected': (GitException cause) =>
          GitPushRejectedException(cause: cause),
    };

    for (final MapEntry<String, GitException Function(GitException)> entry
        in builders.entries) {
      test(entry.key, () {
        final GitException error = entry.value(_rawMessage());

        expect(error.message, isNot(contains(_secret)));
        expect(error.toString(), isNot(contains(_secret)));
        expect(
          error.message,
          contains('https://***@example.invalid/r/'),
        );
      });
    }
  });

  group('a remote failure classified from stderr', () {
    test('authentication', () {
      final GitCommandException failure = _commandFailure(
        'fatal: Authentication failed for '
        "'https://u:$_secret@example.invalid/r/'",
      );
      final GitException? error = GitRemoteFailure.classify(failure);

      expect(error, isA<GitAuthenticationException>());
      expect(error.toString(), isNot(contains(_secret)));
      expect(failure.stderr, contains(_secret));
      expect((error! as GitAuthenticationException).cause, same(failure));
    });

    test('unreachable', () {
      final GitCommandException failure = _commandFailure(
        "fatal: unable to access 'https://u:$_secret@example.invalid/r/': "
        'Failed to connect: connection refused',
      );
      final GitException? error = GitRemoteFailure.classify(failure);

      expect(error, isA<GitRemoteUnreachableException>());
      expect(error.toString(), isNot(contains(_secret)));
    });

    test('repository not found', () {
      final GitCommandException failure = _commandFailure(
        'remote: Repository not found for '
        "'https://u:$_secret@example.invalid/r/'",
      );
      final GitException? error = GitRemoteFailure.classify(failure);

      expect(error, isA<GitRemoteRepositoryNotFoundException>());
      expect(error.toString(), isNot(contains(_secret)));
    });
  });
}
