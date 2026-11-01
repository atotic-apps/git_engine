import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/scripted_git_runner.dart';
import 'support/synthetic_git_support.dart';

/// A platform with no environment variable, identical on every machine.
final GitPlatform plainPlatform = GitPlatform(
  operatingSystem: GitOperatingSystem.linux,
  currentDirectory: '/',
);

/// The command reading the SSH command chosen in a configuration file; an
/// exchange probes it before running.
const List<String> sshCommandProbe = <String>[
  'config',
  '--get',
  'core.sshCommand',
];

/// The scripted probe reply marking no SSH command configured.
GitCommandException unsetSshCommand() => GitCommandException(
      arguments: sshCommandProbe,
      exitCode: 1,
    );

void main() {
  final ScriptedGitRunner runner = ScriptedGitRunner()
    ..failWith(sshCommandProbe, unsetSshCommand())
    ..replyTo(
      <String>['rev-parse', '--is-bare-repository'],
      GitRunResult.fromStrings('false\n'),
    )
    ..replyTo(
      <String>['clone', '--', '/source/repo', '/target/repo'],
      GitRunResult.fromStrings(''),
    )
    ..replyTo(
      <String>['fetch', '--no-tags', '--', 'origin', '--depth=999'],
      GitRunResult.fromStrings(''),
    )
    ..replyTo(
      <String>['push', '--', 'origin', '+main:other'],
      GitRunResult.fromStrings(''),
    );
  final ProcessGitWorkingRepository repository =
      syntheticWorkingRepository(runner, platform: plainPlatform);
  final ProcessGitEngine engine =
      syntheticEngine(runner, platform: plainPlatform);

  test('clone separates source and target from the options with --', () async {
    await engine.clone('/source/repo', '/target/repo');

    expect(
      runner.requests
          .singleWhere((GitRunRequest sent) => sent.arguments.first == 'clone')
          .arguments,
      <String>['clone', '--', '/source/repo', '/target/repo'],
    );
  });

  test('fetch separates the remote and the refspecs from the options with --',
      () async {
    await engine.fetch(
      repository,
      remote: 'origin',
      refspecs: const <String>['--depth=999'],
      tags: GitTagFetch.none,
    );

    final GitRunRequest request = runner.requests
        .singleWhere((GitRunRequest sent) => sent.arguments.first == 'fetch');
    expect(
      request.arguments,
      <String>['fetch', '--no-tags', '--', 'origin', '--depth=999'],
      reason: 'a refspec that reads like an option must stay data',
    );
  });

  test('push separates the remote and the refspecs from the options with --',
      () async {
    await engine.push(
      repository,
      remote: 'origin',
      refspecs: const <String>['+main:other'],
    );

    final GitRunRequest request = runner.requests
        .singleWhere((GitRunRequest sent) => sent.arguments.first == 'push');
    expect(
      request.arguments,
      <String>['push', '--', 'origin', '+main:other'],
    );
  });

  group('remotes keep their names and URLs as data', () {
    test('add separates the name and the URL from the options with --',
        () async {
      final ScriptedGitRunner tests = ScriptedGitRunner()
        ..replyTo(
          <String>['remote', 'add', '--', 'origin', '/upstream/repo'],
          GitRunResult.fromStrings(''),
        );
      await remotesRepository(tests).remotes.add('origin', '/upstream/repo');

      expect(
        tests.requests.single.arguments,
        <String>['remote', 'add', '--', 'origin', '/upstream/repo'],
      );
    });

    test('get-url separates the name from the options with --', () async {
      final ScriptedGitRunner tests = ScriptedGitRunner()
        ..replyTo(
          <String>['remote', 'get-url', '--', '-eerie'],
          GitRunResult.fromStrings('/upstream/repo\n'),
        );

      expect(
        await remotesRepository(tests).remotes.getUrl('-eerie'),
        '/upstream/repo',
      );
      expect(
        tests.requests.single.arguments,
        <String>['remote', 'get-url', '--', '-eerie'],
      );
    });

    test('set-url separates the name and the URL from the options with --',
        () async {
      final ScriptedGitRunner tests = ScriptedGitRunner()
        ..replyTo(
          <String>['remote', 'set-url', '--', '--push-like', '/other/repo'],
          GitRunResult.fromStrings(''),
        );

      await remotesRepository(tests)
          .remotes
          .setUrl('--push-like', '/other/repo');

      expect(
        tests.requests.single.arguments,
        <String>['remote', 'set-url', '--', '--push-like', '/other/repo'],
      );
    });

    test('remove separates the name from the options with --', () async {
      final ScriptedGitRunner tests = ScriptedGitRunner()
        ..replyTo(
          <String>['remote', 'remove', '--', '-plain'],
          GitRunResult.fromStrings(''),
        );

      await remotesRepository(tests).remotes.remove('-plain');
      expect(
        tests.requests.single.arguments,
        <String>['remote', 'remove', '--', '-plain'],
      );
    });

    test('rename separates the names from the options with --', () async {
      final ScriptedGitRunner tests = ScriptedGitRunner()
        ..replyTo(
          <String>['remote', 'rename', '--', '--shifty', 'plain'],
          GitRunResult.fromStrings(''),
        );

      await remotesRepository(tests).remotes.rename('--shifty', 'plain');
      expect(
        tests.requests.single.arguments,
        <String>['remote', 'rename', '--', '--shifty', 'plain'],
      );
    });
  });

  group('branch and tag names travel after the -- marker', () {
    test('a branch creation sends its names behind --', () async {
      final ScriptedGitRunner tests = ScriptedGitRunner()
        ..replyTo(
          <String>['branch', '--force', '--', 'topic', syntheticCommitOid],
          GitRunResult.fromStrings(''),
        );

      await remotesRepository(tests).branches.create(
            'topic',
            startPoint: syntheticCommitOid,
            force: true,
          );

      expect(
        tests.requests.single.arguments,
        <String>['branch', '--force', '--', 'topic', syntheticCommitOid],
      );
    });

    test('a tag creation sends its name and target behind --', () async {
      final ScriptedGitRunner tests = ScriptedGitRunner()
        ..replyTo(
          <String>['tag', '--force', '--', 'v1', syntheticCommitOid],
          GitRunResult.fromStrings(''),
        );

      await remotesRepository(tests).tags.create(
            'v1',
            GitOid.parse(syntheticCommitOid),
            force: true,
          );

      expect(
        tests.requests.single.arguments,
        <String>['tag', '--force', '--', 'v1', syntheticCommitOid],
      );
    });
  });
}

/// A repository holding every evaluator the facades delegate to, over one
/// runner.
ProcessGitWorkingRepository remotesRepository(ScriptedGitRunner runner) {
  return syntheticWorkingRepository(runner, platform: plainPlatform);
}
