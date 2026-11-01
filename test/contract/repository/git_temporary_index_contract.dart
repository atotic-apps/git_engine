import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the `GitRepository.withTemporaryIndex` contract against [factory].
///
/// The suite runs on file-backed repositories: it checks that the temporary
/// index starts empty or from a tree, that a commit can be fabricated on a
/// bare repository without growing an index file, and that the clone's own
/// `.git/index` never changes. Removing the temporary index after success or
/// failure is verified by the process backend, where its location is visible.
void defineGitTemporaryIndexContract(BackendFactory factory) {
  group('withTemporaryIndex', () {
    test('passes a working repository to the action of a working repository',
        () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();

      final GitOid tree = await repository.withTemporaryIndex<GitOid>(
        (GitWorkingRepository indexed) async => indexed.index.writeTree(),
      );

      expect((await repository.objects.readTree(tree)).entries, isEmpty);
    });

    test('starts from the given tree', () async {
      final ScenarioRepository scenario =
          await factory.createBareRepositoryFromScenario(const <ScenarioCommit>[
        ScenarioCommit(
          message: 'Root',
          files: <String, String>{'base.txt': 'base\n'},
        ),
      ]);
      final GitRepository repository = scenario.repository;
      final GitOid baseTree =
          (await repository.objects.readCommit(scenario.commits.single)).tree;

      final GitOid tree = await repository.withTemporaryIndex<GitOid>(
        (GitIndexedRepository indexed) async {
          final GitTree loaded =
              await indexed.objects.readTree(await indexed.index.writeTree());
          expect(loaded.entries.single.path, 'base.txt');
          return indexed.index.writeTree();
        },
        fromTree: baseTree,
      );

      expect(tree, baseTree);
    });

    test('fabricates a commit on a bare repository', () async {
      final ScenarioRepository scenario =
          await factory.createBareRepositoryFromScenario(const <ScenarioCommit>[
        ScenarioCommit(
          message: 'Root',
          files: <String, String>{'base.txt': 'base\n'},
        ),
      ]);
      final GitRepository repository = scenario.repository;
      final GitOid parent = scenario.commits.single;
      final GitOid baseTree =
          (await repository.objects.readCommit(parent)).tree;
      final GitIdentity identity = GitIdentity(
        name: 'Temporary Index',
        email: 'temporary-index@example.com',
      );

      final GitOid fabricated = await repository.withTemporaryIndex<GitOid>(
        (GitIndexedRepository indexed) async {
          final GitOid tree = await indexed.index.writeTree();
          return indexed.objects.commitTree(
            tree,
            <GitOid>[parent],
            'Fabricated on a bare repository\n',
            author: identity,
            committer: identity,
          );
        },
        fromTree: baseTree,
      );

      final GitCommit commit = await repository.objects.readCommit(fabricated);
      expect(commit.tree, baseTree);
      expect(commit.parents, <GitOid>[parent]);
      expect(commit.message, 'Fabricated on a bare repository');
      expect(
        await repository.objects.objectType(fabricated),
        GitObjectType.commit,
      );
    });

    test('leaves the .git/index of a clone unchanged', () async {
      final ScenarioRepository origin =
          await factory.createBareRepositoryFromScenario(const <ScenarioCommit>[
        ScenarioCommit(
          message: 'Root',
          files: <String, String>{'tracked.txt': 'one\n'},
        ),
      ]);
      final GitWorkingRepository clone = await factory.cloneRepository(
        origin.repository as GitFileBareRepository,
      );
      final GitOid baseTree =
          (await origin.repository.objects.readCommit(origin.commits.single))
              .tree;
      final File ownIndex = File(_join(await clone.gitDir(), 'index'));
      final List<int> before = ownIndex.readAsBytesSync();

      final GitOid tree = await clone.withTemporaryIndex<GitOid>(
        (GitWorkingRepository indexed) => indexed.index.writeTree(),
        fromTree: baseTree,
      );

      expect(tree, baseTree);
      expect(ownIndex.readAsBytesSync(), before);
      expect(await clone.worktree.isClean(), isTrue);
    });

    test('creates no index file in a bare repository', () async {
      final GitFileBareRepository repository =
          await factory.createBareRepository();
      final File ownIndex = File(_join(await repository.gitDir(), 'index'));
      expect(ownIndex.existsSync(), isFalse);

      await repository.withTemporaryIndex<void>(
        (GitIndexedRepository indexed) async {
          await indexed.index.writeTree();
          expect(
            ownIndex.existsSync(),
            isFalse,
            reason: 'the temporary index lives outside the git directory',
          );
        },
      );

      expect(ownIndex.existsSync(), isFalse);
    });
  });
}

/// Joins [base] and [relative] with the platform separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}
