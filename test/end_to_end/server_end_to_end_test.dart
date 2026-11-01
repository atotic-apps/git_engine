@Tags(['git'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/server_io.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../backends/process/support/bare_test_repository.dart';

/// Serves a temporary bare repository over smart HTTP and exercises it with
/// the library's own client and with the installed git executable.
void main() {
  test(
    'a real HTTP server serves the first server scenario end to end',
    () async {
      final BareTestRepository fixture = await BareTestRepository.create();
      addTearDown(fixture.dispose);

      final _TrackingLauncher launcher =
          _TrackingLauncher(ProcessGitProcessLauncher(runner: fixture.runner));
      const GitServedRepositoryId repository = GitServedRepositoryId('repo');
      final ProcessGitUploadPackService service = ProcessGitUploadPackService(
        resolveRepository: (GitServedRepositoryId requested) =>
            requested == repository ? fixture.repository : null,
        launcher: launcher,
        inactivityTimeout: const Duration(seconds: 30),
        bufferBytes: 64 * 1024,
      );
      final GitSmartHttpHandler handler = GitSmartHttpHandler(
        resolveRepository: (List<String> segments) =>
            segments.length == 1 && segments.single == repository.value
                ? repository
                : null,
        authorizationPolicy: const GitReadOnlyAuthorizationPolicy(),
        uploadPack: service,
        maxBodyBytes: 64 * 1024 * 1024,
      );
      final DartIoGitHttpServer server = await DartIoGitHttpServer.bind(
        handler: handler,
        authenticate: (HttpRequest request) => null,
      );
      addTearDown(() => server.close(force: true));

      final String base = 'http://127.0.0.1:${server.port}';
      final ProcessGitEngine engine = ProcessGitEngine(runner: fixture.runner);

      // The library's own client clones the served repository.
      final String libraryClone = _join(fixture.sandbox.path, 'library-clone');
      final GitWorkingRepository clone =
          await engine.clone('$base/repo', libraryClone);
      expect(
        (await clone.revisions.resolveRevision('HEAD'))?.value,
        fixture.headOid,
      );
      expect(await clone.worktree.isClean(), isTrue);
      expect(
        await File(_join(libraryClone, 'served.txt')).readAsString(),
        'served content\n',
      );

      // A second commit lands on the served repository, and the library's
      // client fetches it.
      final String updaterPath = _join(fixture.sandbox.path, 'updater');
      await _git(fixture, <String>[
        'clone',
        '--',
        fixture.directory.path,
        updaterPath,
      ]);
      await File(_join(updaterPath, 'second.txt')).writeAsString('second\n');
      await _git(
        fixture,
        const <String>['add', '--', 'second.txt'],
        workingDirectory: updaterPath,
      );
      await _git(
        fixture,
        const <String>[
          '-c',
          'user.name=End To End',
          '-c',
          'user.email=end-to-end@example.com',
          'commit',
          '-m',
          'Second',
        ],
        workingDirectory: updaterPath,
      );
      await _git(
        fixture,
        const <String>['push', 'origin', 'HEAD:main'],
        workingDirectory: updaterPath,
      );
      final String second = (await _git(
        fixture,
        const <String>['rev-parse', 'HEAD'],
        workingDirectory: fixture.directory.path,
      ))
          .stdout
          .trim();

      await engine.fetch(clone, remote: 'origin');
      expect(
        (await clone.revisions.resolveRevision('origin/main'))?.value,
        second,
        reason: 'fetch reads the new commit over HTTP',
      );

      // The installed git clones the same repository in protocol v0 and v2.
      for (final String version in const <String>['0', '2']) {
        final String target = _join(fixture.sandbox.path, 'git-v$version');
        await fixture.runner.run(GitRunRequest(arguments: <String>[
          '-c',
          'protocol.version=$version',
          'clone',
          '$base/repo',
          target,
        ]));
        final GitRunResult head = await _git(
          fixture,
          const <String>['rev-parse', 'HEAD'],
          workingDirectory: target,
        );
        expect(head.stdout.trim(), second,
            reason: 'git $version sees the fetched commit');
      }

      // Pushing is refused while the server is read-only.
      final HttpClient http = HttpClient();
      try {
        final HttpClientRequest push = await http.postUrl(
          Uri.parse('$base/repo/git-receive-pack'),
        );
        push.headers.contentType =
            ContentType('application', 'x-git-receive-pack-request');
        final HttpClientResponse pushResponse = await push.close();
        expect(pushResponse.statusCode, HttpStatus.forbidden);
        await pushResponse.drain<void>();

        await expectLater(
          fixture.runner.run(GitRunRequest(arguments: <String>[
            '-c',
            'protocol.version=0',
            'push',
            '$base/repo',
            'main',
          ], workingDirectory: updaterPath)),
          throwsA(isA<GitCommandException>()),
        );

        // An unknown repository is answered exactly like an unknown URL.
        final HttpClientRequest unknown = await http.getUrl(
          Uri.parse('$base/unknown/info/refs?service=git-upload-pack'),
        );
        final HttpClientResponse unknownResponse = await unknown.close();
        expect(unknownResponse.statusCode, HttpStatus.notFound);
        await unknownResponse.drain<void>();
      } finally {
        http.close(force: true);
      }

      // A large incompressible commit keeps upload-pack streaming long enough
      // for a disconnecting client to matter.
      await File(_join(updaterPath, 'large.bin')).writeAsBytes(
        _incompressibleBytes(16 * 1024 * 1024),
        flush: true,
      );
      await _git(
        fixture,
        const <String>['add', '--', 'large.bin'],
        workingDirectory: updaterPath,
      );
      await _git(
        fixture,
        const <String>[
          '-c',
          'user.name=End To End',
          '-c',
          'user.email=end-to-end@example.com',
          'commit',
          '-m',
          'Large',
        ],
        workingDirectory: updaterPath,
      );
      await _git(
        fixture,
        const <String>['push', 'origin', 'HEAD:main'],
        workingDirectory: updaterPath,
      );
      final String large = (await _git(
        fixture,
        const <String>['rev-parse', 'HEAD'],
        workingDirectory: fixture.directory.path,
      ))
          .stdout
          .trim();
      await _waitUntil(
        () => launcher.live.isEmpty,
        const Duration(seconds: 10),
      );

      // The client starts a pack transfer and disappears; the git process
      // behind the response must not survive it.
      final HttpClient disconnecting = HttpClient();
      try {
        final HttpClientRequest request = await disconnecting.postUrl(
          Uri.parse('$base/repo/git-upload-pack'),
        );
        request.headers.contentType =
            ContentType('application', 'x-git-upload-pack-request');
        request.headers.set('Git-Protocol', 'version=0');
        request.add(_v0FetchRequest(large));
        final HttpClientResponse response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        expect(
          launcher.live,
          isNotEmpty,
          reason: 'the pack transfer is still running',
        );

        final Socket socket = await response.detachSocket();
        socket.destroy();
        await _waitUntil(
          () => launcher.live.isEmpty,
          const Duration(seconds: 20),
        );
        expect(launcher.live, isEmpty,
            reason: 'the disconnect killed the upload-pack process');
      } finally {
        disconnecting.close(force: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Runs git through the fixture's isolated runner.
Future<GitRunResult> _git(
  BareTestRepository fixture,
  List<String> arguments, {
  String? workingDirectory,
}) {
  return fixture.runner.run(GitRunRequest(
    arguments: arguments,
    workingDirectory: workingDirectory,
  ));
}

/// A protocol v0 request asking for the pack of [oid]: one `want` line, a
/// flush-pkt, then `done`.
List<int> _v0FetchRequest(String oid) {
  final String want = 'want $oid\n';
  final String length = (want.length + 4).toRadixString(16).padLeft(4, '0');
  return <int>[
    ...ascii.encode('$length$want'),
    ...ascii.encode('0000'),
    ...ascii.encode('0009done\n'),
  ];
}

/// Deterministic, poorly compressible bytes of [length].
Uint8List _incompressibleBytes(int length) {
  final Uint8List bytes = Uint8List(length);
  var state = 0x12345678;
  for (var index = 0; index < bytes.length; index++) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    bytes[index] = (state >> 16) & 0xff;
  }
  return bytes;
}

/// Waits until [condition] holds, or fails after [timeout].
Future<void> _waitUntil(bool Function() condition, Duration timeout) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// Joins [base] and [relative] with the platform separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

/// A launcher that records the processes still alive.
final class _TrackingLauncher implements GitProcessLauncher {
  _TrackingLauncher(this._inner);

  final GitProcessLauncher _inner;

  /// The processes that have not exited yet.
  final Set<_TrackedProcess> live = <_TrackedProcess>{};

  @override
  Future<GitLaunchedProcess> start(GitProcessLaunchRequest request) async {
    final _TrackedProcess process =
        _TrackedProcess(await _inner.start(request));
    live.add(process);
    unawaited(process.exitCode.then<void>(
      (int exitCode) {
        live.remove(process);
      },
      onError: (Object error, StackTrace stackTrace) {
        live.remove(process);
      },
    ));
    return process;
  }
}

/// A launched process whose exit removes it from the tracking set.
final class _TrackedProcess implements GitLaunchedProcess {
  _TrackedProcess(this._inner);

  final GitLaunchedProcess _inner;

  @override
  Stream<List<int>> get stdout => _inner.stdout;

  @override
  Stream<List<int>> get stderr => _inner.stderr;

  @override
  Future<int> get exitCode => _inner.exitCode;

  @override
  Future<void> writeStdin(List<int> bytes) => _inner.writeStdin(bytes);

  @override
  Future<void> closeStdin() => _inner.closeStdin();

  @override
  Future<void> kill() => _inner.kill();
}
