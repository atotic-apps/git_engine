import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the `GitRefs.resetSoft` contract against [factory].
///
/// Moving `HEAD` with no index or work-tree update is a reference operation,
/// so the suite checks it on a working repository and on a bare one.
void defineGitRefsContract(BackendFactory factory) {
  group('GitRefs.resetSoft contract', () {
    const List<ScenarioCommit> scenario = <ScenarioCommit>[
      ScenarioCommit(
        message: 'First',
        files: <String, String>{'a.txt': 'one\n'},
      ),
      ScenarioCommit(
        message: 'Second',
        files: <String, String>{'a.txt': 'two\n'},
      ),
    ];

    test('moves HEAD on a working repository and keeps the work tree',
        () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;

      await repository.refs.resetSoft(built.commits[0].value);

      expect(
          await repository.revisions.resolveRevision('HEAD'), built.commits[0]);
      expect(await repository.refs.resolveRef('refs/heads/main'),
          built.commits[0]);
      expect(await repository.refs.symbolicTarget('HEAD'), 'refs/heads/main');
      // Only HEAD moved: the index and the work tree still hold the second
      // commit's content, reported as a staged change.
      expect(await repository.worktree.status(), isNotEmpty);
    });

    test('moves the branch HEAD points at on a bare repository', () async {
      final ScenarioRepository built =
          await factory.createBareRepositoryFromScenario(scenario);
      final GitFileBareRepository repository =
          built.repository as GitFileBareRepository;

      expect(await repository.refs.resolveRef('refs/heads/main'),
          built.commits[1]);

      await repository.refs.resetSoft(built.commits[0].value);

      expect(await repository.refs.resolveRef('refs/heads/main'),
          built.commits[0]);
      expect(
          await repository.revisions.resolveRevision('HEAD'), built.commits[0]);
      expect(await repository.refs.symbolicTarget('HEAD'), 'refs/heads/main');
      // The dropped commit is still stored; only the branch moved.
      expect(await repository.objects.objectExists(built.commits[1]), isTrue);
    });
    test('refuses an unknown target with the domain exception', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;

      await expectLater(
        repository.refs.resetSoft('no-such-target'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'no-such-target',
          ),
        ),
      );
      expect(
          await repository.revisions.resolveRevision('HEAD'), built.commits[1]);
    });
  });
}
