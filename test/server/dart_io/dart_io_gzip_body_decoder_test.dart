import 'dart:io' show gzip;

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/server_io.dart';
import 'package:test/test.dart';

import '../../support/fake_git_http.dart';
import '../../support/fake_upload_pack_service.dart';
import '../handler_test_helpers.dart';

void main() {
  late FakeUploadPackService service;
  late RecordingResolver resolver;

  setUp(() {
    service = FakeUploadPackService();
    resolver = RecordingResolver();
  });

  FakeGitHttpRequest postRequest(Stream<List<int>> body) {
    return FakeGitHttpRequest(
      method: 'POST',
      path: '/repo/git-upload-pack',
      headers: GitHttpHeaders(<String, List<String>>{
        'Content-Type': <String>['application/x-git-upload-pack-request'],
        'Content-Encoding': <String>['gzip'],
      }),
      body: body,
    );
  }

  test('bounds a real gzip body after decompression', () async {
    service.echoRequestBody = true;
    final List<Object> failures = <Object>[];
    final GitSmartHttpHandler handler = resolver.handler(
      service: service,
      decoder: dartIoGzipBodyDecoder,
      maxBodyBytes: 1024,
      onError: (Object error, StackTrace stackTrace) => failures.add(error),
    );
    final List<int> compressed = gzip.encode(List<int>.filled(100000, 5));
    expect(
      compressed.length,
      lessThan(1024),
      reason: 'the encoded body must pass the pre-decode limit',
    );

    final GitHttpResponse response = await handler.handle(
      postRequest(Stream<List<int>>.value(compressed)),
    );
    expect(response.status, 200);

    final CollectedBody collected = await collectBody(response.body);
    expect(collected.error, isNotNull);
    expect(collected.error.toString(), contains('limit'));
    expect(collected.bytes.length, lessThanOrEqualTo(1024));
    expect(failures, hasLength(1));
  });

  test('accepts a real gzip body decompressing exactly to the limit', () async {
    service.echoRequestBody = true;
    final GitSmartHttpHandler handler = resolver.handler(
      service: service,
      decoder: dartIoGzipBodyDecoder,
      maxBodyBytes: 1024,
    );
    final List<int> payload = List<int>.filled(1024, 5);

    final GitHttpResponse response = await handler.handle(
      postRequest(Stream<List<int>>.value(gzip.encode(payload))),
    );

    final CollectedBody collected = await collectBody(response.body);
    expect(collected.error, isNull);
    expect(collected.bytes, payload);
  });
}
