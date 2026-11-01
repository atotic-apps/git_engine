import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the [GitMerge] contract against [factory].
///
/// Only the repository-level merge is exercised here: computing a merged tree
/// without touching the index or the work tree. The same cases run on a
/// working repository and on a bare one.
///
/// [supportsMergeTree] tells whether the installed git can run
/// `merge-tree --write-tree` (git 2.38 or newer). When false, the suite
/// expects [GitFeatureUnavailableException] instead of a merged tree.
void defineGitMergeContract(
  BackendFactory factory, {
  bool supportsMergeTree = true,
}) {
  group('GitMerge contract', () {
    if (!supportsMergeTree) {
      test('reports merge-tree as unavailable on an older git', () async {
        final ScenarioRepository scenario =
            await factory.createRepositoryFromScenario(const <ScenarioCommit>[
          ScenarioCommit(
            message: 'Add a',
            files: <String, String>{'a.txt': 'a\n'},
          ),
        ]);
        final GitRepository repository = scenario.repository;
        final GitOid tip = scenario.commits.single;

        await expectLater(
          repository.merge.mergeTree(tip, tip),
          throwsA(
            isA<GitFeatureUnavailableException>()
                .having(
                  (GitFeatureUnavailableException error) => error.operation,
                  'operation',
                  'mergeTree',
                )
                .having(
                  (GitFeatureUnavailableException error) =>
                      error.requiredVersion,
                  'requiredVersion',
                  '2.38',
                )
                .having(
                  (GitFeatureUnavailableException error) =>
                      error.installedVersion,
                  'installedVersion',
                  startsWith('git version '),
                ),
          ),
        );
      });
      return;
    }

    group('on a working repository', () {
      test('a clean merge writes the merged tree and touches nothing',
          () async {
        final _Branches branches = await _branches(factory);
        final GitWorkingRepository repository = branches.repository;
        final GitOid headBefore = await _head(repository);
        final List<GitStatusEntry> statusBefore =
            await repository.worktree.status();

        final GitMergeTreeResult result = await repository.merge
            .mergeTree(branches.mainTip, branches.topicTip);

        expect(result.conflictingFiles, isEmpty);
        final GitTree tree = await repository.objects.readTree(result.tree);
        expect(
          tree.entries.map((GitTreeEntry entry) => entry.path),
          containsAll(<String>['a.txt', 'main.txt', 'topic.txt']),
        );
        expect(await _head(repository), headBefore);
        expect(await repository.worktree.status(), statusBefore);
      });

      test('picking the same commit twice yields its own tree', () async {
        final ScenarioRepository scenario =
            await factory.createRepositoryFromScenario(const <ScenarioCommit>[
          ScenarioCommit(
            message: 'Add a',
            files: <String, String>{'a.txt': 'a\n'},
          ),
        ]);
        final GitRepository repository = scenario.repository;
        final GitOid tip = scenario.commits.single;
        final GitCommit commit = await repository.objects.readCommit(tip);

        final GitMergeTreeResult result =
            await repository.merge.mergeTree(tip, tip);

        expect(result.conflictingFiles, isEmpty);
        expect(result.tree, commit.tree);
      });

      test('a conflicted merge names the files without touching anything',
          () async {
        final _Branches branches = await _conflictedBranches(factory);
        final GitWorkingRepository repository = branches.repository;
        final GitOid headBefore = await _head(repository);
        final List<GitStatusEntry> statusBefore =
            await repository.worktree.status();

        final GitMergeTreeResult result = await repository.merge
            .mergeTree(branches.mainTip, branches.topicTip);

        expect(result.isConflicted, isTrue);
        expect(result.conflictingFiles, <String>['a.txt']);
        final GitTree tree = await repository.objects.readTree(result.tree);
        final GitTreeEntry entry = tree.entries.single;
        expect(entry.path, 'a.txt');
        final String content =
            utf8.decode(await repository.objects.readBlob(entry.oid));
        expect(content, contains('<<<<<<<'));
        expect(content, contains('topic line'));
        expect(content, contains('main line'));

        expect(await _head(repository), headBefore);
        expect(await repository.worktree.status(), statusBefore);
      });

      test('refusals of git itself surface as exceptions', () async {
        final _Branches branches = await _branches(factory);
        final GitWorkingRepository repository = branches.repository;
        final GitOid headBefore = await _head(repository);

        await expectLater(
          repository.merge.mergeTree(
            branches.mainTip,
            GitOid.parse('0123456789' * 4),
          ),
          throwsA(isA<GitException>()),
        );
        expect(await _head(repository), headBefore);
      });
    });

    group('on a bare repository', () {
      test('a clean merge writes the merged tree with no index', () async {
        final ScenarioRepository scenario =
            await factory.createBareRepositoryFromScenario(
          const <ScenarioCommit>[
            ScenarioCommit(
              message: 'Add a',
              files: <String, String>{'a.txt': 'a\n'},
            ),
            ScenarioCommit(
              message: 'Change a',
              files: <String, String>{'a.txt': 'b\n'},
            ),
          ],
        );
        final GitRepository repository = scenario.repository;
        final GitOid headBefore =
            (await repository.revisions.resolveRevision('HEAD'))!;
        final GitCommit newer =
            await repository.objects.readCommit(scenario.commits[1]);

        final GitMergeTreeResult result = await repository.merge.mergeTree(
          scenario.commits[0],
          scenario.commits[1],
        );

        expect(result.conflictingFiles, isEmpty);
        expect(result.tree, newer.tree);
        expect(
          await repository.revisions.resolveRevision('HEAD'),
          headBefore,
        );
      });

      test('a conflicted merge names the files with no index', () async {
        final ScenarioRepository scenario =
            await factory.createBareRepositoryFromScenario(
          const <ScenarioCommit>[
            ScenarioCommit(
              message: 'Add a',
              files: <String, String>{'a.txt': 'base\n'},
            ),
          ],
        );
        final GitRepository repository = scenario.repository;
        final GitOid base = scenario.commits.single;
        final GitIdentity identity = GitIdentity(
          name: 'Contract Merge',
          email: 'contract-merge@example.com',
        );
        final GitOid ours = await repository.objects.commitTree(
          await _treeWithFile(repository, 'a.txt', 'ours\n'),
          <GitOid>[base],
          'ours',
          author: identity,
          committer: identity,
        );
        final GitOid theirs = await repository.objects.commitTree(
          await _treeWithFile(repository, 'a.txt', 'theirs\n'),
          <GitOid>[base],
          'theirs',
          author: identity,
          committer: identity,
        );

        final GitMergeTreeResult result =
            await repository.merge.mergeTree(ours, theirs);

        expect(result.isConflicted, isTrue);
        expect(result.conflictingFiles, <String>['a.txt']);
        final GitTree tree = await repository.objects.readTree(result.tree);
        final GitTreeEntry entry = tree.entries.single;
        final String content =
            utf8.decode(await repository.objects.readBlob(entry.oid));
        expect(content, contains('<<<<<<<'));
        expect(content, contains('ours'));
        expect(content, contains('theirs'));
      });

      test('unrelated histories are refused unless allowed', () async {
        final GitRepository repository = await factory.createBareRepository();
        final GitIdentity identity = GitIdentity(
          name: 'Contract Merge',
          email: 'contract-merge@example.com',
        );
        final GitOid ours = await repository.objects.commitTree(
          await _treeWithFile(repository, 'ours.txt', 'ours\n'),
          const <GitOid>[],
          'orphan ours',
          author: identity,
          committer: identity,
        );
        final GitOid theirs = await repository.objects.commitTree(
          await _treeWithFile(repository, 'theirs.txt', 'theirs\n'),
          const <GitOid>[],
          'orphan theirs',
          author: identity,
          committer: identity,
        );

        await expectLater(
          repository.merge.mergeTree(ours, theirs),
          throwsA(isA<GitUnrelatedHistoriesException>()),
          reason: 'git refuses two histories without a common ancestor',
        );
        final GitMergeTreeResult merged = await repository.merge.mergeTree(
          ours,
          theirs,
          allowUnrelatedHistories: true,
        );
        expect(merged.conflictingFiles, isEmpty);
        final GitTree tree = await repository.objects.readTree(merged.tree);
        expect(
          tree.entries.map((GitTreeEntry entry) => entry.path),
          containsAll(<String>['ours.txt', 'theirs.txt']),
        );
      });
    });
  });
}

/// A repository with a base commit on `main`, then divergent commits on
/// `main` and `topic`.
final class _Branches {
  const _Branches({
    required this.repository,
    required this.mainTip,
    required this.topicTip,
  });

  final GitWorkingRepository repository;
  final GitOid mainTip;
  final GitOid topicTip;
}

/// Builds two branches adding distinct files on top of one base commit.
Future<_Branches> _branches(BackendFactory factory) async {
  final GitWorkingRepository repository =
      await factory.createWorkingRepository();
  await _commit(repository, factory, 'Add a', <String, String>{
    'a.txt': 'a\n',
  });
  await repository.worktree.checkoutNewBranch('topic');
  final GitOid topicTip = await _commit(
    repository,
    factory,
    'Topic work',
    <String, String>{'topic.txt': 't\n'},
  );
  await repository.worktree.checkout('main');
  final GitOid mainTip = await _commit(
    repository,
    factory,
    'Main work',
    <String, String>{'main.txt': 'm\n'},
  );
  return _Branches(
    repository: repository,
    mainTip: mainTip,
    topicTip: topicTip,
  );
}

/// Builds two branches editing the same line of `a.txt`.
Future<_Branches> _conflictedBranches(BackendFactory factory) async {
  final GitWorkingRepository repository =
      await factory.createWorkingRepository();
  await _commit(repository, factory, 'Base line', <String, String>{
    'a.txt': 'base line\n',
  });
  await repository.worktree.checkoutNewBranch('topic');
  final GitOid topicTip = await _commit(
    repository,
    factory,
    'Topic edit',
    <String, String>{'a.txt': 'topic line\n'},
  );
  await repository.worktree.checkout('main');
  final GitOid mainTip = await _commit(
    repository,
    factory,
    'Main edit',
    <String, String>{'a.txt': 'main line\n'},
  );
  return _Branches(
    repository: repository,
    mainTip: mainTip,
    topicTip: topicTip,
  );
}

/// Writes a tree holding one regular file [path] with [content].
Future<GitOid> _treeWithFile(
  GitRepository repository,
  String path,
  String content,
) async {
  final GitOid blob = await repository.objects.writeObject(
    GitObjectType.blob,
    utf8.encode(content),
  );
  final List<int> serialized = <int>[
    ...utf8.encode('100644 $path'),
    0,
    ..._hexToBytes(blob.value),
  ];
  return repository.objects.writeObject(GitObjectType.tree, serialized);
}

/// Bytes of the hexadecimal object name [hex].
List<int> _hexToBytes(String hex) {
  final List<int> bytes = <int>[];
  for (var index = 0; index < hex.length; index += 2) {
    bytes.add(int.parse(hex.substring(index, index + 2), radix: 16));
  }
  return bytes;
}

/// Writes [files] and commits them as [message] through the factory.
Future<GitOid> _commit(
  GitWorkingRepository repository,
  BackendFactory factory,
  String message,
  Map<String, String> files,
) {
  return factory.commitScenario(
    repository,
    ScenarioCommit(message: message, files: files),
  );
}

/// Object name `HEAD` currently resolves to.
Future<GitOid> _head(GitRepository repository) async {
  return (await repository.revisions.resolveRevision('HEAD'))!;
}
