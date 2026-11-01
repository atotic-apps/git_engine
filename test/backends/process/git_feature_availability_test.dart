import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/scripted_git_runner.dart';
import 'support/synthetic_git_support.dart';

const List<String> _versionCommand = <String>['--version'];
const String _installedVersion = 'git version 2.30.0';

/// A runner whose installed git is [_installedVersion] and nothing else.
ScriptedGitRunner _runner() {
  return ScriptedGitRunner()
    ..replyTo(
      _versionCommand,
      GitRunResult.fromStrings('$_installedVersion\n'),
    );
}

/// Arguments of every request [runner] received, in call order.
List<List<String>> _commands(ScriptedGitRunner runner) {
  return runner.requests
      .map((GitRunRequest request) => request.arguments)
      .toList();
}

void main() {
  final GitOid ours = GitOid.parse(syntheticFirstParentOid);
  final GitOid theirs = GitOid.parse(syntheticSecondParentOid);

  group('mergeTree on a git older than 2.38', () {
    test('reports the feature as unavailable without running merge-tree',
        () async {
      final ScriptedGitRunner runner = _runner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.merge.mergeTree(ours, theirs),
        throwsA(
          isA<GitFeatureUnavailableException>()
              .having(
                (GitFeatureUnavailableException error) => error.operation,
                'operation',
                'mergeTree',
              )
              .having(
                (GitFeatureUnavailableException error) => error.requiredVersion,
                'requiredVersion',
                '2.38',
              )
              .having(
                (GitFeatureUnavailableException error) =>
                    error.installedVersion,
                'installedVersion',
                _installedVersion,
              ),
        ),
      );
      expect(_commands(runner), <List<String>>[_versionCommand]);
    });
  });

  group('other domains on a git older than 2.38', () {
    test('opening a repository never reads the git version', () async {
      final ScriptedGitRunner runner = _runner()
        ..replyTo(
          const <String>['rev-parse', '--is-bare-repository'],
          GitRunResult.fromStrings('false\n'),
        );

      final ProcessGitRepository repository = await syntheticEngine(runner)
          .open(syntheticRepositoryPath) as ProcessGitRepository;

      expect(repository, isA<ProcessGitWorkingRepository>());
      expect(
        _commands(runner),
        <List<String>>[
          const <String>['rev-parse', '--is-bare-repository'],
        ],
      );
    });

    test('reading an object never reads the git version', () async {
      final GitOid oid = GitOid.parse(syntheticBlobOid);
      final ScriptedGitRunner runner = _runner()
        ..replyTo(
          <String>['cat-file', 'blob', oid.value],
          GitRunResult.fromStrings('blob content'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(
        await repository.objects.readBlob(oid),
        utf8.encode('blob content'),
      );
      expect(
        _commands(runner),
        <List<String>>[
          <String>['cat-file', 'blob', oid.value],
        ],
      );
    });

    test('reading a reference never reads the git version', () async {
      final ScriptedGitRunner runner = _runner()
        ..replyTo(
          const <String>['symbolic-ref', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('refs/heads/main\n'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(await repository.branches.current(), 'main');
      expect(
        _commands(runner),
        <List<String>>[
          const <String>['symbolic-ref', '--quiet', 'HEAD'],
        ],
      );
    });

    test('writing a tree from the index never reads the git version', () async {
      final ScriptedGitRunner runner = _runner()
        ..replyTo(
          const <String>['write-tree'],
          GitRunResult.fromStrings('$syntheticTreeOid\n'),
        );
      final ProcessGitIndexedRepository repository =
          syntheticIndexedRepository(runner);

      expect(
          await repository.index.writeTree(), GitOid.parse(syntheticTreeOid));
      expect(
        _commands(runner),
        <List<String>>[
          const <String>['write-tree'],
        ],
      );
    });
  });
}
