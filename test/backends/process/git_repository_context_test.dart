import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/scripted_git_runner.dart';
import 'support/synthetic_git_support.dart';

/// A Windows platform whose relative paths hang from [currentDirectory].
GitPlatform windows({String? currentDirectory}) => GitPlatform(
      operatingSystem: GitOperatingSystem.windows,
      currentDirectory: currentDirectory,
    );

/// A POSIX platform whose relative paths hang from [currentDirectory].
GitPlatform posix({String? currentDirectory}) => GitPlatform(
      operatingSystem: GitOperatingSystem.linux,
      currentDirectory: currentDirectory,
    );

void main() {
  group('GitRepositoryContext on Windows paths', () {
    final GitPlatform platform = windows();

    test('keeps a drive-qualified path and normalizes its dot segments', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: r'C:\synthetic\other\..\repo',
        platform: platform,
      );

      expect(context.path, r'C:\synthetic\repo');
    });

    test('normalizes a drive path written with mixed separators', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: r'C:\synthetic/other/../repo',
        platform: platform,
      );

      expect(context.path, r'C:\synthetic\repo');
    });

    test('keeps the UNC share of a network path', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: r'\\server\share\folder\..\repo',
        platform: platform,
      );

      expect(context.path, r'\\server\share\repo');
    });

    test('resolves a relative path against the current directory', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: 'nested/repo',
        platform: windows(currentDirectory: r'C:\work\checkout'),
      );

      expect(context.path, r'C:\work\checkout\nested\repo');
    });

    test('resolves a relative path carrying .. against the current directory',
        () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: r'nested\..\repo',
        platform: windows(currentDirectory: r'C:\work\checkout'),
      );

      expect(context.path, r'C:\work\checkout\repo');
    });

    test('refuses a relative path when the platform has no current directory',
        () {
      expect(
        () => GitRepositoryContext(path: r'repo\sub', platform: platform),
        throwsArgumentError,
      );
    });

    test('withIndexFile resolves a relative path with windows separators', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: r'C:\synthetic\repo',
        platform: platform,
      );

      final GitRepositoryContext withIndex = context.withIndexFile('indexes/a');

      expect(
        withIndex.environment['GIT_INDEX_FILE'],
        r'C:\synthetic\repo\indexes\a',
      );
    });

    test('withIndexFile keeps an absolute path as given', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: r'C:\synthetic\repo',
        platform: platform,
      );

      expect(
        context
            .withIndexFile(r'D:\indexes\alternate.index')
            .environment['GIT_INDEX_FILE'],
        r'D:\indexes\alternate.index',
      );
    });
  });

  group('GitRepositoryContext on POSIX paths', () {
    final GitPlatform platform = posix();

    test('keeps an absolute path and normalizes its dot segments', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: '/srv/other/../repo/./nested',
        platform: platform,
      );

      expect(context.path, '/srv/repo/nested');
    });

    test('drops .. segments that would climb above the root', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: '/a/../../b',
        platform: platform,
      );

      expect(context.path, '/b');
    });

    test('resolves a relative path against the current directory', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: 'nested/repo',
        platform: posix(currentDirectory: '/work/checkout'),
      );

      expect(context.path, '/work/checkout/nested/repo');
    });

    test('resolves a relative path carrying .. against the current directory',
        () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: 'nested/../repo',
        platform: posix(currentDirectory: '/work/checkout'),
      );

      expect(context.path, '/work/checkout/repo');
    });

    test('refuses a relative path when the platform has no current directory',
        () {
      expect(
        () => GitRepositoryContext(path: 'repo/sub', platform: platform),
        throwsArgumentError,
      );
    });

    test('withIndexFile resolves a relative path under the repository', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: '/srv/repo',
        platform: platform,
      );

      expect(
        context.withIndexFile('indexes/a').environment['GIT_INDEX_FILE'],
        '/srv/repo/indexes/a',
      );
    });
  });

  group('commands follow the injected platform', () {
    test('a Windows engine runs its commands in the resolved Windows path',
        () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['rev-parse', '--is-bare-repository'],
          GitRunResult.fromStrings('false\n'),
        );

      await syntheticEngine(
        runner,
        platform: windows(currentDirectory: r'C:\work'),
      ).open('repo');

      final GitRunRequest request = runner.requests.single;
      expect(
        request.arguments,
        const <String>['rev-parse', '--is-bare-repository'],
      );
      expect(request.workingDirectory, r'C:\work\repo');
    });

    test('a POSIX engine runs its commands in the resolved POSIX path',
        () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['rev-parse', '--is-bare-repository'],
          GitRunResult.fromStrings('false\n'),
        );

      await syntheticEngine(
        runner,
        platform: posix(currentDirectory: '/work'),
      ).open('nested/../repo');

      final GitRunRequest request = runner.requests.single;
      expect(
        request.arguments,
        const <String>['rev-parse', '--is-bare-repository'],
      );
      expect(request.workingDirectory, '/work/repo');
    });
  });

  group('GitRepositoryContext environment', () {
    test('carries literal pathspecs by default', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: '/srv/repo',
        platform: posix(),
      );

      expect(context.environment['GIT_LITERAL_PATHSPECS'], '1');
    });

    test('withEnvironment merges over literal pathspecs', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: '/srv/repo',
        platform: posix(),
        environment: const <String, String>{'ENGINE_A': '1'},
      );
      final GitRepositoryContext merged =
          context.withEnvironment(const <String, String>{'ENGINE_B': '2'});
      final GitRepositoryContext overridden =
          context.withEnvironment(const <String, String>{
        'GIT_LITERAL_PATHSPECS': '0',
      });

      expect(merged.environment['GIT_LITERAL_PATHSPECS'], '1');
      expect(merged.environment['ENGINE_B'], '2');
      expect(overridden.environment['GIT_LITERAL_PATHSPECS'], '0');
    });

    test('commands reach the runner with literal pathspecs', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['add', '--', 'a*b.txt'],
          GitRunResult.fromStrings(''),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await repository.worktree.add(const <String>['a*b.txt']);

      final GitRunRequest request = runner.requests.single;
      expect(request.arguments, const <String>['add', '--', 'a*b.txt']);
      expect(request.environment['GIT_LITERAL_PATHSPECS'], '1');
    });

    test('withEnvironment merges over the current variables without mutating',
        () {
      final GitRepositoryContext base = GitRepositoryContext(
        path: '/srv/repo',
        platform: posix(),
        environment: const <String, String>{'ENGINE_A': '1'},
      );
      final GitRepositoryContext merged =
          base.withEnvironment(const <String, String>{
        'ENGINE_A': '2',
        'ENGINE_B': '3',
      });

      expect(base.environment['ENGINE_A'], '1');
      expect(base.environment.containsKey('ENGINE_B'), isFalse);
      expect(merged.environment['ENGINE_A'], '2');
      expect(merged.environment['ENGINE_B'], '3');
      expect(merged.path, base.path);
    });

    test('environment maps are unmodifiable', () {
      final GitRepositoryContext context = GitRepositoryContext(
        path: '/srv/repo',
        platform: posix(),
      );
      expect(
        () => context.environment['ENGINE_X'] = 'y',
        throwsUnsupportedError,
      );
    });
  });
}
