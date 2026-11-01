import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../../../support/fake_git_http.dart' show RecordingBody;
import '../support/fake_git_process_launcher.dart';
import '../support/scripted_git_runner.dart';

void main() {
  const GitServedRepositoryId repository = GitServedRepositoryId('repo');
  const String gitDir = '/served/repo.git';

  /// A service on a fake launcher whose resolution answers [known]
  /// identifiers with a bare repository whose git directory is [gitDir].
  (ProcessGitUploadPackService, FakeGitProcessLauncher) buildService({
    Set<String> known = const <String>{'repo'},
    Duration inactivityTimeout = const Duration(milliseconds: 50),
    int bufferBytes = 1024,
  }) {
    final ScriptedGitRunner runner = ScriptedGitRunner()
      ..replyTo(
        const <String>['rev-parse', '--absolute-git-dir'],
        GitRunResult.fromStrings('$gitDir\n'),
      );
    final FakeGitProcessLauncher launcher = FakeGitProcessLauncher();
    final ProcessGitUploadPackService service = ProcessGitUploadPackService(
      resolveRepository: (GitServedRepositoryId id) => known.contains(id.value)
          ? ProcessGitFileBareRepository(
              runner: runner,
              context: GitRepositoryContext(path: '/served'),
            )
          : null,
      launcher: launcher,
      inactivityTimeout: inactivityTimeout,
      bufferBytes: bufferBytes,
    );
    return (service, launcher);
  }

  /// Waits until [condition] holds or a short budget expires.
  Future<void> waitFor(bool Function() condition) async {
    final Stopwatch watch = Stopwatch()..start();
    while (!condition() && watch.elapsedMilliseconds < 2000) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// The outcome of reading [body] until its end or its first error.
  Future<(List<int>, Object?)> collect(Stream<List<int>> body) async {
    final BytesBuilder builder = BytesBuilder();
    final Completer<Object?> done = Completer<Object?>();
    body.listen(
      builder.add,
      onError: done.complete,
      onDone: () => done.complete(null),
      cancelOnError: true,
    );
    final Object? error = await done.future;
    return (builder.takeBytes(), error);
  }

  group('ProcessGitUploadPackService launch', () {
    test('advertiseRefs launches the stateless advertisement on the git dir',
        () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();

      final GitServiceResponse response = await service.advertiseRefs(
        repository,
        protocol: GitProtocolParameters.empty(),
      );
      await response.cancel();

      expect(launcher.requests, hasLength(1));
      expect(launcher.requests.single.arguments, <String>[
        'upload-pack',
        '--stateless-rpc',
        '--advertise-refs',
        gitDir,
      ]);
      expect(launcher.requests.single.workingDirectory, isNull);
      expect(launcher.requests.single.environment, isEmpty,
          reason: 'no protocol was requested, so git receives no variable');
    });

    test('uploadPack launches the stateless rpc on the git dir', () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();

      final GitServiceResponse response = await service.uploadPack(
        repository,
        const Stream<List<int>>.empty(),
        protocol: GitProtocolParameters.empty(),
      );
      await response.cancel();

      expect(launcher.requests.single.arguments, <String>[
        'upload-pack',
        '--stateless-rpc',
        gitDir,
      ]);
    });

    test('the negotiated protocol crosses through GIT_PROTOCOL alone',
        () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();

      final GitServiceResponse response = await service.advertiseRefs(
        repository,
        protocol: GitProtocolParameters(<String>['version=2']),
      );
      await response.cancel();

      expect(launcher.requests.single.environment, <String, String>{
        'GIT_PROTOCOL': 'version=2',
      });
    });

    test('the advertisement closes the standard input of git', () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();

      final GitServiceResponse response = await service.advertiseRefs(
        repository,
        protocol: GitProtocolParameters.empty(),
      );
      await waitFor(() => launcher.processes.single.stdinClosed);
      await response.cancel();

      expect(launcher.processes.single.stdinClosed, isTrue);
    });
  });

  group('ProcessGitUploadPackService refusals', () {
    test('an unknown identifier fails as unknown, before git runs', () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService(known: <String>{});

      await expectLater(
        service.advertiseRefs(
          repository,
          protocol: GitProtocolParameters.empty(),
        ),
        throwsA(isA<GitUnknownServedRepositoryException>()),
      );
      await expectLater(
        service.uploadPack(
          repository,
          const Stream<List<int>>.empty(),
          protocol: GitProtocolParameters.empty(),
        ),
        throwsA(isA<GitUnknownServedRepositoryException>()),
      );
      expect(launcher.requests, isEmpty);
    });

    test('invalid protocol entries are refused before git runs', () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();

      for (final List<String> entries in const <List<String>>[
        <String>['version=2;injected'],
        <String>['version 2'],
        <String>['version=2\n'],
        <String>['x:y'],
        <String>['ok', 'bad entry'],
        <String>['vér'],
      ]) {
        await expectLater(
          service.advertiseRefs(
            repository,
            protocol: GitProtocolParameters(entries),
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'the entry "${entries.last}" must be refused',
        );
      }
      expect(launcher.requests, isEmpty);
    });

    test('non-positive bounds are refused', () {
      expect(
        () => buildService(inactivityTimeout: Duration.zero),
        throwsArgumentError,
      );
      expect(() => buildService(bufferBytes: 0), throwsArgumentError);
    });
  });

  group('ProcessGitUploadPackService backpressure', () {
    test('the request body is written only as fast as git takes it', () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();
      final RecordingBody request = RecordingBody();
      final GitServiceResponse response = await service.uploadPack(
        repository,
        request,
        protocol: GitProtocolParameters.empty(),
      );
      final FakeGitProcess process = launcher.processes.single;
      final Completer<void> gate = Completer<void>();
      process.writeGate = gate;

      request.add(utf8.encode('one'));
      request.add(utf8.encode('two'));
      request.add(utf8.encode('three'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(request.deliveredBytes, utf8.encode('one').length,
          reason: 'only the chunk git is being given crosses the body');
      expect(process.written, isEmpty,
          reason: 'the write waits for the process to take the bytes');

      gate.complete();
      await waitFor(() => process.written.length == 3);
      expect(
        process.written.map(utf8.decode),
        <String>['one', 'two', 'three'],
        reason: 'every chunk crosses, in order, once git takes it',
      );

      await request.closeSource();
      await waitFor(() => process.stdinClosed);
      await response.cancel();
    });

    test('large request chunks are split to the buffer size', () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService(bufferBytes: 16);
      final RecordingBody request = RecordingBody();
      final GitServiceResponse response = await service.uploadPack(
        repository,
        request,
        protocol: GitProtocolParameters.empty(),
      );

      request.add(List<int>.generate(40, (int i) => i));
      await request.closeSource();
      final FakeGitProcess process = launcher.processes.single;
      await waitFor(() => process.stdinClosed);
      expect(process.written.map((List<int> chunk) => chunk.length),
          <int>[16, 16, 8]);
      await response.cancel();
    });

    test('the response body is produced only as fast as it is read', () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();
      final GitServiceResponse response = await service.uploadPack(
        repository,
        const Stream<List<int>>.empty(),
        protocol: GitProtocolParameters.empty(),
      );
      final FakeGitProcess process = launcher.processes.single;

      final Completer<void> firstChunk = Completer<void>();
      final StreamSubscription<List<int>> subscription = response.body.listen(
        (List<int> chunk) {
          if (!firstChunk.isCompleted) {
            firstChunk.complete();
          }
        },
      );
      process.stdoutController.add(utf8.encode('abc'));
      await firstChunk.future;
      subscription.pause();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(process.stdoutController.isPaused, isTrue,
          reason: 'the standard output is only read while the body is read');

      subscription.resume();
      process.stdoutController.add(utf8.encode('def'));
      await process.stdoutController.close();
      process.exit.complete(0);
      await subscription.asFuture<void>();
      await subscription.cancel();
      await response.cancel();
    });
  });

  group('ProcessGitUploadPackService lifecycle', () {
    test('cancel kills the process and stops reading the request body',
        () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();
      final RecordingBody request = RecordingBody();
      final GitServiceResponse response = await service.uploadPack(
        repository,
        request,
        protocol: GitProtocolParameters.empty(),
      );

      await response.cancel();

      expect(launcher.processes.single.killCalls, 1);
      expect(request.cancelled, isTrue,
          reason: 'the request body is no longer read');
    });

    test('cancelling the body subscription kills the process', () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();
      final GitServiceResponse response = await service.uploadPack(
        repository,
        const Stream<List<int>>.empty(),
        protocol: GitProtocolParameters.empty(),
      );
      final StreamSubscription<List<int>> subscription = response.body.listen(
        (List<int> chunk) {},
      );

      await subscription.cancel();

      expect(launcher.processes.single.killCalls, 1);
    });

    test('a response never listened to is released after the inactivity delay',
        () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService(inactivityTimeout: const Duration(milliseconds: 30));

      final GitServiceResponse response = await service.advertiseRefs(
        repository,
        protocol: GitProtocolParameters.empty(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(launcher.processes.single.killCalls, 1,
          reason: 'the service itself releases an abandoned response');
      await response.cancel();
    });

    test('an idle response ends with an error and kills the process', () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService(inactivityTimeout: const Duration(milliseconds: 30));
      final GitServiceResponse response = await service.uploadPack(
        repository,
        StreamController<List<int>>().stream,
        protocol: GitProtocolParameters.empty(),
      );

      final (List<int> bytes, Object? error) = await collect(response.body);

      expect(error, isA<GitException>());
      expect(bytes, isEmpty);
      expect(launcher.processes.single.killCalls, 1);
    });

    test(
        'a failing request body kills the process and ends the body '
        'with an error', () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();
      final StreamController<List<int>> request = StreamController<List<int>>();
      final GitServiceResponse response = await service.uploadPack(
        repository,
        request.stream,
        protocol: GitProtocolParameters.empty(),
      );
      final Future<(List<int>, Object?)> collected = collect(response.body);

      request.addError(StateError('the request body broke'));
      final (List<int> bytes, Object? error) = await collected;

      expect(error, isA<GitException>());
      expect(bytes, isEmpty);
      expect(launcher.processes.single.killCalls, 1);
      await request.close();
    });
  });

  group('ProcessGitUploadPackService exit and stderr', () {
    test('a zero exit ends the body cleanly, without any standard error',
        () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();
      final GitServiceResponse response = await service.uploadPack(
        repository,
        const Stream<List<int>>.empty(),
        protocol: GitProtocolParameters.empty(),
      );
      final FakeGitProcess process = launcher.processes.single;
      final Future<(List<int>, Object?)> collected = collect(response.body);

      process.stderrController.add(utf8.encode('a hint for the host'));
      process.stdoutController.add(utf8.encode('pack bytes'));
      await process.stdoutController.close();
      await process.stderrController.close();
      process.exit.complete(0);

      final (List<int> bytes, Object? error) = await collected;
      expect(utf8.decode(bytes), 'pack bytes',
          reason: 'the standard error never reaches the body');
      expect(error, isNull);
    });

    test(
        'a non-zero exit after the stream started becomes an error of '
        'the stream', () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService();
      final GitServiceResponse response = await service.uploadPack(
        repository,
        const Stream<List<int>>.empty(),
        protocol: GitProtocolParameters.empty(),
      );
      final FakeGitProcess process = launcher.processes.single;
      final Future<(List<int>, Object?)> collected = collect(response.body);

      process.stdoutController.add(utf8.encode('partial pack'));
      await process.stdoutController.close();
      await process.stderrController.close();
      process.exit.complete(1);

      final (List<int> bytes, Object? error) = await collected;
      expect(utf8.decode(bytes), 'partial pack',
          reason: 'the bytes git produced before failing are delivered');
      expect(error, isA<GitCommandException>());
    });

    test('the standard error kept for the host is bounded by the buffer',
        () async {
      final (
        ProcessGitUploadPackService service,
        FakeGitProcessLauncher launcher
      ) = buildService(bufferBytes: 32);
      final GitServiceResponse response = await service.uploadPack(
        repository,
        const Stream<List<int>>.empty(),
        protocol: GitProtocolParameters.empty(),
      );
      final FakeGitProcess process = launcher.processes.single;
      final Future<(List<int>, Object?)> collected = collect(response.body);

      process.stderrController.add(utf8.encode('x' * 4096));
      await process.stderrController.close();
      await process.stdoutController.close();
      process.exit.complete(1);

      final (List<int> bytes, Object? error) = await collected;
      expect(error, isA<GitCommandException>());
      expect((error! as GitCommandException).stderr.length, 32,
          reason: 'only the buffer of stderr is kept, never the whole of it');
      expect(utf8.decode(bytes), isEmpty,
          reason: 'the stderr bytes never reach the body');
    });
  });
}
