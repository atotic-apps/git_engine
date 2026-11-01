import 'package:git_engine/src/backends/process/git_command_exception.dart';
import 'package:git_engine/src/backends/process/git_command_timeout_exception.dart';
import 'package:git_engine/src/backends/process/git_remote_location.dart';
import 'package:git_engine/backend.dart'
    show redactGitArguments, redactUrlUserinfo;
import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

const String _secret = 'SECRET';

void main() {
  group('redactUrlUserinfo', () {
    test('replaces a password', () {
      expect(
        redactUrlUserinfo('https://audit:$_secret@example.invalid/repo'),
        'https://***@example.invalid/repo',
      );
    });

    test('replaces a token-only userinfo', () {
      expect(
        redactUrlUserinfo('https://$_secret@example.invalid/repo'),
        'https://***@example.invalid/repo',
      );
    });

    test('replaces percent-encoded userinfo as written', () {
      expect(
        redactUrlUserinfo('https://u%40x:p%3Ay@example.invalid/repo'),
        'https://***@example.invalid/repo',
      );
    });

    test('keeps the host, the port and the path', () {
      expect(
        redactUrlUserinfo('http://u:$_secret@example.invalid:8080/a/b?x=1'),
        'http://***@example.invalid:8080/a/b?x=1',
      );
    });

    test('replaces a URL embedded in a larger argument', () {
      expect(
        redactUrlUserinfo(
          'remote.origin.url=https://u:$_secret@example.invalid/repo',
        ),
        'remote.origin.url=https://***@example.invalid/repo',
      );
    });

    test('replaces every URL of one text', () {
      expect(
        redactUrlUserinfo(
          'from https://u:$_secret@one.invalid/a and '
          'ssh://u:$_secret@two.invalid/b',
        ),
        'from https://***@one.invalid/a and ssh://***@two.invalid/b',
      );
    });

    test('replaces the userinfo of an ssh URL', () {
      expect(
        redactUrlUserinfo('ssh://u:$_secret@example.invalid/repo'),
        'ssh://***@example.invalid/repo',
      );
    });

    test('leaves the scp-like spelling unchanged', () {
      const String scp = 'git@example.invalid:org/repo.git';
      expect(redactUrlUserinfo(scp), scp);
    });

    test('leaves text without a URL unchanged', () {
      const String text = 'fatal: repository not found';
      expect(redactUrlUserinfo(text), text);
    });
  });

  group('redactGitArguments', () {
    test('masks a two-argument extraHeader value with its spaces', () {
      expect(
        redactGitArguments(<String>[
          '-c',
          'http.extraHeader=Authorization: Bearer $_secret',
          'fetch',
        ]),
        '-c http.extraHeader=*** fetch',
      );
    });

    test('masks an attached extraHeader value', () {
      expect(
        redactGitArguments(<String>[
          '-chttp.extraHeader=Authorization: Bearer $_secret',
          'fetch',
        ]),
        '-chttp.extraHeader=*** fetch',
      );
    });

    test('masks the key regardless of its case', () {
      expect(
        redactGitArguments(<String>[
          '-c',
          'HTTP.ExtraHeader=Authorization: Bearer $_secret',
        ]),
        '-c HTTP.ExtraHeader=***',
      );
    });

    test('masks a per-URL extraHeader key', () {
      expect(
        redactGitArguments(<String>[
          '-c',
          'http.https://example.invalid/.extraHeader=Authorization: Bearer $_secret',
        ]),
        '-c http.https://example.invalid/.extraHeader=***',
      );
    });

    test('leaves an unrelated config argument unchanged', () {
      expect(
        redactGitArguments(<String>[
          '-c',
          'user.name=Example',
          '--depth',
          '1',
        ]),
        '-c user.name=Example --depth 1',
      );
    });

    test('masks URL userinfo in the arguments too', () {
      final String text = redactGitArguments(<String>[
        '-c',
        'http.extraHeader=Authorization: Bearer $_secret',
        'clone',
        'https://audit:$_secret@example.invalid/repo',
      ]);

      expect(text, isNot(contains(_secret)));
      expect(text, contains('http.extraHeader=***'));
      expect(text, contains('https://***@example.invalid/repo'));
    });

    test('leaves a --config-env setting unchanged', () {
      expect(
        redactGitArguments(<String>[
          '--config-env',
          'http.extraHeader=EXTRA_HEADER',
        ]),
        '--config-env http.extraHeader=EXTRA_HEADER',
      );
    });
  });

  group('GitCommandException', () {
    test('masks the userinfo of an argument', () {
      final GitCommandException error = GitCommandException(
        arguments: <String>[
          'clone',
          '--',
          'https://audit:$_secret@example.invalid/repo',
          'target',
        ],
        exitCode: 128,
      );

      expect(error.message, isNot(contains(_secret)));
      expect(error.toString(), isNot(contains(_secret)));
      expect(
        error.message,
        contains('https://***@example.invalid/repo'),
      );
      expect(
        error.arguments,
        contains('https://audit:$_secret@example.invalid/repo'),
      );
    });

    test('masks the userinfo of a stderr line', () {
      final GitCommandException error = GitCommandException(
        arguments: const <String>['fetch', 'origin'],
        exitCode: 128,
        stderr: 'fatal: unable to access '
            "'https://u:$_secret@example.invalid/r/': refused\n",
      );

      expect(error.toString(), isNot(contains(_secret)));
      expect(error.stderr, contains(_secret));
      expect(error.message, contains('https://***@example.invalid/r/'));
    });

    test('masks a URL embedded in an argument', () {
      final GitCommandException error = GitCommandException(
        arguments: <String>[
          'config',
          '--get',
          'remote.origin.url=https://u:$_secret@example.invalid/r',
        ],
        exitCode: 1,
      );

      expect(error.toString(), isNot(contains(_secret)));
    });

    test('masks a two-argument extraHeader in message and diagnostic', () {
      final GitCommandException error = GitCommandException(
        arguments: <String>[
          '-c',
          'http.extraHeader=Authorization: Bearer $_secret',
          'fetch',
          'origin',
        ],
        exitCode: 128,
      );

      expect(error.message, isNot(contains(_secret)));
      expect(error.diagnostic, isNot(contains(_secret)));
      expect(error.message, contains('http.extraHeader=***'));
      expect(error.diagnostic, contains('http.extraHeader=***'));
      expect(
        error.arguments,
        contains('http.extraHeader=Authorization: Bearer $_secret'),
      );
    });

    test('masks an attached mixed-case extraHeader in message and diagnostic',
        () {
      final GitCommandException error = GitCommandException(
        arguments: <String>[
          '-cHTTP.ExtraHeader=Authorization: Bearer $_secret',
          'fetch',
        ],
        exitCode: 128,
      );

      expect(error.message, isNot(contains(_secret)));
      expect(error.diagnostic, isNot(contains(_secret)));
      expect(error.message, contains('HTTP.ExtraHeader=***'));
      expect(error.diagnostic, contains('HTTP.ExtraHeader=***'));
    });
  });

  group('GitTimeoutException', () {
    test('masks a two-argument extraHeader in message and diagnostic', () {
      final GitCommandTimeoutException details = GitCommandTimeoutException(
        arguments: <String>[
          '-c',
          'http.extraHeader=Authorization: Bearer $_secret',
          'fetch',
        ],
      );
      final GitTimeoutException error = GitTimeoutException(
        timeout: const Duration(seconds: 1),
        cause: details,
      );

      expect(details.message, isNot(contains(_secret)));
      expect(details.diagnostic, isNot(contains(_secret)));
      expect(details.message, contains('http.extraHeader=***'));
      expect(details.diagnostic, contains('http.extraHeader=***'));
      expect(error.diagnostic, isNot(contains(_secret)));
      expect(error.diagnostic, contains('http.extraHeader=***'));
    });

    test('masks an attached per-URL extraHeader in message and diagnostic', () {
      final GitCommandTimeoutException details = GitCommandTimeoutException(
        arguments: <String>[
          '-chttp.https://example.invalid/.extraHeader='
              'Authorization: Bearer $_secret',
          'fetch',
        ],
      );

      expect(details.message, isNot(contains(_secret)));
      expect(details.diagnostic, isNot(contains(_secret)));
      expect(
        details.message,
        contains('http.https://example.invalid/.extraHeader=***'),
      );
      expect(
        details.diagnostic,
        contains('http.https://example.invalid/.extraHeader=***'),
      );
    });

    test('masks the userinfo of a command in its cause', () {
      final GitCommandTimeoutException details = GitCommandTimeoutException(
        arguments: <String>[
          'fetch',
          'https://u:$_secret@example.invalid/r',
        ],
        stdout: 'from https://u:$_secret@example.invalid/r\n',
        stderr: 'fatal: cannot reach https://u:$_secret@example.invalid/r\n',
      );
      final GitTimeoutException error = GitTimeoutException(
        timeout: const Duration(seconds: 1),
        cause: details,
      );

      expect(error.toString(), isNot(contains(_secret)));
      expect(error.message, isNot(contains(_secret)));
      expect(error.diagnostic, isNot(contains(_secret)));
      expect(error.diagnostic, contains('https://***@example.invalid/r'));
      expect(
        details.arguments,
        contains('https://u:$_secret@example.invalid/r'),
      );
      expect(details.stdout, contains(_secret));
      expect(details.stderr, contains(_secret));
    });

    test('has no cause when a backend keeps no command details', () {
      final GitTimeoutException error = GitTimeoutException(
        timeout: const Duration(seconds: 1),
      );

      expect(error.cause, isNull);
      expect(error.message, contains('1000 ms'));
    });
  });

  group('GitUnsupportedUrlException', () {
    test('masks the refused URL but keeps the raw field', () {
      final GitUnsupportedUrlException error = GitUnsupportedUrlException(
        'ftp://u:$_secret@example.invalid/r',
        reason: 'unsupported',
      );

      expect(error.toString(), isNot(contains(_secret)));
      expect(error.message, contains('ftp://***@example.invalid/r'));
      expect(error.url, 'ftp://u:$_secret@example.invalid/r');
    });

    test('masks the URL a classification refuses', () {
      late GitUnsupportedUrlException error;
      try {
        classifyRemoteLocation('ftp://u:$_secret@example.invalid/r');
        fail('the location was accepted');
      } on GitUnsupportedUrlException catch (caught) {
        error = caught;
      }

      expect(error.url, contains(_secret));
      expect(error.toString(), isNot(contains(_secret)));
    });
  });
}
