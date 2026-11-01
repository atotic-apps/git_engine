import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/fake_git_http.dart';
import '../support/fake_upload_pack_service.dart';
import 'handler_test_helpers.dart';

void main() {
  late FakeUploadPackService service;
  late RecordingResolver resolver;

  setUp(() {
    service = FakeUploadPackService();
    resolver = RecordingResolver();
  });

  FakeGitHttpRequest postRequest({
    Stream<List<int>>? body,
    Map<String, List<String>> extraHeaders = const <String, List<String>>{},
  }) {
    return FakeGitHttpRequest(
      method: 'POST',
      path: '/repo/git-upload-pack',
      headers: GitHttpHeaders(<String, List<String>>{
        'Content-Type': <String>['application/x-git-upload-pack-request'],
        ...extraHeaders,
      }),
      body: body,
    );
  }

  group('GitSmartHttpHandler protocol negotiation', () {
    test('passes the Git-Protocol header to advertiseRefs', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      await handler.handle(
        FakeGitHttpRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
          headers: GitHttpHeaders(<String, List<String>>{
            'Git-Protocol': <String>['version=2'],
          }),
        ),
      );

      expect(service.advertiseCalls.single.protocol.version, 2);
      expect(service.advertiseCalls.single.protocol.entries,
          <String>['version=2']);
    });

    test('merges repeated and comma-separated values in order', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      await handler.handle(postRequest(
        extraHeaders: <String, List<String>>{
          'Git-Protocol': <String>['version=2', 'agent=unit/1,side-band-64k'],
        },
      ));

      expect(service.uploadCalls.single.protocol.version, 2);
      expect(
        service.uploadCalls.single.protocol.entries,
        <String>['version=2', 'agent=unit/1', 'side-band-64k'],
      );
    });

    test('reports version 0 without the header', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      await handler.handle(
        FakeGitHttpRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
      );

      expect(service.advertiseCalls.single.protocol.version, 0);
      expect(service.advertiseCalls.single.protocol.entries, isEmpty);
    });
  });

  group('GitSmartHttpHandler decompression', () {
    test('decompresses the body exactly once, on the encoded bytes', () async {
      service.echoRequestBody = true;
      final RecordingDecoder decoder = RecordingDecoder(<String>{'gzip'});
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, decoder: decoder.fn);

      final List<int> payload = utf8.encode('pack negotiation payload');
      final List<int> compressed = gzip.encode(payload);
      final GitHttpResponse response = await handler.handle(postRequest(
        body: Stream<List<int>>.value(compressed),
        extraHeaders: <String, List<String>>{
          'Content-Encoding': <String>['gzip'],
          'Content-Length': <String>['${compressed.length}'],
        },
      ));

      final CollectedBody collected = await collectBody(response.body);
      expect(collected.error, isNull);
      expect(collected.bytes, payload);
      expect(decoder.calls, <String>['gzip']);
    });

    test('leaves an identity body alone', () async {
      service.echoRequestBody = true;
      final RecordingDecoder decoder = RecordingDecoder(<String>{'gzip'});
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, decoder: decoder.fn);

      final GitHttpResponse response = await handler.handle(postRequest(
        body: Stream<List<int>>.value(<int>[1, 2, 3]),
        extraHeaders: <String, List<String>>{
          'Content-Encoding': <String>['identity'],
        },
      ));

      final CollectedBody collected = await collectBody(response.body);
      expect(collected.bytes, <int>[1, 2, 3]);
      expect(decoder.called, isFalse);
    });
  });

  group('GitSmartHttpHandler body limit', () {
    test('answers 413 on Content-Length without reading the body', () async {
      final RecordingBody body = RecordingBody();
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxBodyBytes: 10);

      final GitHttpResponse response = await handler.handle(postRequest(
        body: body,
        extraHeaders: <String, List<String>>{
          'Content-Length': <String>['11'],
        },
      ));

      expect(response.status, 413);
      expect(body.listened, isFalse);
      expect(service.uploadCalls, isEmpty);
    });

    test('accepts a Content-Length equal to the limit', () async {
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxBodyBytes: 10);

      final GitHttpResponse response = await handler.handle(postRequest(
        body: Stream<List<int>>.value(List<int>.filled(10, 7)),
        extraHeaders: <String, List<String>>{
          'Content-Length': <String>['10'],
        },
      ));

      expect(response.status, 200);
    });

    test('fails a body that grows past the limit while it streams', () async {
      final List<Object> failures = <Object>[];
      final GitSmartHttpHandler handler = resolver.handler(
        service: service,
        maxBodyBytes: 10,
        onError: (Object error, StackTrace stackTrace) => failures.add(error),
      );
      service.echoRequestBody = true;

      final RecordingBody body = RecordingBody();
      final GitHttpResponse response = await handler.handle(postRequest(
        body: body,
      ));
      expect(response.status, 200);

      final Completer<Object?> finished = Completer<Object?>();
      final List<int> received = <int>[];
      response.body.listen(
        received.addAll,
        onError: (Object error) {
          if (!finished.isCompleted) {
            finished.complete(error);
          }
        },
        onDone: () {
          if (!finished.isCompleted) {
            finished.complete(null);
          }
        },
      );

      body.add(List<int>.filled(6, 1));
      await pumpEventQueue();
      expect(received, List<int>.filled(6, 1));

      body.add(List<int>.filled(6, 2));
      final Object? delivered = await finished.future;
      await pumpEventQueue();

      expect(delivered, isNotNull);
      expect(delivered.toString(), contains('limit'));
      expect(received, hasLength(6));
      expect(failures, hasLength(1));
      expect(failures.single.toString(), contains('limit'));
    });
  });

  group('GitSmartHttpHandler unsupported encoding', () {
    test('answers 415 without any decoder', () async {
      final RecordingBody body = RecordingBody();
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response = await handler.handle(postRequest(
        body: body,
        extraHeaders: <String, List<String>>{
          'Content-Encoding': <String>['gzip'],
        },
      ));

      expect(response.status, 415);
      expect(body.listened, isFalse);
      expect(service.uploadCalls, isEmpty);
    });

    test('answers 415 when the decoder refuses the encoding', () async {
      final RecordingDecoder decoder = RecordingDecoder(<String>{'gzip'});
      final RecordingBody body = RecordingBody();
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, decoder: decoder.fn);

      final GitHttpResponse response = await handler.handle(postRequest(
        body: body,
        extraHeaders: <String, List<String>>{
          'Content-Encoding': <String>['deflate'],
        },
      ));

      expect(response.status, 415);
      expect(decoder.calls, <String>['deflate']);
      expect(body.listened, isFalse);
      expect(service.uploadCalls, isEmpty);
    });
  });

  group('GitSmartHttpHandler backpressure', () {
    test('leaves the request body suspended while the service ignores it',
        () async {
      service.readRequestBody = false;
      final RecordingBody body = RecordingBody();
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response = await handler.handle(postRequest(
        body: body,
      ));

      expect(response.status, 200);
      expect(body.listened, isFalse);
      body.add(<int>[1, 2, 3]);
      await pumpEventQueue();
      expect(body.listened, isFalse);
      expect(body.deliveredBytes, 0);
    });

    test('produces the response body at the pace of the adapter', () async {
      service.holdResponseOpen = true;
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response = await handler.handle(postRequest());

      final List<List<int>> received = <List<int>>[];
      final StreamSubscription<List<int>> subscription =
          response.body.listen(received.add);

      service.responses.single.controller.add(<int>[1]);
      await pumpEventQueue();
      expect(received, <List<int>>[
        <int>[1]
      ]);

      subscription.pause();
      await pumpEventQueue();
      expect(service.responses.single.bodyPaused, isTrue);

      service.responses.single.controller.add(<int>[2]);
      await pumpEventQueue();
      expect(
          received,
          <List<int>>[
            <int>[1]
          ],
          reason: 'nothing is produced while the adapter is paused');

      subscription.resume();
      await pumpEventQueue();
      expect(
        received,
        <List<int>>[
          <int>[1],
          <int>[2]
        ],
      );
      await subscription.cancel();
      await service.responses.single.cancelled;
    });
  });

  group('GitSmartHttpHandler cancellation', () {
    test('propagates the cancellation of an advertisement', () async {
      service.holdResponseOpen = true;
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
      );

      final StreamSubscription<List<int>> subscription =
          response.body.listen((List<int> chunk) {});
      await pumpEventQueue();
      await subscription.cancel();

      await service.responses.single.cancelled;
      expect(service.responses.single.cancelCalls, 1);
    });

    test(
        'propagates the cancellation of a response to the service and the '
        'request body', () async {
      service.echoRequestBody = true;
      final RecordingBody body = RecordingBody();
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response =
          await handler.handle(postRequest(body: body));

      final List<List<int>> received = <List<int>>[];
      final StreamSubscription<List<int>> subscription =
          response.body.listen(received.add);
      body.add(<int>[1]);
      await pumpEventQueue();
      expect(received, <List<int>>[
        <int>[1]
      ]);

      await subscription.cancel();
      await service.responses.single.cancelled;
      await pumpEventQueue();

      expect(service.responses.single.cancelCalls, 1);
      expect(body.cancelled, isTrue);
    });
  });

  group('GitSmartHttpHandler errors after the headers', () {
    test('interrupts the response and reports the error to the host', () async {
      service.echoRequestBody = true;
      final List<Object> failures = <Object>[];
      final GitSmartHttpHandler handler = resolver.handler(
        service: service,
        onError: (Object error, StackTrace stackTrace) => failures.add(error),
      );

      final RecordingBody body = RecordingBody();
      final GitHttpResponse response =
          await handler.handle(postRequest(body: body));

      final Completer<Object?> finished = Completer<Object?>();
      final List<int> received = <int>[];
      response.body.listen(
        received.addAll,
        onError: (Object error) {
          if (!finished.isCompleted) {
            finished.complete(error);
          }
        },
        onDone: () {
          if (!finished.isCompleted) {
            finished.complete(null);
          }
        },
      );

      body.add(<int>[1, 2, 3]);
      await pumpEventQueue();
      expect(received, <int>[1, 2, 3]);

      final Object failure = StateError('the exchange blew up: secret');
      body.addError(failure);
      final Object? delivered = await finished.future;
      await pumpEventQueue();

      expect(delivered, same(failure));
      expect(failures, hasLength(1));
      expect(failures.single, same(failure));
      expect(utf8.decode(received), isNot(contains('secret')));
    });

    test('interrupts the response when the service fails mid-flight', () async {
      service.holdResponseOpen = true;
      final List<Object> failures = <Object>[];
      final GitSmartHttpHandler handler = resolver.handler(
        service: service,
        onError: (Object error, StackTrace stackTrace) => failures.add(error),
      );

      final GitHttpResponse response = await handler.handle(postRequest());

      final Completer<Object?> finished = Completer<Object?>();
      final List<int> received = <int>[];
      response.body.listen(
        received.addAll,
        onError: (Object error) {
          if (!finished.isCompleted) {
            finished.complete(error);
          }
        },
        onDone: () {
          if (!finished.isCompleted) {
            finished.complete(null);
          }
        },
      );

      final Object failure = StateError('secret git stderr');
      service.responses.single.completeWith(
        <List<int>>[
          <int>[1, 2]
        ],
        error: failure,
      );
      final Object? delivered = await finished.future;
      await pumpEventQueue();

      expect(delivered, same(failure));
      expect(received, <int>[1, 2]);
      expect(failures.single, same(failure));
    });
  });

  test('refuses a non-positive body limit', () {
    expect(
      () => buildHandler(service: service, maxBodyBytes: 0),
      throwsArgumentError,
    );
  });
}
