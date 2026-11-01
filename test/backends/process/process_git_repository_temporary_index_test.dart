import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/memory_working_repository.dart';
import 'support/scripted_git_runner.dart';

/// [ProcessGitRepository.withTemporaryIndex] creating its index in the
/// injected file system and deleting its temporary directory after success
/// and after every error.
///
/// Every scenario runs with the Windows and the POSIX path spelling, on any
/// machine, and never touches a disk.
void main() {
  final List<GitPlatform> platforms = <GitPlatform>[
    GitPlatform.windows,
    GitPlatform.linux,
  ];
  for (final GitPlatform platform in platforms) {
    group('withTemporaryIndex with ${platform.operatingSystem.name} paths', () {
      late MemoryGitFileSystem fileSystem;
      late ScriptedGitRunner runner;
      late ProcessGitWorkingRepository repository;
      late String sandbox;
      late String indexFile;

      setUp(() {
        fileSystem = MemoryGitFileSystem();
        runner = ScriptedGitRunner();
        repository = memoryWorkingRepository(
          runner,
          fileSystem,
          platform: platform,
        );
        sandbox = '/tmp/git_engine_temporary_index_1';
        indexFile = platform.pathStyle.join(sandbox, 'index');
      });

      test('deletes the temporary index after success', () async {
        runner.replyTo(
          const <String>['read-tree', '--empty'],
          GitRunResult.fromStrings(''),
        );
        String? seenIndex;

        final int result = await repository.withTemporaryIndex<int>(
          (GitWorkingRepository indexed) async {
            final ProcessGitRepository process =
                indexed as ProcessGitRepository;
            seenIndex = process.context.environment['GIT_INDEX_FILE'];
            expect(fileSystem.hasDirectory(sandbox), isTrue);
            return 7;
          },
        );

        expect(result, 7);
        expect(
          seenIndex,
          indexFile,
          reason: 'the index lives in the temporary directory',
        );
        expect(fileSystem.hasDirectory(sandbox), isFalse);
        expect(fileSystem.hasFile(indexFile), isFalse);
      });

      test('deletes the temporary index when the action throws', () async {
        runner.replyTo(
          const <String>['read-tree', '--empty'],
          GitRunResult.fromStrings(''),
        );

        await expectLater(
          repository.withTemporaryIndex<void>(
            (GitWorkingRepository indexed) async {
              throw StateError('action failed');
            },
          ),
          throwsA(isA<StateError>()),
        );

        expect(fileSystem.hasDirectory(sandbox), isFalse);
      });

      test('deletes the temporary index when read-tree fails', () async {
        runner.failWith(
          const <String>['read-tree', '--empty'],
          GitCommandException(
            arguments: const <String>['read-tree', '--empty'],
            exitCode: 128,
            stderr: 'fatal: not a git repository',
          ),
        );

        await expectLater(
          repository.withTemporaryIndex<void>(
            (GitWorkingRepository indexed) async {},
          ),
          throwsA(isA<GitCommandException>()),
        );

        expect(fileSystem.hasDirectory(sandbox), isFalse);
      });
    });
  }
}
