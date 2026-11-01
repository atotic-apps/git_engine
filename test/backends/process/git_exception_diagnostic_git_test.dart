@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'support/remote_test_support.dart';
import 'support/test_repository.dart';

const String _secret = 'SECRET';

void main() {
  test('a clone failure does not leak the password in its diagnostic',
      () async {
    final TestRepository repo = await createTestRepository();
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('repository not found');
      request.response.close();
    });

    final String url =
        'http://user:$_secret@127.0.0.1:${server.port}/absent.git';

    try {
      await engineAt(repo).clone(
        url,
        TestRepository.join(repo.sandbox.path, 'absent-clone'),
      );
      fail('cloning an absent repository did not fail');
    } on GitException catch (error) {
      expect(error.diagnostic, isNotEmpty);
      expect(error.diagnostic, isNot(contains(_secret)));
    }
  });
}
