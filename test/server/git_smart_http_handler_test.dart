import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/fake_git_http.dart';
import '../support/fake_upload_pack_service.dart';
import 'handler_test_helpers.dart';

void main() {
  group('GitSmartHttpHandler routing', () {
    late FakeUploadPackService service;
    late RecordingResolver resolver;

    setUp(() {
      service = FakeUploadPackService();
      resolver = RecordingResolver();
    });

    test('routes GET info/refs to advertiseRefs and frames the body', () async {
      service.cannedChunks = <List<int>>[
        <int>[1, 2, 3]
      ];
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
      );

      expect(response.status, 200);
      expect(response.headers.firstValue('content-type'),
          'application/x-git-upload-pack-advertisement');
      expect(response.headers.firstValue('cache-control'), 'no-cache');
      final CollectedBody body = await collectBody(response.body);
      expect(body.error, isNull);
      expect(
        body.bytes,
        hasLength(advertisementPrefix.length + 3),
      );
      expect(
        body.bytes.sublist(0, advertisementPrefix.length),
        advertisementPrefix,
      );
      expect(body.bytes.sublist(advertisementPrefix.length), <int>[1, 2, 3]);
      expect(resolver.calls, <List<String>>[
        <String>['repo'],
      ]);
      expect(service.advertiseCalls, hasLength(1));
      expect(service.advertiseCalls.single.repository, repoId);
      expect(service.uploadCalls, isEmpty);
    });

    test('routes POST git-upload-pack to uploadPack', () async {
      service.cannedChunks = <List<int>>[
        <int>[9, 9],
      ];
      final RecordingBody body = RecordingBody();
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          method: 'POST',
          path: '/repo/git-upload-pack',
          headers: GitHttpHeaders(<String, List<String>>{
            'Content-Type': <String>['application/x-git-upload-pack-request'],
          }),
          body: body,
        ),
      );

      expect(response.status, 200);
      expect(response.headers.firstValue('content-type'),
          'application/x-git-upload-pack-result');
      expect(response.headers.firstValue('cache-control'), 'no-cache');
      final CollectedBody collected = await collectBody(response.body);
      expect(collected.bytes, <int>[9, 9]);
      expect(service.uploadCalls, hasLength(1));
      expect(service.uploadCalls.single.repository, repoId);
      expect(identical(service.uploadCalls.single.request, body), isFalse,
          reason: 'the handler wraps the body to control it');
      expect(resolver.calls, <List<String>>[
        <String>['repo'],
      ]);
      expect(service.advertiseCalls, isEmpty);
    });

    test('refuses git-receive-pack with 403 before resolving', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      for (final FakeGitHttpRequest request in <FakeGitHttpRequest>[
        FakeGitHttpRequest(
          method: 'POST',
          path: '/repo/git-receive-pack',
          headers: GitHttpHeaders(<String, List<String>>{
            'Content-Type': <String>['application/x-git-receive-pack-request'],
          }),
        ),
        FakeGitHttpRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-receive-pack'],
          },
        ),
      ]) {
        final GitHttpResponse response = await handler.handle(request);
        expect(response.status, 403);
      }

      expect(resolver.calls, isEmpty);
      expect(service.advertiseCalls, isEmpty);
      expect(service.uploadCalls, isEmpty);
    });

    test('refuses an unknown service with 403', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-not-a-thing'],
          },
        ),
      );

      expect(response.status, 403);
      expect(resolver.calls, isEmpty);
      expect(service.advertiseCalls, isEmpty);
    });

    test('refuses a path without a protocol suffix with 400', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      for (final String path in <String>['/repo', '/repo/other', '/']) {
        final GitHttpResponse response = await handler.handle(
          FakeGitHttpRequest(path: path),
        );
        expect(response.status, 400, reason: 'path $path');
      }
      expect(resolver.calls, isEmpty);
      expect(service.advertiseCalls, isEmpty);
    });

    test('refuses the dumb protocol with 400', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse withoutParameter = await handler.handle(
        FakeGitHttpRequest(path: '/repo/info/refs'),
      );
      final GitHttpResponse emptyParameter = await handler.handle(
        FakeGitHttpRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>[''],
          },
        ),
      );

      expect(withoutParameter.status, 400);
      expect(emptyParameter.status, 400);
      expect(resolver.calls, isEmpty);
    });

    test('refuses a method that does not fit the suffix with 400', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse postInfoRefs = await handler.handle(
        FakeGitHttpRequest(
          method: 'POST',
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
      );
      final GitHttpResponse getRpc = await handler.handle(
        FakeGitHttpRequest(path: '/repo/git-upload-pack'),
      );

      expect(postInfoRefs.status, 400);
      expect(getRpc.status, 400);
      expect(resolver.calls, isEmpty);
    });

    test('refuses a POST without the protocol content type with 400', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse missing = await handler.handle(
        FakeGitHttpRequest(method: 'POST', path: '/repo/git-upload-pack'),
      );
      final GitHttpResponse wrong = await handler.handle(
        FakeGitHttpRequest(
          method: 'POST',
          path: '/repo/git-upload-pack',
          headers: GitHttpHeaders(<String, List<String>>{
            'Content-Type': <String>['text/plain'],
          }),
        ),
      );

      expect(missing.status, 400);
      expect(wrong.status, 400);
      expect(resolver.calls, isEmpty);
      expect(service.uploadCalls, isEmpty);
    });

    test('refuses an unparsable Content-Length with 400', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          method: 'POST',
          path: '/repo/git-upload-pack',
          headers: GitHttpHeaders(<String, List<String>>{
            'Content-Type': <String>['application/x-git-upload-pack-request'],
            'Content-Length': <String>['not-a-number'],
          }),
        ),
      );

      expect(response.status, 400);
      expect(service.uploadCalls, isEmpty);
    });
  });

  group('GitSmartHttpHandler path decoding', () {
    late FakeUploadPackService service;
    late RecordingResolver resolver;

    setUp(() {
      service = FakeUploadPackService();
      resolver = RecordingResolver(
        accepted: <List<String>>{
          const <String>['repo'],
          const <String>[],
          <String>['my repos', 'alphé.git'],
        },
      );
    });

    FakeGitHttpRequest advertisement(String path) {
      return FakeGitHttpRequest(
        path: path,
        queryParameters: <String, List<String>>{
          'service': <String>['git-upload-pack'],
        },
      );
    }

    test('decodes every segment exactly once', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response = await handler
          .handle(advertisement('/my%20repos/alph%C3%A9.git/info/refs'));

      expect(response.status, 200);
      expect(resolver.calls.single, <String>['my repos', 'alphé.git']);
    });

    test('passes no segments for a repository at the root', () async {
      final GitSmartHttpHandler handler = buildHandler(
        resolveRepository: (List<String> segments) {
          resolver.calls.add(segments);
          return segments.isEmpty ? repoId : null;
        },
        service: service,
      );

      final GitHttpResponse response =
          await handler.handle(advertisement('/info/refs'));

      expect(response.status, 200);
      expect(resolver.calls.single, isEmpty);
    });

    test('refuses an ambiguous path with 400 before resolving', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      const List<String> ambiguous = <String>[
        '/repo//info/refs',
        '//repo/info/refs',
        '/repo/other//deep/info/refs',
        '/repo/./info/refs',
        '/repo/../info/refs',
        '/repo/%2E/info/refs',
        '/repo/%2E%2E/info/refs',
        '/repo/a%2Fb/info/refs',
        '/repo/%00/info/refs',
        '/repo/%zz/info/refs',
        '/repo/%2/info/refs',
      ];
      for (final String path in ambiguous) {
        final GitHttpResponse response =
            await handler.handle(advertisement(path));
        expect(response.status, 400, reason: 'path $path');
      }

      expect(resolver.calls, isEmpty);
      expect(service.advertiseCalls, isEmpty);
    });

    test('answers 404 when the host serves no repository', () async {
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response =
          await handler.handle(advertisement('/unknown/info/refs'));

      expect(response.status, 404);
      expect(resolver.calls.single, <String>['unknown']);
      expect(service.advertiseCalls, isEmpty);
    });
  });

  group('GitSmartHttpHandler internal errors', () {
    late FakeUploadPackService service;
    late RecordingResolver resolver;

    setUp(() {
      service = FakeUploadPackService();
      resolver = RecordingResolver();
    });

    FakeGitHttpRequest advertisement(String path) {
      return FakeGitHttpRequest(
        path: path,
        queryParameters: <String, List<String>>{
          'service': <String>['git-upload-pack'],
        },
      );
    }

    test('answers 500 when advertiseRefs fails, without leaking its error',
        () async {
      service.advertiseError = StateError('secret git stderr');
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response =
          await handler.handle(advertisement('/repo/info/refs'));

      expect(response.status, 500);
      final CollectedBody body = await collectBody(response.body);
      expect(body.bytes, isEmpty);
      expect(body.error, isNull);
    });

    test('answers 500 when uploadPack fails, without leaking its error',
        () async {
      service.uploadPackError = StateError('secret git stderr');
      final GitSmartHttpHandler handler = resolver.handler(service: service);

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          method: 'POST',
          path: '/repo/git-upload-pack',
          headers: GitHttpHeaders(<String, List<String>>{
            'Content-Type': <String>['application/x-git-upload-pack-request'],
          }),
        ),
      );

      expect(response.status, 500);
      final CollectedBody body = await collectBody(response.body);
      expect(body.bytes, isEmpty);
      expect(body.error, isNull);
    });

    test('answers 500 when the resolver fails', () async {
      final GitSmartHttpHandler handler = buildHandler(
        resolveRepository: (List<String> segments) =>
            throw StateError('catalog down'),
        service: service,
      );

      final GitHttpResponse response =
          await handler.handle(advertisement('/repo/info/refs'));

      expect(response.status, 500);
      expect(service.advertiseCalls, isEmpty);
    });
  });
}
