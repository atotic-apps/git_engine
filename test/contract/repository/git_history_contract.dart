import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

final GitIdentity _identity = GitIdentity(
  name: 'Ada Lovelace',
  email: 'ada@example.com',
);

const List<ScenarioCommit> _scenario = <ScenarioCommit>[
  ScenarioCommit(
    message: 'Add a',
    files: <String, String>{'a.txt': 'one\n'},
  ),
  ScenarioCommit(
    message: 'Add b',
    files: <String, String>{'b.txt': 'two\n'},
  ),
  ScenarioCommit(
    message: 'Touch a',
    files: <String, String>{'a.txt': 'three\n'},
  ),
];

/// Declares the [GitHistoryReader] and [GitHistory] contract tests for
/// [factory].
///
/// The same suite runs on a working clone and on a bare clone, so the contract
/// is checked in both kinds of repository.
void defineGitHistoryContract(BackendFactory factory) {
  group('GitHistory', () {
    _defineHistoryTests(
      'on a working clone',
      factory.createRepositoryFromScenario,
      () async => factory.createWorkingRepository(),
    );
    _defineHistoryTests(
      'on a bare clone',
      factory.createBareRepositoryFromScenario,
      () async => factory.createBareRepository(),
    );
  });
}

void _defineHistoryTests(
  String description,
  Future<ScenarioRepository> Function(List<ScenarioCommit>) create,
  Future<GitRepository> Function() createEmpty,
) {
  group(description, () {
    late ScenarioRepository scenario;
    late GitHistory history;

    setUp(() async {
      scenario = await create(_scenario);
      history = scenario.repository.history;
    });

    test('reports a true ancestry, including a commit itself', () async {
      final GitHistoryReader reader = history;
      expect(
        await reader.isAncestor(scenario.commits[0], scenario.commits[2]),
        isTrue,
      );
      expect(
        await reader.isAncestor(scenario.commits[2], scenario.commits[2]),
        isTrue,
      );
    });

    test('reports a false ancestry the other way around', () async {
      expect(
        await history.isAncestor(scenario.commits[2], scenario.commits[0]),
        isFalse,
      );
    });

    test('finds the merge base of two commits', () async {
      expect(
        await history.mergeBase(scenario.commits[2], scenario.commits[1]),
        scenario.commits[1],
      );
      expect(
        await history.mergeBase(scenario.commits[0], scenario.commits[2]),
        scenario.commits[0],
      );
      expect(
        await history.mergeBase(scenario.commits[1], scenario.commits[1]),
        scenario.commits[1],
      );
    });

    test('finds the last commit touching a path', () async {
      expect(
        await history.lastCommitTouching('a.txt'),
        scenario.commits[2],
      );
      expect(
        await history.lastCommitTouching('b.txt'),
        scenario.commits[1],
      );
      expect(await history.lastCommitTouching('never.txt'), isNull);
    });

    test('walks path history from a revision expression', () async {
      expect(
        await history.lastCommitTouching(
          'a.txt',
          rev: scenario.commits[0].value,
        ),
        scenario.commits[0],
      );
      expect(
        await history.lastCommitTouching(
          'b.txt',
          rev: scenario.commits[0].value,
        ),
        isNull,
      );
    });

    test('lists the commits of a range touching a path, newest first',
        () async {
      expect(
        await history.commitsTouching('a.txt'),
        <GitOid>[scenario.commits[2], scenario.commits[0]],
      );
      expect(
        await history.commitsTouching(
          'a.txt',
          from: scenario.commits[0].value,
          to: scenario.commits[2].value,
        ),
        <GitOid>[scenario.commits[2]],
      );
      expect(
        await history.commitsTouching(
          'b.txt',
          from: scenario.commits[0].value,
          to: scenario.commits[2].value,
        ),
        <GitOid>[scenario.commits[1]],
      );
      expect(await history.commitsTouching('never.txt'), isEmpty);
    });

    test('refuses an unknown revision with the domain exception', () async {
      await expectLater(
        history.lastCommitTouching('a.txt', rev: 'no-such-branch'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'no-such-branch',
          ),
        ),
      );
      await expectLater(
        history.commitsTouching('a.txt', from: 'no-such-branch'),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      await expectLater(
        history.commitsSince('no-such-branch', scenario.commits[2].value),
        throwsA(isA<GitUnknownRevisionException>()),
      );
    });

    test('lists the commits of a range with their subjects, newest first',
        () async {
      expect(
        await history.commitsSince(
          scenario.commits[1].value,
          scenario.commits[2].value,
        ),
        <GitLogEntry>[
          GitLogEntry(oid: scenario.commits[2], subject: 'Touch a'),
        ],
      );
      expect(
        await history.commitsSince(
          scenario.commits.first.value,
          scenario.commits.last.value,
        ),
        <GitLogEntry>[
          GitLogEntry(oid: scenario.commits[2], subject: 'Touch a'),
          GitLogEntry(oid: scenario.commits[1], subject: 'Add b'),
        ],
      );
    });

    test('lists nothing for a range that carries no commit', () async {
      expect(
        await history.commitsSince(
          scenario.commits[2].value,
          scenario.commits[2].value,
        ),
        isEmpty,
      );
      expect(
        await history.commitsSince(
          scenario.commits[2].value,
          scenario.commits[0].value,
        ),
        isEmpty,
        reason: 'a base newer than the tip carries everything already',
      );
    });

    test('logs complete commits of a linear history, newest first', () async {
      final List<GitLogCommit> commits = await history.log();

      expect(
        commits.map((GitLogCommit entry) => entry.oid).toList(),
        scenario.commits.reversed.toList(),
      );
      for (final GitLogCommit entry in commits) {
        final GitCommit read =
            await scenario.repository.objects.readCommit(entry.oid);
        expect(entry.commit, read);
      }
      expect(commits.first.commit.message, 'Touch a');
      expect(commits.first.commit.parents, <GitOid>[scenario.commits[1]]);
    });

    test('logs only the commits touching a literal path', () async {
      expect(
        (await history.log(path: 'a.txt'))
            .map((GitLogCommit entry) => entry.oid)
            .toList(),
        <GitOid>[scenario.commits[2], scenario.commits[0]],
      );
      expect(
        (await history.log(path: 'b.txt'))
            .map((GitLogCommit entry) => entry.oid)
            .toList(),
        <GitOid>[scenario.commits[1]],
      );
      expect(await history.log(path: 'never.txt'), isEmpty);
    });

    test('logs a directory as covering its content', () async {
      final ScenarioRepository docs = await create(const <ScenarioCommit>[
        ScenarioCommit(
          message: 'Add the guide',
          files: <String, String>{'docs/guide.txt': 'one\n'},
        ),
        ScenarioCommit(
          message: 'Touch the guide',
          files: <String, String>{'docs/guide.txt': 'two\n'},
        ),
        ScenarioCommit(
          message: 'Add another file',
          files: <String, String>{'other.txt': 'x\n'},
        ),
      ]);

      expect(
        (await docs.repository.history.log(path: 'docs'))
            .map((GitLogCommit entry) => entry.oid)
            .toList(),
        <GitOid>[docs.commits[1], docs.commits[0]],
      );
    });

    test('caps the walk with limit', () async {
      expect(
        (await history.log(limit: 2))
            .map((GitLogCommit entry) => entry.oid)
            .toList(),
        <GitOid>[scenario.commits[2], scenario.commits[1]],
      );
      expect(
        (await history.log(limit: 10))
            .map((GitLogCommit entry) => entry.oid)
            .toList(),
        scenario.commits.reversed.toList(),
      );
      await expectLater(history.log(limit: 0), throwsArgumentError);
      await expectLater(history.log(limit: -1), throwsArgumentError);
    });

    test('walks the commits of a from/to range', () async {
      expect(
        (await history.log(
          from: scenario.commits[0].value,
          to: scenario.commits[2].value,
        ))
            .map((GitLogCommit entry) => entry.oid)
            .toList(),
        <GitOid>[scenario.commits[2], scenario.commits[1]],
      );
      expect(
        await history.log(
          from: scenario.commits[2].value,
          to: scenario.commits[2].value,
        ),
        isEmpty,
      );
    });

    test('logs nothing in a repository without a commit', () async {
      final GitRepository empty = await createEmpty();
      expect(await empty.history.log(), isEmpty);
    });

    test('refuses an unknown revision in log', () async {
      await expectLater(
        history.log(to: 'no-such-branch'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'no-such-branch',
          ),
        ),
      );
      await expectLater(
        history.log(from: 'no-such-branch'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'no-such-branch',
          ),
        ),
      );
    });

    test('orders a merge before its parents and honours firstParent', () async {
      final GitRepository repository = scenario.repository;
      final GitOid root = scenario.commits[0];
      final GitOid main = scenario.commits[1];
      final GitCommit mainCommit = await repository.objects.readCommit(main);
      final GitCommit sideSource =
          await repository.objects.readCommit(scenario.commits[2]);
      final DateTime sideDate = DateTime.utc(2000, 1, 1);
      final GitOid side = await repository.objects.commitTree(
        sideSource.tree,
        <GitOid>[root],
        'Side work',
        author: _identity,
        committer: _identity,
        authorDate: sideDate,
        committerDate: sideDate,
      );
      final DateTime mergeDate = DateTime.utc(2030, 1, 1);
      final GitOid merge = await repository.objects.commitTree(
        mainCommit.tree,
        <GitOid>[main, side],
        'Merge the side work',
        author: _identity,
        committer: _identity,
        authorDate: mergeDate,
        committerDate: mergeDate,
      );
      await _pointHeadAt(repository, merge);

      expect(
        (await history.log()).map((GitLogCommit entry) => entry.oid).toList(),
        <GitOid>[merge, main, side, root],
      );
      expect(
        (await history.log(firstParent: true))
            .map((GitLogCommit entry) => entry.oid)
            .toList(),
        <GitOid>[merge, main, root],
      );
    });

    test('keeps a multiline non-ASCII message exactly', () async {
      final GitRepository repository = scenario.repository;
      final GitOid parent = scenario.commits[2];
      final GitCommit parentCommit =
          await repository.objects.readCommit(parent);
      const String message =
          'Sujet accentué — 日本語\n\nCorps du message\nseconde ligne';
      final GitOid oid = await _writeRawCommit(
        repository,
        tree: parentCommit.tree,
        parent: parent,
        message: message,
      );
      await _pointHeadAt(repository, oid);

      final List<GitLogCommit> commits = await history.log(limit: 1);
      expect(commits.single.oid, oid);
      expect(commits.single.commit.message, message);
    });

    test('keeps the instants of dates recorded with an offset', () async {
      final GitRepository repository = scenario.repository;
      final GitOid parent = scenario.commits[2];
      final GitCommit parentCommit =
          await repository.objects.readCommit(parent);
      final GitOid oid = await _writeRawCommit(
        repository,
        tree: parentCommit.tree,
        parent: parent,
        message: 'Offset dates',
        author: 'Ada Lovelace <ada@example.com> 1700000000 +0530',
        committer: 'Grace Hopper <grace@example.com> 1700000100 -0700',
      );
      await _pointHeadAt(repository, oid);

      final GitLogCommit entry = (await history.log(limit: 1)).single;
      expect(entry.commit.author, _identity);
      expect(
        entry.commit.committer,
        GitIdentity(name: 'Grace Hopper', email: 'grace@example.com'),
      );
      expect(entry.commit.authorDate, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(entry.commit.committerDate, DateTime.utc(2023, 11, 14, 22, 15));
    });
  });
}

/// Points the current branch of [repository] at [oid].
Future<void> _pointHeadAt(GitRepository repository, GitOid oid) async {
  final String? branch = await repository.branches.current();
  await repository.refs.updateRef('refs/heads/${branch ?? 'main'}', oid);
}

/// Writes and returns a commit object with exactly [message] and the given
/// raw signature lines.
Future<GitOid> _writeRawCommit(
  GitRepository repository, {
  required GitOid tree,
  required GitOid parent,
  required String message,
  String author = 'Ada Lovelace <ada@example.com> 1700000000 +0000',
  String committer = 'Grace Hopper <grace@example.com> 1700000100 +0000',
}) {
  final String content = 'tree ${tree.value}\n'
      'parent ${parent.value}\n'
      'author $author\n'
      'committer $committer\n'
      '\n'
      '$message\n';
  return repository.objects.writeObject(
    GitObjectType.commit,
    utf8.encode(content),
  );
}
