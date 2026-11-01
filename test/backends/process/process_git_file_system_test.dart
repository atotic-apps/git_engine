@Tags(['git'])
library;

import 'dart:io';

import 'package:test/test.dart';

import 'git_file_system_contract.dart';
import 'support/test_repository.dart';

void main() {
  group('ProcessGitFileSystem', () {
    group('shared contract', () {
      defineGitFileSystemContract(() async {
        final Directory root =
            await Directory.systemTemp.createTemp('git_engine_fs_contract_');
        addTearDown(() => TestRepository.deleteRecursively(root));
        return FileSystemCase(
          fileSystem: const ProcessGitFileSystem(),
          root: root.path,
          separator: Platform.pathSeparator,
        );
      });
    });

    test('createTemporaryDirectory names carry the prefix', () async {
      final ProcessGitFileSystem fileSystem = const ProcessGitFileSystem();

      final String temporary = await fileSystem.createTemporaryDirectory(
        'git_engine_prefix_',
      );
      addTearDown(() => TestRepository.deleteRecursively(Directory(temporary)));

      expect(
        temporary
            .split(Platform.pathSeparator)
            .where((String segment) => segment.isNotEmpty)
            .last,
        startsWith('git_engine_prefix_'),
      );
    });
  });
}
