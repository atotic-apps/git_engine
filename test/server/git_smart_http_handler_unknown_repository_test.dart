import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/fake_git_http.dart';
import '../support/fake_upload_pack_service.dart';
import 'handler_test_helpers.dart';

void main() {
  group('unknown served repository', () {
    test('a service that refuses the identifier on info/refs receives a 404',
        () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..advertiseError = GitUnknownServedRepositoryException(repoId);
      final GitSmartHttpHandler handler =
          RecordingResolver().handler(service: service);

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          method: 'GET',
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
      );

      expect(response.status, 404);
    });

    test(
        'a service that refuses the identifier on git-upload-pack receives '
        'a 404', () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..uploadPackError = GitUnknownServedRepositoryException(repoId);
      final GitSmartHttpHandler handler =
          RecordingResolver().handler(service: service);

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          method: 'POST',
          path: '/repo/git-upload-pack',
          headers: GitHttpHeaders(<String, List<String>>{
            'Content-Type': <String>['application/x-git-upload-pack-request'],
            'Content-Length': <String>['4'],
          }),
          body: Stream<List<int>>.value(Uint8List.fromList(
            <int>[0x30, 0x30, 0x30, 0x30],
          )),
        ),
      );

      expect(response.status, 404);
    });

    test('any other service failure stays a 500', () async {
      final FakeUploadPackService service = FakeUploadPackService()
        ..advertiseError = StateError('internal');
      final GitSmartHttpHandler handler =
          RecordingResolver().handler(service: service);

      final GitHttpResponse response = await handler.handle(
        FakeGitHttpRequest(
          method: 'GET',
          path: '/repo/info/refs',
          queryParameters: <String, List<String>>{
            'service': <String>['git-upload-pack'],
          },
        ),
      );

      expect(response.status, 500);
    });
  });
}
