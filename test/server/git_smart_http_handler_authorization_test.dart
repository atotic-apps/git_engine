import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/fake_git_http.dart';
import '../support/fake_upload_pack_service.dart';
import 'handler_test_helpers.dart';

void main() {
  group('GitSmartHttpHandler authorization', () {
    late FakeUploadPackService service;

    setUp(() {
      service = FakeUploadPackService();
    });

    test('answers 401 with the challenge for a refused anonymous request',
        () async {
      final GitSmartHttpHandler handler = buildHandler(
        resolveRepository: (List<String> segments) => repoId,
        policy: FakeGitAuthorizationPolicy(
          onCanRead: (GitPrincipal? principal) => false,
        ),
        service: service,
        challenge: 'Basic realm="git"',
      );

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
      );

      expect(response.status, 401);
      expect(
        response.headers.firstValue('www-authenticate'),
        'Basic realm="git"',
      );
      expect(service.advertiseCalls, isEmpty);
    });

    test('answers 403 for a refused anonymous request without a challenge',
        () async {
      final GitSmartHttpHandler handler = buildHandler(
        resolveRepository: (List<String> segments) => repoId,
        policy: FakeGitAuthorizationPolicy(
          onCanRead: (GitPrincipal? principal) => false,
        ),
        service: service,
      );

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
      );

      expect(response.status, 403);
      expect(response.headers.contains('www-authenticate'), isFalse);
    });

    test('answers 403 for a refused identity, challenge aside', () async {
      final GitSmartHttpHandler handler = buildHandler(
        resolveRepository: (List<String> segments) => repoId,
        policy: FakeGitAuthorizationPolicy(
          onCanRead: (GitPrincipal? principal) =>
              principal != null && principal.name == 'ada',
        ),
        service: service,
        challenge: 'Basic realm="git"',
      );

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          method: 'POST',
          path: '/repo/git-upload-pack',
          headers: GitHttpHeaders(<String, List<String>>{
            'Content-Type': <String>['application/x-git-upload-pack-request'],
          }),
        ),
        principal: const FakeGitPrincipal('mallory'),
      );

      expect(response.status, 403);
      expect(response.headers.contains('www-authenticate'), isFalse);
      expect(service.uploadCalls, isEmpty);
    });

    test('lets the policy decide asynchronously', () async {
      final GitSmartHttpHandler handler = buildHandler(
        resolveRepository: (List<String> segments) => repoId,
        policy: FakeGitAuthorizationPolicy(
          onCanRead: (GitPrincipal? principal) async {
            await Future<void>.delayed(Duration.zero);
            return true;
          },
        ),
        service: service,
      );

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
      );

      expect(response.status, 200);
    });

    test('answers 500 when the policy fails, without running the service',
        () async {
      final GitSmartHttpHandler handler = buildHandler(
        resolveRepository: (List<String> segments) => repoId,
        policy: FakeGitAuthorizationPolicy(
          onCanRead: (GitPrincipal? principal) =>
              throw StateError('policy broke: secret git stderr'),
        ),
        service: service,
      );

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
      );

      expect(response.status, 500);
      final CollectedBody body = await collectBody(response.body);
      expect(body.bytes, isEmpty);
      expect(body.error, isNull);
      expect(service.advertiseCalls, isEmpty);
    });
  });
}
