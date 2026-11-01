import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/scripted_git_runner.dart';

/// The occupied-directory guard of `init` and `initBare`, decided on the
/// injected file system: no git, no disk, no machine.
void main() {
  group('init guarded on the injected file system', () {
    late MemoryGitFileSystem fileSystem;
    late ScriptedGitRunner runner;

    setUp(() {
      fileSystem = MemoryGitFileSystem();
      runner = ScriptedGitRunner();
    });

    /// An engine whose every disk decision goes through [fileSystem] and
    /// whose every command goes through [runner].
    ProcessGitEngine build() => ProcessGitEngine(
          runner: runner,
          fileSystem: fileSystem,
          platform: GitPlatform.linux,
        );

    /// Scripts the successful `git init` on [path] and the `rev-parse` that
    /// opens it afterwards as a working repository.
    void scriptSuccessfulInit(String path) {
      runner.replyTo(
        <String>['init', '--', path],
        GitRunResult.fromStrings('Initialized empty Git repository\n'),
      );
      runner.replyTo(
        const <String>['rev-parse', '--is-bare-repository'],
        GitRunResult.fromStrings('false\n'),
      );
    }

    test('an occupied directory is refused before git runs', () async {
      fileSystem.seedDirectory('/repo');
      fileSystem.seedFile('/repo/notes.txt', utf8.encode('kept\n'));

      await expectLater(
        build().init('/repo'),
        throwsA(
          isA<GitOccupiedDirectoryException>().having(
            (GitOccupiedDirectoryException error) => error.path,
            'path',
            '/repo',
          ),
        ),
      );

      expect(
        runner.requests,
        isEmpty,
        reason: 'the refusal is decided on the injected file system, '
            'without running git',
      );
      expect(
        fileSystem.fileContent('/repo/notes.txt'),
        utf8.encode('kept\n'),
        reason: 'the refusal leaves the content untouched',
      );
    });

    test('initBare refuses an occupied directory the same way', () async {
      fileSystem.seedDirectory('/store.git');
      fileSystem.seedFile('/store.git/notes.txt', utf8.encode('kept\n'));

      await expectLater(
        build().initBare('/store.git'),
        throwsA(isA<GitOccupiedDirectoryException>()),
      );

      expect(runner.requests, isEmpty);
    });

    test('a file at the target path is left to git', () async {
      fileSystem.seedFile('/plain.txt', utf8.encode('kept\n'));
      runner.failWith(
        <String>['init', '--', '/plain.txt'],
        StateError('git refused the file'),
      );

      await expectLater(
        build().init('/plain.txt'),
        throwsA(isA<StateError>()),
        reason: 'a path that holds a file is not refused by the guard; '
            'git fails on it with its own answer',
      );

      expect(runner.requests, hasLength(1));
    });

    test('an absent directory goes straight to git', () async {
      scriptSuccessfulInit('/fresh');

      final ProcessGitWorkingRepository repository =
          await build().init('/fresh') as ProcessGitWorkingRepository;

      expect(repository, isA<ProcessGitWorkingRepository>());
      expect(
        runner.requests.first.arguments,
        <String>['init', '--', '/fresh'],
      );
    });

    test('an empty directory is accepted', () async {
      fileSystem.seedDirectory('/empty');
      scriptSuccessfulInit('/empty');

      final ProcessGitWorkingRepository repository =
          await build().init('/empty') as ProcessGitWorkingRepository;

      expect(repository, isA<ProcessGitWorkingRepository>());
      expect(
        runner.requests.first.arguments,
        <String>['init', '--', '/empty'],
      );
    });

    test('allowOccupied hands the occupied directory to git', () async {
      fileSystem.seedDirectory('/repo');
      fileSystem.seedFile('/repo/notes.txt', utf8.encode('kept\n'));
      scriptSuccessfulInit('/repo');

      final ProcessGitWorkingRepository repository = await build()
          .init('/repo', allowOccupied: true) as ProcessGitWorkingRepository;

      expect(repository, isA<ProcessGitWorkingRepository>());
      expect(
        runner.requests.first.arguments,
        <String>['init', '--', '/repo'],
      );
      expect(
        fileSystem.fileContent('/repo/notes.txt'),
        utf8.encode('kept\n'),
        reason: 'git keeps the files it finds',
      );
    });

    test('initBare with allowOccupied runs git with --bare', () async {
      fileSystem.seedDirectory('/store.git');
      fileSystem.seedFile('/store.git/notes.txt', utf8.encode('kept\n'));
      runner.replyTo(
        <String>['init', '--bare', '--', '/store.git'],
        GitRunResult.fromStrings('Initialized empty Git repository\n'),
      );
      runner.replyTo(
        const <String>['rev-parse', '--is-bare-repository'],
        GitRunResult.fromStrings('true\n'),
      );

      final ProcessGitFileBareRepository repository =
          await build().initBare('/store.git', allowOccupied: true)
              as ProcessGitFileBareRepository;

      expect(repository, isA<ProcessGitFileBareRepository>());
      expect(
        runner.requests.first.arguments,
        <String>['init', '--bare', '--', '/store.git'],
      );
    });
  });
}
