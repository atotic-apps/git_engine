@Tags(['git'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/server_io.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../backends/process/support/bare_test_repository.dart';

/// The server limits over real git processes and loopback sockets: a cap on
/// concurrent upload-pack exchanges, a total duration, and the release of
/// every launched process.
void main() {
  late BareTestRepository fixture;
  late List<_CountingLauncher> launchers;

  setUp(() async {
    fixture = await BareTestRepository.create();
    launchers = <_CountingLauncher>[];
  });

  tearDown(() async {
    for (final _CountingLauncher launcher in launchers) {
      await _waitUntil(
        () => launcher.live == 0,
        timeout: const Duration(seconds: 20),
      );
    }
    await fixture.dispose();
  });

  test('a cap of four starts exactly four upload-pack processes', () async {
    final _TestServer server = await _start(
      fixture,
      launchers,
      maxConcurrentExchanges: 4,
      inactivityTimeout: const Duration(seconds: 30),
    );
    final List<_Client> clients = <_Client>[];
    addTearDown(() {
      for (final _Client client in clients) {
        client.destroy();
      }
    });
    final List<int> request = ascii.encode(_wantRequest(fixture.headOid));
    for (var index = 0; index < 8; index++) {
      clients.add(await _Client.open(server.server.port, body: request));
    }

    // The accepted exchanges hold their response until git has something to
    // say; only the four refused ones answer right away.
    await _waitUntil(
      () => clients.where((_Client client) => client.head != null).length == 4,
      timeout: const Duration(seconds: 30),
    );
    final List<_ResponseHead> refused = <_ResponseHead>[
      for (final _Client client in clients)
        if (client.head != null) client.head!,
    ];
    expect(refused, hasLength(4));
    for (final _ResponseHead head in refused) {
      expect(head.status, 503);
      expect(head.headers['retry-after'], '1');
    }
    await _waitUntil(
      () => server.launcher.started == 4 && server.launcher.live == 4,
      timeout: const Duration(seconds: 20),
    );
    expect(server.launcher.started, 4,
        reason: 'no process is launched beyond the cap');
    expect(server.launcher.live, 4,
        reason: 'the four accepted processes wait for the rest of the request');

    for (final _Client client in clients) {
      client.destroy();
    }
    await _waitUntil(
      () => server.launcher.live == 0,
      timeout: const Duration(seconds: 20),
    );
  });

  test('a slow exchange is killed near the total duration', () async {
    final _TestServer server = await _start(
      fixture,
      launchers,
      maxConcurrentExchanges: 8,
      maxExchangeDuration: const Duration(seconds: 1),
      inactivityTimeout: const Duration(milliseconds: 700),
    );
    final DateTime started = DateTime.now();
    final List<int> request =
        ascii.encode('${_wantRequest(fixture.headOid)}ffe0');
    final _Client client =
        await _Client.open(server.server.port, body: request);
    addTearDown(client.destroy);
    await _waitUntil(
      () => server.launcher.live == 1,
      timeout: const Duration(seconds: 15),
    );

    // One byte every hundred milliseconds keeps the inactivity delay from
    // firing; only the total duration may stop this exchange.
    final Timer ticker = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => client.send(<int>[0x61]),
    );
    addTearDown(ticker.cancel);

    await client.closed.timeout(const Duration(seconds: 15));
    ticker.cancel();
    final Duration elapsed = DateTime.now().difference(started);
    expect(elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 700)));
    expect(elapsed, lessThan(const Duration(seconds: 8)));
    await _waitUntil(
      () => server.launcher.live == 0,
      timeout: const Duration(seconds: 20),
    );
  });

  test('held-open advertisements never start more than the cap', () async {
    final _TestServer server = await _start(
      fixture,
      launchers,
      maxConcurrentExchanges: 4,
      inactivityTimeout: const Duration(seconds: 30),
      holdProcessOutput: true,
    );
    final List<_Client> clients = <_Client>[];
    addTearDown(() {
      for (final _Client client in clients) {
        client.destroy();
      }
    });
    for (var index = 0; index < 8; index++) {
      clients.add(await _Client.openAdvertisement(server.server.port));
    }

    await _waitUntil(
      () => clients.where((_Client client) => client.head != null).length == 8,
      timeout: const Duration(seconds: 30),
    );
    final List<_ResponseHead> accepted = <_ResponseHead>[
      for (final _Client client in clients)
        if (client.head!.status == 200) client.head!,
    ];
    final List<_ResponseHead> refused = <_ResponseHead>[
      for (final _Client client in clients)
        if (client.head!.status == 503) client.head!,
    ];
    expect(accepted, hasLength(4));
    expect(refused, hasLength(4));
    for (final _ResponseHead head in refused) {
      expect(head.headers['retry-after'], '1');
    }
    await _waitUntil(
      () => server.launcher.started == 4,
      timeout: const Duration(seconds: 20),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.launcher.started, 4,
        reason: 'no process is launched beyond the cap');

    for (final _Client client in clients) {
      client.destroy();
    }
    await _waitUntil(
      () => server.launcher.live == 0,
      timeout: const Duration(seconds: 20),
    );
  });

  test('clones through the adapter with a cap of one', () async {
    final _TestServer server = await _start(
      fixture,
      launchers,
      maxConcurrentExchanges: 1,
      inactivityTimeout: const Duration(seconds: 30),
    );
    final String clonePath = _join(fixture.sandbox.path, 'clone');
    await fixture.runner.run(GitRunRequest(
      arguments: <String>[
        'clone',
        '--',
        'http://127.0.0.1:${server.server.port}/served',
        clonePath,
      ],
    ));
    expect(File(_join(clonePath, 'served.txt')).existsSync(), isTrue);

    await _waitUntil(
      () => server.launcher.live == 0,
      timeout: const Duration(seconds: 20),
    );
  });

  test('closing the client releases the slot for the next exchange', () async {
    final _TestServer server = await _start(
      fixture,
      launchers,
      maxConcurrentExchanges: 1,
      inactivityTimeout: const Duration(seconds: 30),
    );
    final List<int> request = ascii.encode(_wantRequest(fixture.headOid));

    final _Client first = await _Client.open(server.server.port, body: request);
    addTearDown(first.destroy);
    await _waitUntil(
      () => server.launcher.live == 1,
      timeout: const Duration(seconds: 15),
    );

    final _Client second =
        await _Client.open(server.server.port, body: request);
    addTearDown(second.destroy);
    final _ResponseHead? refused =
        await second.headers.timeout(const Duration(seconds: 15));
    expect(refused, isNotNull);
    expect(refused!.status, 503);
    expect(refused.headers['retry-after'], '1');

    first.destroy();
    await _waitUntil(
      () => server.launcher.live == 0,
      timeout: const Duration(seconds: 20),
    );

    final _Client third = await _Client.open(server.server.port, body: request);
    addTearDown(third.destroy);
    await _waitUntil(
      () => server.launcher.started == 2 && server.launcher.live == 1,
      timeout: const Duration(seconds: 15),
    );
    expect(server.launcher.started, 2,
        reason: 'the closed exchange released its slot');

    third.destroy();
    await _waitUntil(
      () => server.launcher.live == 0,
      timeout: const Duration(seconds: 20),
    );
  });
}

/// Starts a read-only server on a temporary bare repository, with a launcher
/// that counts the upload-pack processes it starts.
Future<_TestServer> _start(
  BareTestRepository fixture,
  List<_CountingLauncher> launchers, {
  required int maxConcurrentExchanges,
  required Duration inactivityTimeout,
  Duration maxExchangeDuration = const Duration(minutes: 10),
  bool holdProcessOutput = false,
}) async {
  final _CountingLauncher launcher = _CountingLauncher(
    ProcessGitProcessLauncher(runner: fixture.runner),
    holdProcessOutput: holdProcessOutput,
  );
  launchers.add(launcher);
  final ProcessGitUploadPackService service = ProcessGitUploadPackService(
    resolveRepository: (GitServedRepositoryId id) =>
        id.value == 'served' ? fixture.repository : null,
    launcher: launcher,
    inactivityTimeout: inactivityTimeout,
    bufferBytes: 64 * 1024,
  );
  final GitSmartHttpHandler handler = GitSmartHttpHandler(
    resolveRepository: (List<String> segments) =>
        segments.length == 1 && segments.single == 'served'
            ? const GitServedRepositoryId('served')
            : null,
    authorizationPolicy: const GitReadOnlyAuthorizationPolicy(),
    uploadPack: service,
    maxBodyBytes: 1024 * 1024,
    maxConcurrentExchanges: maxConcurrentExchanges,
    maxExchangeDuration: maxExchangeDuration,
  );
  final DartIoGitHttpServer server = await DartIoGitHttpServer.bind(
    handler: handler,
    authenticate: (HttpRequest request) => null,
  );
  addTearDown(() => server.close(force: true));
  return _TestServer(server, launcher);
}

/// Joins [base] and [relative] with the platform separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

/// One pkt-line asking for the served commit, followed by a flush packet.
/// git answers it while keeping its standard input open for `done`.
String _wantRequest(String oid) {
  final String payload = 'want $oid\n';
  final int length = payload.length + 4;
  return length.toRadixString(16).padLeft(4, '0') + payload + '0000';
}

/// A running server and the launcher counting its git processes.
final class _TestServer {
  _TestServer(this.server, this.launcher);

  final DartIoGitHttpServer server;
  final _CountingLauncher launcher;
}

/// A launcher that counts the processes it starts and how many are alive.
final class _CountingLauncher implements GitProcessLauncher {
  _CountingLauncher(this._inner, {this.holdProcessOutput = false});

  final GitProcessLauncher _inner;

  /// When true, the standard output of every process is drained but never
  /// forwarded, so the advertisement response stays open while its process
  /// runs and exits.
  final bool holdProcessOutput;

  /// Processes successfully started.
  int started = 0;

  /// Processes that have not exited yet.
  int live = 0;

  @override
  Future<GitLaunchedProcess> start(GitProcessLaunchRequest request) async {
    final GitLaunchedProcess process = await _inner.start(request);
    started++;
    live++;
    final _CountedProcess counted = _CountedProcess(process, () {
      live--;
    });
    return holdProcessOutput ? _HeldProcess(counted) : counted;
  }
}

/// A launched process whose standard output never completes, so a response
/// built on it stays open while the underlying process is drained and exits.
final class _HeldProcess implements GitLaunchedProcess {
  _HeldProcess(this._process) {
    _process.stdout.listen((List<int> chunk) {}, onError: (Object _) {});
  }

  final GitLaunchedProcess _process;
  final StreamController<List<int>> _output = StreamController<List<int>>();

  @override
  Stream<List<int>> get stdout => _output.stream;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> writeStdin(List<int> bytes) => _process.writeStdin(bytes);

  @override
  Future<void> closeStdin() => _process.closeStdin();

  @override
  Future<void> kill() async {
    if (!_output.isClosed) {
      await _output.close();
    }
    await _process.kill();
  }
}

/// A launched process that reports its exit once.
final class _CountedProcess implements GitLaunchedProcess {
  _CountedProcess(this._process, this._onExit) {
    unawaited(_track());
  }

  final GitLaunchedProcess _process;
  final void Function() _onExit;

  Future<void> _track() async {
    try {
      await _process.exitCode;
    } finally {
      _onExit();
    }
  }

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> writeStdin(List<int> bytes) => _process.writeStdin(bytes);

  @override
  Future<void> closeStdin() => _process.closeStdin();

  @override
  Future<void> kill() => _process.kill();
}

/// A raw HTTP client that keeps its request body open and reads the response
/// status line and headers.
final class _Client {
  _Client._(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onError: (Object error) => _close(),
      onDone: _close,
    );
  }

  final Socket _socket;
  final List<int> _head = <int>[];
  final Completer<_ResponseHead?> _headers = Completer<_ResponseHead?>();
  final Completer<void> _closed = Completer<void>();

  /// The response status and headers, or null while none arrived.
  _ResponseHead? head;
  late final StreamSubscription<List<int>> _subscription;

  /// Connects to [port] and sends a `git-upload-pack` request whose declared
  /// length is larger than [body], leaving the body open.
  static Future<_Client> open(
    int port, {
    required List<int> body,
    int contentLength = 1024,
  }) async {
    // The socket stays open for the whole exchange; destroy() closes it.
    // ignore: close_sinks
    final Socket socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
    );
    final _Client client = _Client._(socket);
    socket.add(ascii.encode(
      'POST /served/git-upload-pack HTTP/1.1\r\n'
      'Host: 127.0.0.1:$port\r\n'
      'Content-Type: application/x-git-upload-pack-request\r\n'
      'Content-Length: $contentLength\r\n'
      '\r\n',
    ));
    socket.add(body);
    await socket.flush();
    return client;
  }

  /// Connects to [port] and sends a `git-upload-pack` reference
  /// advertisement request, keeping the connection open.
  static Future<_Client> openAdvertisement(int port) async {
    // The socket stays open for the whole exchange; destroy() closes it.
    // ignore: close_sinks
    final Socket socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
    );
    final _Client client = _Client._(socket);
    socket.add(ascii.encode(
      'GET /served/info/refs?service=git-upload-pack HTTP/1.1\r\n'
      'Host: 127.0.0.1:$port\r\n'
      '\r\n',
    ));
    await socket.flush();
    return client;
  }

  /// The response status line and headers, or null when the connection
  /// closed first.
  Future<_ResponseHead?> get headers => _headers.future;

  /// Completes when the connection ends, from either side.
  Future<void> get closed => _closed.future;

  /// Sends more request body bytes.
  void send(List<int> bytes) {
    try {
      _socket.add(bytes);
    } catch (_) {
      // The connection is already gone.
    }
  }

  /// Closes the connection abruptly, as a client that went away.
  void destroy() {
    try {
      unawaited(_socket.close());
    } catch (_) {
      // The connection is already gone.
    }
    _socket.destroy();
    _close();
  }

  void _onData(List<int> data) {
    if (_headers.isCompleted) {
      return;
    }
    _head.addAll(data);
    final int end = _headerEnd(_head);
    if (end >= 0) {
      final _ResponseHead parsed = _parseHead(_head.sublist(0, end));
      head = parsed;
      _headers.complete(parsed);
    }
  }

  void _close() {
    unawaited(_subscription.cancel());
    if (!_closed.isCompleted) {
      _closed.complete();
    }
    if (!_headers.isCompleted) {
      _headers.complete(null);
    }
  }
}

/// The status and headers of an HTTP response.
final class _ResponseHead {
  _ResponseHead(this.status, this.headers);

  final int status;
  final Map<String, String> headers;
}

/// The index just past the `\r\n\r\n` ending the headers, or -1.
int _headerEnd(List<int> bytes) {
  for (var index = 0; index + 3 < bytes.length; index++) {
    if (bytes[index] == 13 &&
        bytes[index + 1] == 10 &&
        bytes[index + 2] == 13 &&
        bytes[index + 3] == 10) {
      return index + 4;
    }
  }
  return -1;
}

/// Parses a status line and its headers.
_ResponseHead _parseHead(List<int> bytes) {
  final List<String> lines = latin1.decode(bytes).split('\r\n');
  final int status = int.parse(lines.first.split(' ')[1]);
  final Map<String, String> headers = <String, String>{};
  for (final String line in lines.skip(1)) {
    final int colon = line.indexOf(':');
    if (colon > 0) {
      headers[line.substring(0, colon).trim().toLowerCase()] =
          line.substring(colon + 1).trim();
    }
  }
  return _ResponseHead(status, headers);
}

/// Waits until [condition] holds, failing after [timeout].
Future<void> _waitUntil(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
