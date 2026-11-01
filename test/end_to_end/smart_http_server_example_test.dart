@Tags(['git'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

/// Runs the smart HTTP server example as a process, clones and fetches the
/// repository it serves with the real git, stops it with Enter, and checks a
/// clean exit and the removal of its temporary directory.
void main() {
  test(
    'the smart HTTP server example serves clone and fetch and stops cleanly',
    () async {
      final int port = await _freePort();
      final Directory sandbox =
          await Directory.systemTemp.createTemp('git_engine_example_test_');
      final Process process = await Process.start(
        Platform.resolvedExecutable,
        <String>['run', 'example/smart_http_server.dart', '--port', '$port'],
      );
      final StringBuffer transcript = StringBuffer();
      final Completer<String> url = Completer<String>();
      final Completer<String> temporary = Completer<String>();
      final Future<void> stdoutDone = _read(
        process.stdout,
        transcript,
        (String line) {
          _complete(url, _after(line, 'URL: '));
          _complete(temporary, _after(line, 'Temporary directory: '));
        },
      );
      final Future<void> stderrDone = _read(process.stderr, transcript, null);
      try {
        final String serverUrl = await url.future.timeout(
          const Duration(seconds: 60),
          onTimeout: () =>
              throw TimeoutException('the URL was not printed:\n$transcript'),
        );
        final String temporaryPath = await temporary.future.timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw TimeoutException(
              'the temporary directory was not printed:\n$transcript'),
        );

        final File globalConfig = File(_join(sandbox.path, 'gitconfig'));
        await globalConfig.writeAsString('');
        final ProcessGitRunner runner = ProcessGitRunner(
          globalEnvironment: <String, String>{
            'GIT_CONFIG_NOSYSTEM': '1',
            'GIT_CONFIG_GLOBAL': globalConfig.path,
          },
        );
        final String clonePath = _join(sandbox.path, 'clone');
        await runner.run(GitRunRequest(
          arguments: <String>['clone', '--', serverUrl, clonePath],
        ));
        expect(
          File(_join(clonePath, 'README.md')).existsSync(),
          isTrue,
          reason: 'the served demo repository carries a commit',
        );
        await runner.run(GitRunRequest(
          arguments: const <String>['fetch'],
          workingDirectory: clonePath,
        ));

        process.stdin.writeln('');
        await process.stdin.flush();
        await process.stdin.close();
        final int exitCode = await process.exitCode.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            process.kill();
            return -1;
          },
        );
        expect(exitCode, 0, reason: transcript.toString());
        await stdoutDone.timeout(const Duration(seconds: 10));
        await stderrDone.timeout(const Duration(seconds: 10));

        expect(transcript.toString(), contains('Temporary directory removed.'));
        expect(
          Directory(temporaryPath).existsSync(),
          isFalse,
          reason: 'the example removes the directory it created',
        );
      } finally {
        process.kill();
        await process.stdin.close().catchError((Object _) {});
        await _deleteRecursively(sandbox);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Reads [stream] line by line into [transcript] and calls [onLine].
Future<void> _read(
  Stream<List<int>> stream,
  StringBuffer transcript,
  void Function(String line)? onLine,
) async {
  await for (final String line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    transcript.writeln(line);
    onLine?.call(line);
  }
}

/// Completes [completer] with [value] when it is not null and not settled.
void _complete(Completer<String> completer, String? value) {
  if (value != null && !completer.isCompleted) {
    completer.complete(value);
  }
}

/// The text following [prefix] on [line], or null when absent.
String? _after(String line, String prefix) {
  return line.startsWith(prefix) ? line.substring(prefix.length).trim() : null;
}

/// A free loopback port, released before the example binds it.
Future<int> _freePort() async {
  final ServerSocket socket =
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final int port = socket.port;
  await socket.close();
  return port;
}

/// Joins [base] and [relative] with the platform separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

/// Deletes [directory], retrying while Windows still holds file locks.
Future<void> _deleteRecursively(Directory directory) async {
  for (var attempt = 0;; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt >= 4) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
