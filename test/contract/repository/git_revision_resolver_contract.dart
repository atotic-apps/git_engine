import 'dart:convert';

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

/// Declares the [GitRevisionResolver] contract tests for [factory].
///
/// The same suite runs on a working clone and on a bare clone, so the contract
/// is checked in both kinds of repository, and on an empty repository of each
/// kind for the unborn `HEAD` case.
void defineGitRevisionResolverContract(BackendFactory factory) {
  group('GitRevisionResolver', () {
    _defineRevisionResolverTests(
      'on a working clone',
      factory.createRepositoryFromScenario,
    );
    _defineRevisionResolverTests(
      'on a bare clone',
      factory.createBareRepositoryFromScenario,
    );
    _defineEmptyRepositoryTests(
      'on an empty working repository',
      () => factory.createWorkingRepository(),
    );
    _defineEmptyRepositoryTests(
      'on an empty bare repository',
      () => factory.createBareRepository(),
    );
  });
}

void _defineRevisionResolverTests(
  String description,
  Future<ScenarioRepository> Function(List<ScenarioCommit>) create,
) {
  group(description, () {
    late ScenarioRepository scenario;
    late GitRevisionResolver revisions;
    late GitRefs refs;

    setUp(() async {
      scenario = await create(_scenario);
      revisions = scenario.repository.revisions;
      refs = scenario.repository.refs;
    });

    test('resolves a complete and an abbreviated object name', () async {
      final GitOid target = scenario.commits.last;

      expect(await revisions.resolveRevision(target.value), target);
      expect(
        await revisions.resolveRevision(target.value.substring(0, 12)),
        target,
      );
    });

    test('resolves HEAD', () async {
      expect(await revisions.resolveRevision('HEAD'), scenario.commits.last);
    });

    test('resolves full and short reference names in the documented order',
        () async {
      final GitOid target = scenario.commits.first;
      await refs.updateRef('refs/heads/topic', target);
      await refs.updateRef('refs/tags/v1', target);
      await refs.updateRef('refs/remotes/origin/main', scenario.commits[1]);
      await refs.updateRef('refs/remotes/upstream/HEAD', scenario.commits.last);

      expect(await revisions.resolveRevision('refs/heads/topic'), target);
      expect(await revisions.resolveRevision('heads/topic'), target);
      expect(await revisions.resolveRevision('refs/tags/v1'), target);
      expect(await revisions.resolveRevision('v1'), target);
      expect(await revisions.resolveRevision('topic'), target);
      expect(
        await revisions.resolveRevision('origin/main'),
        scenario.commits[1],
      );
      expect(
        await revisions.resolveRevision('upstream'),
        scenario.commits.last,
      );
    });

    test('prefers a tag over a branch for the same short name', () async {
      await refs.updateRef('refs/tags/shared', scenario.commits.first);
      await refs.updateRef('refs/heads/shared', scenario.commits.last);

      expect(
        await revisions.resolveRevision('shared'),
        scenario.commits.first,
      );
    });

    test('resolves the chainable suffixes', () async {
      expect(await revisions.resolveRevision('HEAD~'), scenario.commits[1]);
      expect(await revisions.resolveRevision('HEAD~1'), scenario.commits[1]);
      expect(await revisions.resolveRevision('HEAD~2'), scenario.commits[0]);
      expect(await revisions.resolveRevision('HEAD^'), scenario.commits[1]);
      expect(await revisions.resolveRevision('HEAD^1'), scenario.commits[1]);
      expect(await revisions.resolveRevision('HEAD~1^'), scenario.commits[0]);
    });

    test('resolves the documented peels and a path in a tree', () async {
      final GitOid head = scenario.commits.last;
      final GitCommit commit =
          await scenario.repository.objects.readCommit(head);
      final GitTree tree =
          await scenario.repository.objects.readTree(commit.tree);
      final GitOid blob = tree.entries
          .singleWhere((GitTreeEntry entry) => entry.path == 'a.txt')
          .oid;
      final GitOid annotated = await _writeAnnotatedTag(
        scenario.repository,
        head,
        'release',
      );
      await refs.updateRef('refs/tags/release', annotated);
      await refs.updateRef('refs/tags/blob-tag', blob);

      expect(await revisions.resolveRevision('HEAD^{commit}'), head);
      expect(await revisions.resolveRevision('HEAD^{tree}'), commit.tree);
      expect(await revisions.resolveRevision('HEAD^{}'), head);
      expect(await revisions.resolveRevision('release^{tag}'), annotated);
      expect(await revisions.resolveRevision('release^{}'), head);
      expect(await revisions.resolveRevision('blob-tag^{blob}'), blob);
      expect(await revisions.resolveRevision('HEAD:a.txt'), blob);
    });

    test('resolves the upstream forms', () async {
      final GitOid upstream = scenario.commits[1];
      await refs.updateRef('refs/heads/upstream-target', upstream);
      await scenario.repository.branches.setUpstream('main', 'upstream-target');

      expect(await revisions.resolveRevision('main@{upstream}'), upstream);
      expect(await revisions.resolveRevision('main@{u}'), upstream);
      expect(await revisions.resolveRevision('@{upstream}'), upstream);
      expect(await revisions.resolveRevision('@{u}'), upstream);
    });

    test('returns null when the expression names nothing', () async {
      expect(await revisions.resolveRevision('no-such-revision'), isNull);
      expect(await revisions.resolveRevision('HEAD~99'), isNull);
      expect(
        await revisions.resolveRevision('no-such-revision^{tree}'),
        isNull,
      );
    });
  });
}

void _defineEmptyRepositoryTests(
  String description,
  Future<GitRepository> Function() create,
) {
  group(description, () {
    test('returns null for HEAD and its suffixes without a commit', () async {
      final GitRepository repository = await create();
      final GitRevisionResolver revisions = repository.revisions;

      expect(await revisions.resolveRevision('HEAD'), isNull);
      expect(await revisions.resolveRevision('HEAD~1'), isNull);
      expect(await revisions.resolveRevision('refs/heads/main'), isNull);
    });
  });
}

/// Writes an annotated tag object pointing at [target] and returns its name.
Future<GitOid> _writeAnnotatedTag(
  GitRepository repository,
  GitOid target,
  String name,
) {
  const int seconds = 1700000000;
  final String serialized = 'object ${target.value}\n'
      'type commit\n'
      'tag $name\n'
      'tagger Ada Lovelace <ada@example.com> $seconds +0000\n'
      '\n'
      'Annotated $name\n';
  return repository.objects.writeObject(
    GitObjectType.tag,
    utf8.encode(serialized),
  );
}
