@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart'
    show GitRemoteRepositoryNotFoundException;
import 'package:test/test.dart';

import 'support/test_repository.dart';
import 'support/remote_test_support.dart';

void main() {
  late TestRepository repo;
  late ProcessGitEngine engine;

  setUp(() async {
    repo = await createTestRepository();
    engine = engineAt(repo);
  });

  for (final bool bare in <bool>[false, true]) {
    test(
        '${bare ? 'cloneBare' : 'clone'} of an absent local source reports '
        'the missing repository', () async {
      final String absent = await missingDirectory(repo, 'absent source');
      final String target = await missingDirectory(repo, 'never cloned');

      await expectLater(
        bare ? engine.cloneBare(absent, target) : engine.clone(absent, target),
        throwsA(isA<GitRemoteRepositoryNotFoundException>()),
      );
      expect(Directory(target).existsSync(), isFalse);
    });
  }
}
