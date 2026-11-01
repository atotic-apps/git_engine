import 'dart:async';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/fake_git_http.dart';
import '../support/fake_upload_pack_service.dart';
import 'handler_test_helpers.dart';

/// A decoder that inflates any encoded body into [decodedBytes] bytes,
/// emitted in [chunkSize] chunks, and records whether it was listened to.
final class InflatingDecoder {
  /// Creates the decoder.
  InflatingDecoder({required this.decodedBytes, this.chunkSize = 1024});

  /// The number of bytes the decoder produces.
  final int decodedBytes;

  /// The largest chunk the decoder produces.
  final int chunkSize;

  /// Whether anyone listened to the stream the decoder returned.
  bool listened = false;

  /// The decoder function to hand to a handler.
  GitHttpBodyDecoder get fn {
    return (String encoding, Stream<List<int>> body) async* {
      listened = true;
      final StreamSubscription<List<int>> subscription = body.listen(
        (List<int> chunk) {},
        onError: (Object error) {},
      );
      try {
        var remaining = decodedBytes;
        while (remaining > 0) {
          final int size = remaining < chunkSize ? remaining : chunkSize;
          yield List<int>.filled(size, 7);
          remaining -= size;
        }
      } finally {
        await subscription.cancel();
      }
    };
  }
}

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

  group('GitSmartHttpHandler decoded body limit', () {
    test('fails a decoded body that grows past the limit', () async {
      service.echoRequestBody = true;
      final InflatingDecoder decoder = InflatingDecoder(decodedBytes: 100000);
      final List<Object> failures = <Object>[];
      final GitSmartHttpHandler handler = resolver.handler(
        service: service,
        decoder: decoder.fn,
        maxBodyBytes: 1024,
        onError: (Object error, StackTrace stackTrace) => failures.add(error),
      );

      final RecordingBody encoded = RecordingBody();
      final GitHttpResponse response = await handler.handle(postRequest(
        body: encoded,
        extraHeaders: <String, List<String>>{
          'Content-Encoding': <String>['gzip'],
        },
      ));
      expect(response.status, 200);

      final Future<CollectedBody> reading = collectBody(response.body);
      encoded.add(List<int>.filled(133, 1));
      final CollectedBody collected = await reading;

      expect(collected.error, isNotNull);
      expect(collected.error.toString(), contains('limit'));
      expect(collected.bytes, hasLength(1024));
      expect(failures, hasLength(1));
      expect(failures.single.toString(), contains('limit'));
    });

    test('accepts a decoded body exactly at the limit', () async {
      service.echoRequestBody = true;
      final InflatingDecoder decoder = InflatingDecoder(decodedBytes: 1024);
      final GitSmartHttpHandler handler = resolver.handler(
        service: service,
        decoder: decoder.fn,
        maxBodyBytes: 1024,
      );

      final GitHttpResponse response = await handler.handle(postRequest(
        body: Stream<List<int>>.value(List<int>.filled(133, 1)),
        extraHeaders: <String, List<String>>{
          'Content-Encoding': <String>['gzip'],
        },
      ));

      final CollectedBody collected = await collectBody(response.body);
      expect(collected.error, isNull);
      expect(collected.bytes, List<int>.filled(1024, 7));
    });

    test('leaves an uncompressed body unchanged', () async {
      service.echoRequestBody = true;
      final InflatingDecoder decoder = InflatingDecoder(decodedBytes: 100000);
      final GitSmartHttpHandler handler = resolver.handler(
        service: service,
        decoder: decoder.fn,
        maxBodyBytes: 1024,
      );

      final GitHttpResponse response = await handler.handle(postRequest(
        body: Stream<List<int>>.value(<int>[1, 2, 3]),
      ));

      final CollectedBody collected = await collectBody(response.body);
      expect(collected.error, isNull);
      expect(collected.bytes, <int>[1, 2, 3]);
      expect(decoder.listened, isFalse);
    });

    test('reads the decoded body only when the service asks for it', () async {
      service.readRequestBody = false;
      final InflatingDecoder decoder = InflatingDecoder(decodedBytes: 100000);
      final GitSmartHttpHandler handler = resolver.handler(
        service: service,
        decoder: decoder.fn,
        maxBodyBytes: 1024,
      );

      final RecordingBody encoded = RecordingBody();
      final GitHttpResponse response = await handler.handle(postRequest(
        body: encoded,
        extraHeaders: <String, List<String>>{
          'Content-Encoding': <String>['gzip'],
        },
      ));

      expect(response.status, 200);
      expect(decoder.listened, isFalse);
      expect(encoded.listened, isFalse);

      encoded.add(List<int>.filled(133, 1));
      await pumpEventQueue();

      expect(decoder.listened, isFalse);
      expect(encoded.listened, isFalse);
      expect(encoded.deliveredBytes, 0);
    });
  });
}
