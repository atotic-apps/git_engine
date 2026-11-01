import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the `GitRefTransaction` contract against [factory].
///
/// The suite only goes through the public capabilities of the repository it is
/// given, so the same tests run on every backend.
void refTransactionContractTests(BackendFactory factory) {
  group('GitRefTransaction contract', () {
    for (final _RepositoryKind kind in _RepositoryKind.values) {
      group(kind.label, () {
        test('applies updates, creations and deletions together', () async {
          final GitRepository repository = await _repository(factory, kind);
          final List<GitOid> oids = await _writeObjects(repository, 3);
          await repository.refs.updateRef('refs/heads/updated', oids[0]);
          await repository.refs.updateRef('refs/heads/deleted', oids[0]);

          final GitRefTransaction transaction =
              repository.beginRefTransaction();
          transaction.update(
            'refs/heads/updated',
            oids[1],
            expectedOld: oids[0],
          );
          transaction.create('refs/heads/created', oids[2]);
          transaction.delete('refs/heads/deleted', expectedOld: oids[0]);
          await transaction.commit();

          expect(
              await repository.refs.resolveRef('refs/heads/updated'), oids[1]);
          expect(
              await repository.refs.resolveRef('refs/heads/created'), oids[2]);
          expect(await repository.refs.exists('refs/heads/deleted'), isFalse);
        });

        test('a wrong expected value applies nothing', () async {
          final GitRepository repository = await _repository(factory, kind);
          final List<GitOid> oids = await _writeObjects(repository, 4);
          await repository.refs.updateRef('refs/heads/first', oids[0]);
          await repository.refs.updateRef('refs/heads/second', oids[1]);

          final GitRefTransaction transaction =
              repository.beginRefTransaction();
          transaction.update('refs/heads/first', oids[2], expectedOld: oids[0]);
          transaction.update(
            'refs/heads/second',
            oids[3],
            expectedOld: oids[0],
          );

          await expectLater(transaction.commit(), throwsA(isA<GitException>()));

          expect(await repository.refs.resolveRef('refs/heads/first'), oids[0]);
          expect(
              await repository.refs.resolveRef('refs/heads/second'), oids[1]);
        });

        test('a wrong expected value on a deletion applies nothing', () async {
          final GitRepository repository = await _repository(factory, kind);
          final List<GitOid> oids = await _writeObjects(repository, 2);
          await repository.refs.updateRef('refs/heads/kept', oids[0]);

          final GitRefTransaction transaction =
              repository.beginRefTransaction();
          transaction.delete('refs/heads/kept', expectedOld: oids[1]);

          await expectLater(transaction.commit(), throwsA(isA<GitException>()));

          expect(await repository.refs.resolveRef('refs/heads/kept'), oids[0]);
        });

        test('creates and deletes refs', () async {
          final GitRepository repository = await _repository(factory, kind);
          final List<GitOid> oids = await _writeObjects(repository, 2);

          final GitRefTransaction creation = repository.beginRefTransaction();
          creation.create('refs/heads/topic', oids[0]);
          await creation.commit();
          expect(await repository.refs.resolveRef('refs/heads/topic'), oids[0]);

          final GitRefTransaction deletion = repository.beginRefTransaction();
          deletion.delete('refs/heads/topic', expectedOld: oids[0]);
          await deletion.commit();
          expect(await repository.refs.exists('refs/heads/topic'), isFalse);
        });

        test('a refused creation leaves every ref untouched', () async {
          final GitRepository repository = await _repository(factory, kind);
          final List<GitOid> oids = await _writeObjects(repository, 2);
          await repository.refs.updateRef('refs/heads/existing', oids[0]);

          final GitRefTransaction transaction =
              repository.beginRefTransaction();
          transaction.create('refs/heads/existing', oids[1]);
          transaction.create('refs/heads/other', oids[1]);

          await expectLater(transaction.commit(), throwsA(isA<GitException>()));

          expect(
              await repository.refs.resolveRef('refs/heads/existing'), oids[0]);
          expect(await repository.refs.exists('refs/heads/other'), isFalse);
        });
      });
    }
  });
}

/// The two repository shapes the transaction must support.
enum _RepositoryKind {
  /// A bare repository with no work tree.
  bare('bare repository'),

  /// A repository with a work tree, as a clone has.
  clone('clone');

  const _RepositoryKind(this.label);

  /// Human-readable name used in the test group.
  final String label;
}

/// Builds a fresh repository of [kind] through [factory].
Future<GitRepository> _repository(
  BackendFactory factory,
  _RepositoryKind kind,
) async {
  switch (kind) {
    case _RepositoryKind.bare:
      return factory.createBareRepository();
    case _RepositoryKind.clone:
      const List<ScenarioCommit> scenario = <ScenarioCommit>[
        ScenarioCommit(
          message: 'Add the base file',
          files: <String, String>{'base.txt': 'base\n'},
        ),
        ScenarioCommit(
          message: 'Change the base file',
          files: <String, String>{'base.txt': 'changed\n'},
        ),
      ];
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      return built.repository;
  }
}

/// Writes [count] distinct commits and returns their object names.
Future<List<GitOid>> _writeObjects(
  GitRepository repository,
  int count,
) async {
  final GitOid tree = await repository.objects.writeObject(
    GitObjectType.tree,
    const <int>[],
  );
  final GitIdentity identity = GitIdentity(
    name: 'Contract Test',
    email: 'contract@example.com',
  );
  final List<GitOid> commits = <GitOid>[];
  for (var index = 0; index < count; index++) {
    final GitOid commit = await repository.objects.commitTree(
      tree,
      const <GitOid>[],
      'transaction object $index',
      author: identity,
      committer: identity,
    );
    commits.add(commit);
  }
  return commits;
}
