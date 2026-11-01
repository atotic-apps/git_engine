@Tags(['machine'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/server_io.dart';
import 'package:test/test.dart';

import '../server/handler_test_helpers.dart';
import '../support/fake_git_http.dart';
import '../support/fake_upload_pack_service.dart';

/// Exercises the `dart:io` adapter over real loopback connections: the
/// exchanges whose verification needs an actual socket run only when the
/// `machine` tag is explicitly enabled.
void main() {
  group('DartIoGitHttpServer full duplex', () {
    test(
      'streams the response while the request body is still arriving',
      () async {
        const int requestBytes = 8 * 1024 * 1024;
        const int chunkBytes = 64 * 1024;
        final Uint8List request = _pseudoRandomBytes(requestBytes);

        final _InterlockedUploadPackService service =
            _InterlockedUploadPackService();
        final DartIoGitHttpServer server = await _start(
          GitSmartHttpHandler(
            resolveRepository: (List<String> segments) =>
                segments.length == 1 && segments.single == 'repo'
                    ? repoId
                    : null,
            authorizationPolicy: FakeGitAuthorizationPolicy(),
            uploadPack: service,
            maxBodyBytes: 64 * 1024 * 1024,
          ),
        );

        // A raw socket is the only client able to send a request and read
        // the response at the same time, which is what this exchange needs.
        final Socket socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          server.port,
        );
        addTearDown(socket.destroy);

        final List<int> head = <int>[];
        final BytesBuilder body = BytesBuilder(copy: false);
        final Completer<void> firstBodyByte = Completer<void>();
        final Completer<void> responseEnded = Completer<void>();
        var headersComplete = false;
        socket.listen(
          (List<int> data) {
            if (headersComplete) {
              body.add(data);
              if (!firstBodyByte.isCompleted) {
                firstBodyByte.complete();
              }
              return;
            }
            head.addAll(data);
            final int end = _headerEnd(head);
            if (end < 0) {
              return;
            }
            headersComplete = true;
            body.add(head.sublist(end));
            if (!firstBodyByte.isCompleted) {
              firstBodyByte.complete();
            }
          },
          onDone: () {
            if (!responseEnded.isCompleted) {
              responseEnded.complete();
            }
          },
          onError: (Object error) {
            if (!responseEnded.isCompleted) {
              responseEnded.completeError(error);
            }
          },
        );

        final String requestHead = 'POST /repo/git-upload-pack HTTP/1.1\r\n'
            'Host: 127.0.0.1:${server.port}\r\n'
            'Content-Type: application/x-git-upload-pack-request\r\n'
            'Content-Length: $requestBytes\r\n'
            '\r\n';
        socket.add(ascii.encode(requestHead));
        socket.add(Uint8List.sublistView(request, 0, chunkBytes));
        await socket.flush();

        // The service only reads the request as fast as its response is
        // consumed, and only emits the response as fast as it reads the
        // request: the first response byte must come back while the request
        // is still being sent, far before any release delay could fire.
        await firstBodyByte.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw StateError(
            'no response byte arrived while the request was still open',
          ),
        );

        final List<List<int>> rest = <List<int>>[
          for (var offset = chunkBytes;
              offset < requestBytes;
              offset += chunkBytes)
            Uint8List.sublistView(
              request,
              offset,
              offset + chunkBytes > requestBytes
                  ? requestBytes
                  : offset + chunkBytes,
            ),
        ];
        await socket.addStream(Stream<List<int>>.fromIterable(rest));

        await responseEnded.future.timeout(const Duration(seconds: 30));

        final List<int> response = _dechunked(body.takeBytes());
        expect(response.length, requestBytes,
            reason: 'one response byte per request byte');
        expect(_isShiftOf(response, request), isTrue,
            reason: 'every response byte is its request byte plus one');
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('DartIoGitHttpServer failures', () {
    test('aborts the connection when the response body fails', () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..holdResponseOpen = true;
      final DartIoGitHttpServer server = await _start(
        RecordingResolver().handler(service: service),
      );

      final HttpClient client = HttpClient();
      try {
        final HttpClientRequest request = await client.postUrl(Uri.parse(
          'http://127.0.0.1:${server.port}/repo/git-upload-pack',
        ));
        request.headers.contentType =
            ContentType('application', 'x-git-upload-pack-request');
        request.add(<int>[0, 0, 0, 0]);
        final Future<HttpClientResponse> closing = request.close();
        await _waitUntil(() => service.responses.isNotEmpty);
        service.responses.single.controller.add(<int>[1, 2, 3]);
        final HttpClientResponse response = await closing;
        expect(response.statusCode, HttpStatus.ok);

        final Future<void> reading =
            expectLater(_readAll(response), throwsA(anything));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        service.responses.single.controller
            .addError(StateError('the pack failed'));

        await reading;
      } finally {
        client.close(force: true);
      }
    });

    test('cancels the response when the client disconnects', () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..holdResponseOpen = true;
      final DartIoGitHttpServer server = await _start(
        RecordingResolver().handler(service: service),
      );

      final HttpClient client = HttpClient();
      try {
        final HttpClientRequest request = await client.postUrl(Uri.parse(
          'http://127.0.0.1:${server.port}/repo/git-upload-pack',
        ));
        request.headers.contentType =
            ContentType('application', 'x-git-upload-pack-request');
        request.add(<int>[0, 0, 0, 0]);
        final Future<HttpClientResponse> closing = request.close();
        await _waitUntil(() => service.responses.isNotEmpty);
        service.responses.single.controller.add(<int>[1, 2, 3]);
        final HttpClientResponse response = await closing;
        expect(response.statusCode, HttpStatus.ok);

        final Socket socket = await response.detachSocket();
        socket.destroy();
        final FakeServiceResponse serviceResponse = service.responses.single;
        for (var attempt = 0; attempt < 100; attempt++) {
          if (serviceResponse.cancelCalls > 0) {
            break;
          }
          serviceResponse.controller.add(List<int>.filled(64 * 1024, 7));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        await serviceResponse.cancelled.timeout(const Duration(seconds: 5));
        expect(serviceResponse.cancelCalls, greaterThan(0));
      } finally {
        client.close(force: true);
      }
    });
  });
}

/// Starts a server for the test and registers its closure.
Future<DartIoGitHttpServer> _start(GitSmartHttpHandler handler) async {
  final DartIoGitHttpServer server = await DartIoGitHttpServer.bind(
    handler: handler,
    authenticate: (HttpRequest request) => null,
  );
  addTearDown(() => server.close(force: true));
  return server;
}

/// Reads a response body to its end.
Future<List<int>> _readAll(HttpClientResponse response) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// Waits until [condition] holds, or fails after five seconds.
Future<void> _waitUntil(bool Function() condition) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Deterministic bytes of [length] with no structure a buffer could rely on.
Uint8List _pseudoRandomBytes(int length) {
  final Uint8List bytes = Uint8List(length);
  var state = 0x12345678;
  for (var index = 0; index < length; index++) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    bytes[index] = (state >> 16) & 0xff;
  }
  return bytes;
}

/// The index just past the `\r\n\r\n` ending HTTP headers, or -1.
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

/// Reassembles a chunked body: hex chunk-size line, chunk, CRLF, until a
/// zero-size chunk.
List<int> _dechunked(List<int> raw) {
  final BytesBuilder body = BytesBuilder(copy: false);
  var offset = 0;
  while (offset < raw.length) {
    var lineEnd = offset;
    while (lineEnd + 1 < raw.length &&
        !(raw[lineEnd] == 13 && raw[lineEnd + 1] == 10)) {
      lineEnd++;
    }
    final int size =
        int.parse(ascii.decode(raw.sublist(offset, lineEnd)), radix: 16);
    offset = lineEnd + 2;
    if (size == 0) {
      break;
    }
    body.add(raw.sublist(offset, offset + size));
    offset += size + 2;
  }
  return body.takeBytes();
}

/// Whether [shifted] is [source] with every byte incremented by one.
bool _isShiftOf(List<int> shifted, List<int> source) {
  if (shifted.length != source.length) {
    return false;
  }
  for (var index = 0; index < shifted.length; index++) {
    if (shifted[index] != (source[index] + 1) & 0xff) {
      return false;
    }
  }
  return true;
}

/// An upload-pack service whose request reading and response production pace
/// each other: every response chunk is derived from one request chunk, and
/// the next request chunk is read only once the previous response chunk was
/// consumed. The first request chunk is read as soon as [uploadPack] is
/// called, the way a service already pumping the input of its consumer does.
final class _InterlockedUploadPackService implements GitUploadPackService {
  @override
  Future<GitServiceResponse> advertiseRefs(
    GitServedRepositoryId repository, {
    required GitProtocolParameters protocol,
  }) async {
    throw UnimplementedError('this fake only serves uploadPack');
  }

  @override
  Future<GitServiceResponse> uploadPack(
    GitServedRepositoryId repository,
    Stream<List<int>> request, {
    required GitProtocolParameters protocol,
  }) async {
    final StreamIterator<List<int>> requestIterator =
        StreamIterator<List<int>>(request);
    if (!await requestIterator.moveNext()) {
      await requestIterator.cancel();
      throw StateError('the request body ended before its first chunk');
    }
    final List<int> first = requestIterator.current;

    Stream<List<int>> pump() async* {
      yield _shifted(first);
      while (await requestIterator.moveNext()) {
        yield _shifted(requestIterator.current);
      }
    }

    return _InterlockedResponse(pump(), requestIterator.cancel);
  }
}

/// [chunk] with every byte incremented by one, independent of where the
/// transport cut the request into chunks.
List<int> _shifted(List<int> chunk) {
  final Uint8List shifted = Uint8List(chunk.length);
  for (var index = 0; index < shifted.length; index++) {
    shifted[index] = (chunk[index] + 1) & 0xff;
  }
  return shifted;
}

/// A [GitServiceResponse] whose release cancels the reading of the request.
final class _InterlockedResponse implements GitServiceResponse {
  final Stream<List<int>> _body;
  final Future<void> Function() _release;

  _InterlockedResponse(this._body, this._release);

  @override
  Stream<List<int>> get body => _body;

  @override
  Future<void> cancel() => _release();
}
