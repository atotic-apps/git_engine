@Tags(['git'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:git_engine/src/backends/process/git_command_timeout_exception.dart';
import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/test_repository.dart';

void main() {
  group('ProcessGitRunner.run', () {
    late TestRepository repo;

    setUp(() async {
      repo = await createTestRepository();
    });

    test('decodes UTF-8 output: accented commit message and file name',
        () async {
      repo.writeFile('fichîer_àccentuë.txt', 'contenu ünïcode\n');
      await repo.runGit(const <String>['add', '.']);
      const String message = 'Message açcentué — éàü';
      await repo.runGit(<String>['commit', '-m', message]);

      final GitRunResult log =
          await repo.runGit(const <String>['log', '-1', '--format=%B']);
      expect(log.stdout.trim(), message);

      final GitRunResult files = await repo.runGit(const <String>['ls-files']);
      expect(files.stdout.trim().split('\n'), contains('fichîer_àccentuë.txt'));
    });

    test('throws GitCommandException with stderr on a non-zero exit', () async {
      await expectLater(
        repo.runGit(const <String>['rev-parse', 'not-a-real-ref']),
        throwsA(isA<GitCommandException>()
            .having((GitCommandException e) => e.exitCode, 'exitCode', isNot(0))
            .having((GitCommandException e) => e.stderr, 'stderr',
                contains('fatal'))
            .having((GitCommandException e) => e.arguments, 'arguments',
                contains('not-a-real-ref'))
            .having((GitCommandException e) => e.workingDirectory,
                'workingDirectory', repo.directory.path)),
      );
    });

    test('throws GitExecutableNotFoundException when git is missing', () async {
      final String missing = TestRepository.join(
        repo.sandbox.path,
        Platform.isWindows ? 'no-such-git.exe' : 'no-such-git',
      );
      final ProcessGitRunner runner = ProcessGitRunner(executable: missing);

      await expectLater(
        runner.run(const GitRunRequest(arguments: <String>['--version'])),
        throwsA(isA<GitExecutableNotFoundException>().having(
            (GitExecutableNotFoundException e) => e.executable,
            'executable',
            missing)),
      );
    });

    test('the missing executable is an unavailable engine failure', () async {
      final String missing = TestRepository.join(
        repo.sandbox.path,
        Platform.isWindows ? 'no-such-git.exe' : 'no-such-git',
      );
      final ProcessGitRunner runner = ProcessGitRunner(executable: missing);

      Object? failure;
      try {
        await runner.run(const GitRunRequest(arguments: <String>['--version']));
      } on GitException catch (error) {
        failure = error;
      }

      expect(failure, isA<GitExecutableNotFoundException>());
      expect(failure, isA<GitEngineUnavailableException>());
      expect(failure, isA<GitException>());
      final GitExecutableNotFoundException exception =
          failure! as GitExecutableNotFoundException;
      expect(exception.executable, missing);
      expect(
        exception.message,
        startsWith('git executable not found: "$missing"'),
      );
    });

    test('a portable caller catches the missing executable', () async {
      final String missing = TestRepository.join(
        repo.sandbox.path,
        Platform.isWindows ? 'no-such-git.exe' : 'no-such-git',
      );
      final ProcessGitRunner runner = ProcessGitRunner(executable: missing);

      Object? failure;
      try {
        await runner.run(const GitRunRequest(arguments: <String>['--version']));
      } on GitEngineUnavailableException catch (error) {
        failure = error;
      }

      expect(failure, isA<GitExecutableNotFoundException>());
      expect(
        (failure! as GitExecutableNotFoundException).executable,
        missing,
      );
    });

    test('the missing executable keeps its message and executable', () {
      final GitExecutableNotFoundException withoutCause =
          GitExecutableNotFoundException('no-such-git');
      final GitExecutableNotFoundException withCause =
          GitExecutableNotFoundException('no-such-git', cause: 'spawn failed');

      expect(withoutCause.executable, 'no-such-git');
      expect(
        withoutCause.message,
        'git executable not found: "no-such-git"',
      );
      expect(withCause.executable, 'no-such-git');
      expect(
        withCause.message,
        'git executable not found: "no-such-git" (spawn failed)',
      );
      expect(withCause.spawnError, 'spawn failed');
      expect(withCause.cause, isNull);
    });

    test('throws GitTimeoutException when the delay is exceeded', () async {
      repo.writeFile('a.txt', 'a\n');
      await repo.runGit(const <String>['add', '.']);
      await repo.runGit(const <String>['commit', '-m', 'a']);

      final Stopwatch stopwatch = Stopwatch()..start();
      await expectLater(
        repo.runGit(
          const <String>['log', '--oneline', '--all'],
          timeout: Duration.zero,
        ),
        throwsA(isA<GitTimeoutException>()
            .having(
                (GitTimeoutException e) => e.timeout, 'timeout', Duration.zero)
            .having(
                (GitTimeoutException e) => e.cause,
                'cause',
                isA<GitCommandTimeoutException>().having(
                    (GitCommandTimeoutException cause) => cause.arguments,
                    'arguments',
                    contains('log')))),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
    });

    test('does not wait for child output when timing out before git exits',
        () async {
      // Single-process termination leaves the shell's output pipes open on
      // every host, even where the normal Windows tree kill would close them.
      final ProcessGitRunner runner = ProcessGitRunner(
        platform: GitPlatform.linux,
        globalEnvironment: repo.runner.globalEnvironment,
      );
      final Stopwatch stopwatch = Stopwatch()..start();
      await expectLater(
        runner.run(GitRunRequest(
          arguments: const <String>[
            '-c',
            'alias.hold=!printf ready; sleep 6',
            'hold',
          ],
          timeout: const Duration(seconds: 1),
        )),
        throwsA(isA<GitTimeoutException>()
            .having(
              (GitTimeoutException e) => e.timeout,
              'timeout',
              const Duration(seconds: 1),
            )
            .having(
              (GitTimeoutException e) =>
                  (e.cause as GitCommandTimeoutException).stdout,
              'captured stdout',
              'ready',
            )),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 4)));
    });

    test('times out when a child keeps the output open after git exits',
        () async {
      final Stopwatch stopwatch = Stopwatch()..start();
      await expectLater(
        repo.runGit(
          const <String>['-c', 'alias.auditwait=!sleep 2 &', 'auditwait'],
          timeout: const Duration(milliseconds: 400),
        ),
        throwsA(isA<GitTimeoutException>().having(
            (GitTimeoutException e) => e.timeout,
            'timeout',
            const Duration(milliseconds: 400))),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 1500)));
    });

    test(
      'reports a timeout for a descendant that may outlive git',
      () async {
        if (!Platform.isWindows) {
          return;
        }
        final Stopwatch stopwatch = Stopwatch()..start();
        await expectLater(
          repo.runGit(
            const <String>[
              '-c',
              'alias.survive=! (sleep 2; printf survived > child-survived.txt) &',
              'survive',
            ],
            timeout: const Duration(milliseconds: 400),
          ),
          throwsA(isA<GitTimeoutException>().having(
              (GitTimeoutException e) => e.timeout,
              'timeout',
              const Duration(milliseconds: 400))),
        );
        stopwatch.stop();
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
        // Known limit: the descendant may create child-survived.txt after the
        // timeout. This test does not assert that the file is absent; see the
        // GitRunRequest.timeout documentation.
      },
      skip: Platform.isWindows
          ? false
          : 'reserved to Windows: documents the taskkill /T /F limit',
    );

    test('returns the complete output when a large command finishes in time',
        () async {
      final String content = 'x' * 200000;
      repo.writeFile('large.txt', content);
      await repo.runGit(const <String>['add', '.']);
      await repo.runGit(const <String>['commit', '-m', 'large']);

      final GitRunResult result = await repo.runGit(
        const <String>['show', 'HEAD:large.txt'],
        timeout: const Duration(seconds: 30),
      );

      expect(result.stdout.length, content.length);
      expect(result.stdout, content);
    });

    test('hashes stdin bytes and closes stdin when none is given', () async {
      final File file = repo.writeFile('hello.txt', 'hello\n');
      final GitRunResult fromFile =
          await repo.runGit(<String>['hash-object', file.path]);
      final GitRunResult fromStdin = await repo.runGit(
        const <String>['hash-object', '--stdin'],
        stdin: utf8.encode('hello\n'),
      );
      final GitRunResult empty =
          await repo.runGit(const <String>['hash-object', '--stdin']);

      expect(fromStdin.stdout.trim(), fromFile.stdout.trim());
      expect(empty.stdout.trim(), 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391',
          reason: 'stdin must be closed: hash of the empty content');
    });

    test('refuses a working directory that does not exist', () {
      final ProcessGitRunner runner = ProcessGitRunner();
      final GitRunRequest request = GitRunRequest(
        arguments: const <String>['status'],
        workingDirectory: TestRepository.join(
          repo.sandbox.path,
          'does-not-exist',
        ),
      );

      expect(
        runner.run(request),
        throwsA(isA<GitException>().having((GitException e) => e.message,
            'message', contains('does-not-exist'))),
      );
    });

    test('throws GitNotARepositoryException outside of a repository', () async {
      final Directory plain =
          await Directory.systemTemp.createTemp('git_engine_norepo_');
      addTearDown(() => TestRepository.deleteRecursively(plain));
      final ProcessGitRunner runner = ProcessGitRunner();

      await expectLater(
        runner.run(GitRunRequest(
          arguments: const <String>['rev-parse', '--git-dir'],
          workingDirectory: plain.path,
        )),
        throwsA(isA<GitNotARepositoryException>().having(
            (GitNotARepositoryException e) =>
                (e.cause as GitCommandException).stderr,
            'cause stderr',
            contains('not a git repository'))),
      );
    });
  });
}
