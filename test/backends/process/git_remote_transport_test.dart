@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/src/backends/process/git_remote_location.dart';
import 'package:test/test.dart';

import 'support/remote_test_support.dart';
import 'support/test_repository.dart';

void main() {
  late TestRepository repo;
  late ProcessGitRepository repository;

  group('remote location classification', () {
    test('classifies every accepted form and tells which may use SSH', () {
      const Map<String, GitRemoteTransport> forms =
          <String, GitRemoteTransport>{
        '/repo': GitRemoteTransport.localPath,
        'C:repo': GitRemoteTransport.localPath,
        'C://repo': GitRemoteTransport.localPath,
        'file:///repo': GitRemoteTransport.file,
        'http://example.com/repo.git': GitRemoteTransport.http,
        'https://example.com/repo.git': GitRemoteTransport.https,
        'ssh://git@example.com/repo.git': GitRemoteTransport.ssh,
        'git@example.com:repo.git': GitRemoteTransport.ssh,
      };

      for (final MapEntry<String, GitRemoteTransport> form in forms.entries) {
        expect(classifyRemoteLocation(form.key), form.value);
        expect(
          transportMayUseSsh(form.value),
          form.value == GitRemoteTransport.ssh,
        );
      }
    });
  });

  setUp(() async {
    repo = await createTestRepository();
    repository = await openAt(repo);
  });

  test(
      'a global configuration allowing ext cannot widen the transports of a '
      'fetch', () async {
    await repo.sandboxFile('gitconfig-global').writeAsString(
          '[protocol "ext"]\n\tallow = always\n',
        );
    await repository.remotes.add('origin', 'ext::git upload-pack /nowhere');

    await _expectTransportRefused(
      engineAt(repo).fetch(repository, remote: 'origin'),
    );
  });

  test(
      'a repository configuration allowing ext cannot widen the transports of '
      'a fetch', () async {
    await repo.runGit(const <String>['config', 'protocol.ext.allow', 'always']);
    await repository.remotes.add('origin', 'ext::git upload-pack /nowhere');

    await _expectTransportRefused(
      engineAt(repo).fetch(repository, remote: 'origin'),
    );
  });

  test('a clone through a remote helper is refused before git runs', () async {
    final String target = TestRepository.join(
      repo.sandbox.path,
      'refused-clone',
    );

    await expectLater(
      engineAt(repo).clone('ext::git upload-pack /nowhere', target),
      throwsA(isA<GitUnsupportedUrlException>()),
    );
    expect(
      Directory(target).existsSync(),
      isFalse,
      reason: 'nothing ran, so nothing was created',
    );
  });
}

/// Expects [future] to fail with git refusing the transport.
Future<void> _expectTransportRefused(Future<void> future) async {
  final Object? failure = await _captureError(future);

  expect(failure, isA<GitCommandException>());
  final GitCommandException commandFailure = failure! as GitCommandException;
  expect(
    commandFailure.stderr.toLowerCase(),
    contains('not allowed'),
    reason: 'the bounding environment outranks the allowed ext transport',
  );
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
