import 'dart:async';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/src/server/dart_io/dart_io_exchange.dart';
import 'package:test/test.dart';

import '../../support/fake_git_http.dart';
import '../../support/fake_upload_pack_service.dart';
import '../handler_test_helpers.dart';
import 'dart_io_exchange_test_support.dart';

void main() {
  group('DartIoExchange request conversion', () {
    test('keeps the path percent-encoded for the handler to decode', () async {
      final RecordingResolver resolver = RecordingResolver(
        accepted: <List<String>>{
          <String>['repo%20name'],
        },
      );
      final FakeUploadPackService service = FakeUploadPackService();
      final RecordingDartIoResponse response = RecordingDartIoResponse();

      await _exchange(resolver.handler(service: service)).serve(
        FakeDartIoRequest(
          path: '/repo%2520name/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
        response,
      );

      expect(response.statusCode, 200);
      expect(
        resolver.calls.single,
        <String>['repo%20name'],
        reason: 'the adapter must not decode the path before the handler',
      );
    });

    test('passes the identity the host authenticated', () async {
      final FakeGitAuthorizationPolicy policy = FakeGitAuthorizationPolicy();
      final RecordingResolver resolver = RecordingResolver();
      final FakeUploadPackService service = FakeUploadPackService();
      final RecordingDartIoResponse response = RecordingDartIoResponse();

      await _exchange(
        resolver.handler(service: service, policy: policy),
        authenticate: (DartIoRequest request) => const FakeGitPrincipal('ada'),
      ).serve(
        FakeDartIoRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
        response,
      );

      expect(response.statusCode, 200);
      expect(policy.canReadCalls.single?.name, 'ada');
    });
  });

  group('DartIoExchange bodies', () {
    test('carries the request body and the response body as streams', () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..echoRequestBody = true;
      final RecordingDartIoResponse response = RecordingDartIoResponse();

      await _exchange(RecordingResolver().handler(service: service)).serve(
        _postRequest(
          body: Stream<List<int>>.fromIterable(<List<int>>[
            <int>[1, 2],
            <int>[3, 4],
          ]),
        ),
        response,
      );

      expect(response.statusCode, 200);
      expect(response.bytes, <int>[1, 2, 3, 4]);
      expect(response.closed, isTrue);
    });

    test('supplies the dart:io gzip decoder to the handler', () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..echoRequestBody = true;
      final RecordingDartIoResponse response = RecordingDartIoResponse();
      final List<int> payload = <int>[
        for (int index = 0; index < 4096; index++) index % 251,
      ];

      await _exchange(RecordingResolver().handler(service: service)).serve(
        _postRequest(
          headers: <String, List<String>>{
            'Content-Encoding': <String>['gzip'],
          },
          body: Stream<List<int>>.value(gzip.encode(payload)),
        ),
        response,
      );

      expect(response.statusCode, 200);
      expect(response.bytes, payload);
    });

    test('bounds a compressed body after decompression', () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..echoRequestBody = true;
      final List<Object> failures = <Object>[];
      final FailingWriteResponse response = FailingWriteResponse();
      final List<int> compressed = gzip.encode(List<int>.filled(100000, 5));

      await _exchange(
        RecordingResolver().handler(
          service: service,
          maxBodyBytes: 1024,
          onError: (Object error, StackTrace stackTrace) => failures.add(error),
        ),
      ).serve(
        _postRequest(
          headers: <String, List<String>>{
            'Content-Encoding': <String>['gzip'],
          },
          body: Stream<List<int>>.value(compressed),
        ),
        response,
      );

      expect(response.statusCode, 200);
      expect(response.bytes.length, lessThanOrEqualTo(1024));
      expect(response.writeError.toString(), contains('limit'));
      expect(response.aborted, isTrue);
      expect(response.closed, isFalse);
      expect(failures, hasLength(1));
      expect(failures.single.toString(), contains('limit'));
    });

    test('aborts the connection when the response body fails', () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..holdResponseOpen = true;
      final FailingWriteResponse response = FailingWriteResponse();

      final Future<void> serving =
          _exchange(RecordingResolver().handler(service: service))
              .serve(_postRequest(), response);
      await _waitUntil(() => service.responses.isNotEmpty);
      service.responses.single.controller.add(<int>[1, 2, 3]);
      await pumpEventQueue();
      service.responses.single.controller
          .addError(StateError('the pack failed'));

      await serving;
      expect(response.bytes, <int>[1, 2, 3]);
      expect(response.writeError.toString(), contains('the pack failed'));
      expect(response.aborted, isTrue);
      expect(response.closed, isFalse);
    });

    test('cancels the response when the client disconnects', () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..holdResponseOpen = true;
      final ClientGoneResponse response = ClientGoneResponse();

      final Future<void> serving =
          _exchange(RecordingResolver().handler(service: service))
              .serve(_postRequest(), response);
      await _waitUntil(() => service.responses.isNotEmpty);
      final FakeServiceResponse serviceResponse = service.responses.single;
      serviceResponse.controller.add(<int>[1, 2, 3]);
      await response.firstChunk.future;

      await serving;
      await serviceResponse.cancelled.timeout(const Duration(seconds: 5));
      expect(serviceResponse.cancelCalls, greaterThan(0));
      expect(response.aborted, isTrue);
      expect(response.closed, isFalse);
    });
  });

  group('DartIoExchange backpressure', () {
    test('leaves the request body unread while the service ignores it',
        () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..readRequestBody = false;
      final RecordingBody body = RecordingBody();
      final RecordingDartIoResponse response = RecordingDartIoResponse();

      await _exchange(RecordingResolver().handler(service: service))
          .serve(_postRequest(body: body), response);

      expect(response.statusCode, 200);
      expect(response.closed, isTrue);
      expect(body.listened, isFalse);
      body.add(<int>[1, 2, 3]);
      await pumpEventQueue();
      expect(body.deliveredBytes, 0);
    });

    test('produces the response body at the pace of the response sink',
        () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..holdResponseOpen = true;
      final PausedDartIoResponse response = PausedDartIoResponse();

      final Future<void> serving =
          _exchange(RecordingResolver().handler(service: service))
              .serve(_postRequest(), response);
      await _waitUntil(() => service.responses.isNotEmpty);
      final FakeServiceResponse serviceResponse = service.responses.single;

      serviceResponse.controller.add(<int>[1]);
      await response.firstChunk.future;
      expect(serviceResponse.bodyPaused, isTrue);

      serviceResponse.controller.add(<int>[2]);
      await pumpEventQueue();
      expect(
          response.received,
          <List<int>>[
            <int>[1]
          ],
          reason: 'nothing is written while the sink is paused');

      response.resume();
      await pumpEventQueue();
      expect(response.received, <List<int>>[
        <int>[1],
        <int>[2],
      ]);

      await serviceResponse.controller.close();
      await serving;
      expect(response.closed, isTrue);
    });
  });

  group('DartIoExchange full duplex', () {
    test('interleaves a large request with its response', () async {
      const int requestBytes = 2 * 1024 * 1024;
      const int chunkBytes = 64 * 1024;
      final Uint8List request = _pseudoRandomBytes(requestBytes);
      final StreamController<List<int>> requestBody =
          StreamController<List<int>>();
      addTearDown(requestBody.close);

      final InterlockedUploadPackService service =
          InterlockedUploadPackService();
      final FirstChunkResponse response = FirstChunkResponse();

      final Future<void> serving = _exchange(
        GitSmartHttpHandler(
          resolveRepository: (List<String> segments) =>
              segments.length == 1 && segments.single == repoId.value
                  ? repoId
                  : null,
          authorizationPolicy: FakeGitAuthorizationPolicy(),
          uploadPack: service,
          maxBodyBytes: 64 * 1024 * 1024,
        ),
      ).serve(
        _postRequest(body: requestBody.stream),
        response,
      );

      requestBody.add(
        Uint8List.sublistView(request, 0, chunkBytes),
      );
      await response.firstChunk.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw StateError(
          'no response byte arrived while the request was still open',
        ),
      );
      expect(
        requestBody.isClosed,
        isFalse,
        reason: 'the response starts before the request body ends',
      );

      for (var offset = chunkBytes;
          offset < requestBytes;
          offset += chunkBytes) {
        requestBody.add(Uint8List.sublistView(
          request,
          offset,
          offset + chunkBytes > requestBytes
              ? requestBytes
              : offset + chunkBytes,
        ));
      }
      await requestBody.close();
      await serving.timeout(const Duration(seconds: 30));

      expect(response.bytes.length, requestBytes);
      expect(_isShiftOf(response.bytes, request), isTrue);
      expect(response.closed, isTrue);
    });
  });
}

/// Runs [handler] with the default test authenticator.
DartIoExchange<FakeDartIoRequest> _exchange(
  GitSmartHttpHandler handler, {
  FutureOr<GitPrincipal?> Function(DartIoRequest request)? authenticate,
}) {
  return DartIoExchange<FakeDartIoRequest>(
    handler: handler,
    authenticate: (DartIoRequest request) {
      if (authenticate == null) {
        return null;
      }
      return authenticate(request);
    },
  );
}

/// A POST to the upload-pack endpoint with the usual content type.
FakeDartIoRequest _postRequest({
  Map<String, List<String>> headers = const <String, List<String>>{},
  Stream<List<int>>? body,
}) {
  return FakeDartIoRequest(
    method: 'POST',
    path: '/repo/git-upload-pack',
    headers: GitHttpHeaders(<String, List<String>>{
      'Content-Type': <String>['application/x-git-upload-pack-request'],
      ...headers,
    }),
    body: body,
  );
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
