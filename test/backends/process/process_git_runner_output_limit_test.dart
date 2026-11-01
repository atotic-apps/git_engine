@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/test_repository.dart';

void main() {
  group('ProcessGitRunner output limit', () {
    late TestRepository repo;

    setUp(() async {
      repo = await createTestRepository();
      repo.writeFile('a.txt', 'a\n');
      await repo.runGit(const <String>['add', '.']);
      await repo.runGit(const <String>['commit', '-m', 'a']);
    });

    test('stops a real command whose output exceeds the limit', () async {
      for (var index = 0; index < 20; index++) {
        await repo.runGit(<String>[
          'tag',
          'release-${index.toString().padLeft(3, '0')}',
        ]);
      }
      final GitRunResult all = await repo.runGit(const <String>['tag']);
      expect(all.stdoutBytes.length, greaterThan(100));

      final Stopwatch stopwatch = Stopwatch()..start();
      await expectLater(
        repo.runGit(const <String>['tag'], maxOutputBytes: 100),
        throwsA(
          isA<GitOutputLimitException>()
              .having(
                (GitOutputLimitException error) => error.limit,
                'limit',
                100,
              )
              .having(
                (GitOutputLimitException error) => error.message,
                'message',
                isNot(contains('release-')),
              ),
        ),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));

      final GitRunResult after = await repo.runGit(const <String>['tag']);
      expect(after.stdoutBytes, all.stdoutBytes);
    });

    test('kills a command that keeps producing output', () async {
      final Stopwatch stopwatch = Stopwatch()..start();
      await expectLater(
        repo.runGit(
          const <String>[
            '-c',
            'alias.flood=!while true; do printf flood; done',
            'flood',
          ],
          maxOutputBytes: 1024,
        ),
        throwsA(isA<GitOutputLimitException>()),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));

      final GitRunResult after =
          await repo.runGit(const <String>['rev-parse', 'HEAD']);
      expect(after.stdout.trim(), hasLength(40));
    });

    test('accepts output exactly at the limit', () async {
      final GitRunResult plain =
          await repo.runGit(const <String>['rev-parse', 'HEAD']);
      final int size = plain.stdoutBytes.length;

      final GitRunResult exact = await repo.runGit(
        const <String>['rev-parse', 'HEAD'],
        maxOutputBytes: size,
      );

      expect(exact.stdoutBytes, plain.stdoutBytes);
    });

    test('the request limit takes precedence over the runner default',
        () async {
      final GitRunResult plain =
          await repo.runGit(const <String>['rev-parse', 'HEAD']);
      final int size = plain.stdoutBytes.length;

      final ProcessGitRunner permissive = ProcessGitRunner(
        globalEnvironment: repo.runner.globalEnvironment,
        defaultMaxOutputBytes: size - 1,
      );
      final GitRunResult accepted = await permissive.run(
        GitRunRequest(
          arguments: const <String>['rev-parse', 'HEAD'],
          workingDirectory: repo.directory.path,
          maxOutputBytes: size,
        ),
      );
      expect(accepted.stdoutBytes, plain.stdoutBytes);

      final ProcessGitRunner strict = ProcessGitRunner(
        globalEnvironment: repo.runner.globalEnvironment,
        defaultMaxOutputBytes: size + 1,
      );
      await expectLater(
        strict.run(
          GitRunRequest(
            arguments: const <String>['rev-parse', 'HEAD'],
            workingDirectory: repo.directory.path,
            maxOutputBytes: size - 1,
          ),
        ),
        throwsA(
          isA<GitOutputLimitException>().having(
            (GitOutputLimitException error) => error.limit,
            'limit',
            size - 1,
          ),
        ),
      );
    });

    test('has no limit by default', () async {
      final String content = 'x' * 300000;
      repo.writeFile('large.txt', content);
      await repo.runGit(const <String>['add', '.']);
      await repo.runGit(const <String>['commit', '-m', 'large']);

      final GitRunResult result =
          await repo.runGit(const <String>['show', 'HEAD:large.txt']);

      expect(repo.runner.defaultMaxOutputBytes, isNull);
      expect(result.stdout, content);
    });
  });
}
