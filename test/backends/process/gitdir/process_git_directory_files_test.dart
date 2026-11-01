import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/memory_working_repository.dart';
import '../support/scripted_git_runner.dart';

/// [GitDirectoryFiles] over the injected file system: capture, drift and
/// restore of a synthetic git directory, and the derivation of its location
/// when git can no longer read it.
///
/// Every scenario runs with the Windows and the POSIX path spelling, on any
/// machine, and never touches a disk.
void main() {
  final List<GitPlatform> platforms = <GitPlatform>[
    GitPlatform.windows,
    GitPlatform.linux,
  ];
  for (final GitPlatform platform in platforms) {
    group('GitDirectoryFiles with ${platform.operatingSystem.name} paths', () {
      late MemoryGitFileSystem fileSystem;
      late ScriptedGitRunner runner;
      late ProcessGitWorkingRepository repository;
      late String gitDirectory;

      /// Joins [relative] onto [base] with this group's path spelling.
      String joinPath(String base, String relative) =>
          platform.pathStyle.join(base, relative);

      setUp(() {
        fileSystem = MemoryGitFileSystem();
        runner = ScriptedGitRunner();
        repository = memoryWorkingRepository(
          runner,
          fileSystem,
          platform: platform,
        );
        gitDirectory = joinPath(repository.path, '.git');
      });

      /// The platform path of [relative] inside the git directory.
      String gitPath(String relative) => joinPath(gitDirectory, relative);

      void seedGitFile(String relative, String content) {
        fileSystem.seedFile(gitPath(relative), utf8.encode(content));
      }

      void answerGitDirectory() {
        runner.replyTo(
          const <String>['rev-parse', '--absolute-git-dir'],
          GitRunResult.fromStrings(gitDirectory),
        );
      }

      test('captures every regular file by forward-slash relative path',
          () async {
        seedGitFile('HEAD', 'ref: refs/heads/main\n');
        seedGitFile('config', '[core]\n\trepositoryformatversion = 0\n');
        seedGitFile('refs/heads/main', 'aa\n');
        answerGitDirectory();

        final GitDirectorySnapshot snapshot =
            await repository.gitDirectoryFiles.capture();

        expect(
          snapshot.files.keys,
          containsAll(<String>['HEAD', 'config', 'refs/heads/main']),
        );
        expect(
          snapshot.files['config'],
          utf8.encode('[core]\n\trepositoryformatversion = 0\n'),
        );
        for (final String path in snapshot.files.keys) {
          expect(path, isNot(contains('\\')));
          expect(path, isNot(startsWith('/')));
        }
      });

      test('reports modified, added and deleted files one by one', () async {
        seedGitFile('HEAD', 'ref: refs/heads/main\n');
        seedGitFile('config', '[core]\n');
        seedGitFile('refs/heads/main', 'aa\n');
        answerGitDirectory();
        final GitDirectorySnapshot before =
            await repository.gitDirectoryFiles.capture();

        seedGitFile('config', '[core]\n\tbare = false\n');
        seedGitFile('description', 'a new file\n');
        await fileSystem.deleteDirectory(gitPath('refs'), recursive: true);

        final GitDirectoryDrift drift =
            await repository.gitDirectoryFiles.drift(before);

        expect(drift.modified, <String>['config']);
        expect(drift.added, <String>['description']);
        expect(drift.deleted, <String>['refs/heads/main']);
      });

      test('restores captured files verbatim and creates missing parents',
          () async {
        seedGitFile('HEAD', 'ref: refs/heads/main\n');
        seedGitFile('config', '[core]\n');
        seedGitFile('refs/heads/main', 'aa\n');
        answerGitDirectory();
        final GitDirectorySnapshot snapshot =
            await repository.gitDirectoryFiles.capture();

        seedGitFile('config', '[core]\n\tbare = false\n');
        seedGitFile('kept.txt', 'not captured\n');
        await fileSystem.deleteDirectory(gitPath('refs'), recursive: true);

        final List<String> restored =
            await repository.gitDirectoryFiles.restore(snapshot);

        expect(restored, <String>['config', 'refs/heads/main']);
        expect(
          fileSystem.fileContent(gitPath('config')),
          utf8.encode('[core]\n'),
        );
        expect(
          fileSystem.fileContent(gitPath('refs/heads/main')),
          utf8.encode('aa\n'),
          reason: 'a deleted captured file is written back with its parents',
        );
        expect(
          fileSystem.fileContent(gitPath('kept.txt')),
          utf8.encode('not captured\n'),
          reason: 'a file the capture does not hold is kept',
        );
        expect(
          await repository.gitDirectoryFiles.restore(snapshot),
          isEmpty,
          reason: 'restoring is safe to repeat',
        );
      });

      test('derives the git directory from the .git directory when git fails',
          () async {
        seedGitFile('HEAD', 'ref: refs/heads/main\n');
        runner.failWith(
          const <String>['rev-parse', '--absolute-git-dir'],
          GitException('damaged HEAD'),
        );

        final GitDirectorySnapshot snapshot =
            await repository.gitDirectoryFiles.capture();

        expect(snapshot.files.keys, contains('HEAD'));
        expect(
          runner.requests,
          hasLength(1),
          reason: 'the capture never retries git once it failed',
        );
      });

      test('derives the git directory from a relative .git pointer', () async {
        final String dotGit = joinPath(repository.path, '.git');
        final String target = joinPath(repository.path, 'actual-git');
        fileSystem.seedFile(dotGit, utf8.encode('gitdir: actual-git\n'));
        fileSystem.seedFile(
          joinPath(target, 'HEAD'),
          utf8.encode('ref: refs/heads/main\n'),
        );
        runner.failWith(
          const <String>['rev-parse', '--absolute-git-dir'],
          GitException('damaged HEAD'),
        );

        final GitDirectorySnapshot snapshot =
            await repository.gitDirectoryFiles.capture();

        expect(snapshot.files.keys, contains('HEAD'));
      });

      test('derives the git directory from an absolute .git pointer', () async {
        final String target = platform.pathStyle.isWindows
            ? r'C:\elsewhere\gitdir'
            : '/elsewhere/gitdir';
        final String dotGit = joinPath(repository.path, '.git');
        fileSystem.seedFile(dotGit, utf8.encode('gitdir: $target\n'));
        fileSystem.seedFile(
          joinPath(target, 'HEAD'),
          utf8.encode('ref: refs/heads/main\n'),
        );
        runner.failWith(
          const <String>['rev-parse', '--absolute-git-dir'],
          GitException('damaged HEAD'),
        );

        final GitDirectorySnapshot snapshot =
            await repository.gitDirectoryFiles.capture();

        expect(snapshot.files.keys, contains('HEAD'));
      });
    });
  }
}
