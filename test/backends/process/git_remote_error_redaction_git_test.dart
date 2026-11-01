@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'support/remote_test_support.dart';
import 'support/test_repository.dart';

void main() {
  test('a fetch failure does not leak the userinfo of the remote URL',
      () async {
    final TestRepository repo = await createTestRepository();
    final ProcessGitRepository repository = await openAt(repo);
    final ServerSocket socket =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final int port = socket.port;
    await socket.close();
    await repository.remotes.add(
      'origin',
      'http://u:SECRET@127.0.0.1:$port/r',
    );

    final Object? failure = await _captureError(
      engineAt(repo).fetch(repository, remote: 'origin'),
    );

    expect(failure, isA<GitException>());
    expect(
      (failure! as GitException).message,
      isNot(contains('SECRET')),
    );
    expect(failure.toString(), isNot(contains('SECRET')));
  });
}

/// Captures the error [future] fails with, failing its caller otherwise.
Future<Object?> _captureError(Future<void> future) async {
  try {
    await future;
  } catch (error) {
    return error;
  }
  fail('the operation did not fail');
}
