import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the common diagnostic contract of [GitException].
///
/// The suite provokes a real engine refusal - opening a directory that is not
/// a repository - and checks that its diagnostic is usable as-is: non-empty
/// and carrying the failure's message.
void defineGitExceptionContract(BackendFactory factory) {
  group('GitException.diagnostic', () {
    late EngineSandbox sandbox;
    late GitRepositoryManager manager;

    setUp(() async {
      sandbox = await factory.createEngineSandbox();
      manager = sandbox.manager;
    });

    test('a real engine failure has a non-empty diagnostic with its message',
        () async {
      final String path = sandbox.newPath('not-a-repository');
      await Directory(path).create(recursive: true);

      try {
        await manager.open(path);
        fail('opening a plain directory did not fail');
      } on GitException catch (error) {
        expect(error.diagnostic, isNotEmpty);
        expect(error.diagnostic, contains(error.message));
      }
    });
  });
}
