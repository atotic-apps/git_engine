import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

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

/// Declares the [GitRefReader] contract tests for [factory].
///
/// The same suite runs on a working clone and on a bare clone, so the contract
/// is checked in both kinds of repository.
void defineGitRefReaderContract(BackendFactory factory) {
  group('GitRefReader', () {
    _defineRefReaderTests(
      'on a working clone',
      factory.createRepositoryFromScenario,
    );
    _defineRefReaderTests(
      'on a bare clone',
      factory.createBareRepositoryFromScenario,
    );
  });
}

void _defineRefReaderTests(
  String description,
  Future<ScenarioRepository> Function(List<ScenarioCommit>) create,
) {
  group(description, () {
    late ScenarioRepository scenario;
    late GitRefReader refs;

    setUp(() async {
      scenario = await create(_scenario);
      refs = scenario.repository.refs;
    });

    test('resolves HEAD and a non-symbolic reference', () async {
      expect(await refs.resolveRef('HEAD'), scenario.commits.last);
      expect(await refs.resolveRef('refs/heads/main'), scenario.commits.last);
    });

    test('reports the target of a symbolic reference only', () async {
      expect(await refs.symbolicTarget('HEAD'), 'refs/heads/main');
      expect(await refs.symbolicTarget('refs/heads/main'), isNull);
    });

    test('returns null for an absent reference', () async {
      expect(await refs.resolveRef('refs/heads/missing'), isNull);
      expect(await refs.symbolicTarget('refs/heads/missing'), isNull);
    });

    test('does not interpret a revision expression as a reference', () async {
      expect(await refs.resolveRef('HEAD~1'), isNull);
      expect(await refs.resolveRef('refs/heads/main~1'), isNull);
      expect(await refs.resolveRef('refs/heads/main^{tree}'), isNull);
    });

    test('lists references by literal prefix', () async {
      final List<GitRef> all = await refs.listRefs();
      expect(
        all.map((GitRef ref) => ref.name),
        contains('refs/heads/main'),
      );

      final List<GitRef> heads = await refs.listRefs(prefix: 'refs/heads/');
      expect(
        heads.map((GitRef ref) => ref.name),
        <String>['refs/heads/main'],
      );
      expect(heads.single.oid, scenario.commits.last);

      expect(await refs.listRefs(prefix: 'refs/tags/'), isEmpty);
      expect(await refs.listRefs(prefix: 'refs/notes/'), isEmpty);
    });
  });
}
