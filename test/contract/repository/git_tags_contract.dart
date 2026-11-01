import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the `GitTags` contract against [factory].
///
/// Tags are reference-level data, so the operations work the same on a
/// working repository and on a bare one; both are exercised.
void defineGitTagsContract(BackendFactory factory) {
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

  group('GitTags.list contract', () {
    test('lists tags sorted by name, annotated and lightweight', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;

      await repository.tags
          .create('v1', built.commits.last, message: 'Release one');
      await repository.tags.create('start', built.commits[0]);

      final List<GitTagRef> tags = await repository.tags.list();

      expect(tags.map((GitTagRef tag) => tag.name).toList(), <String>[
        'start',
        'v1',
      ]);

      final GitTagRef start = tags.first;
      expect(start.isAnnotated, isFalse);
      expect(start.oid, built.commits[0]);
      expect(start.target, built.commits[0]);

      final GitTagRef v1 = tags.last;
      expect(v1.isAnnotated, isTrue);
      expect(v1.oid, isNot(built.commits.last));
      expect(v1.target, built.commits.last);
    });

    test('reads the content of an annotated tag back through readTag',
        () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;
      final DateTime date = DateTime.utc(2024, 5, 1, 12, 30);

      await repository.tags.create(
        'v1',
        built.commits.last,
        message: 'Release one',
        tagger: GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com'),
        date: date,
      );

      final GitTagRef ref = (await repository.tags.list()).single;
      expect(ref.isAnnotated, isTrue);

      final GitTag tag = await repository.objects.readTag(ref.oid);
      expect(tag.name, 'v1');
      expect(tag.target, built.commits.last);
      expect(tag.message, 'Release one');
      expect(
        tag.tagger,
        GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com'),
      );
      expect(tag.taggerDate, date);
    });
  });

  group('GitTags.create contract', () {
    test('creates a lightweight tag naming its target directly', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;

      await repository.tags.create('start', built.commits[0]);

      expect(
        await repository.refs.resolveRef('refs/tags/start'),
        built.commits[0],
      );
      final GitTagRef ref = (await repository.tags.list()).single;
      expect(ref.isAnnotated, isFalse);
      expect(ref.target, built.commits[0]);
    });

    test('creates an annotated tag on a tree or a commit target', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;
      final GitOid commit = built.commits.last;
      final GitCommit read = await repository.objects.readCommit(commit);

      await repository.tags.create('tree-tag', read.tree, message: 'A tree');

      final GitTagRef ref = (await repository.tags.list()).single;
      expect(ref.isAnnotated, isTrue);
      expect(ref.target, read.tree);
    });

    test('refuses a taken name unless forced, then moves the tag', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;
      await repository.tags.create('v1', built.commits[0]);

      await expectLater(
        repository.tags
            .create('v1', built.commits.last, message: 'Release one'),
        throwsA(isA<GitRefExistsException>().having(
          (GitRefExistsException error) => error.name,
          'name',
          'v1',
        )),
      );
      expect(
        await repository.refs.resolveRef('refs/tags/v1'),
        built.commits[0],
      );

      await repository.tags.create(
        'v1',
        built.commits.last,
        message: 'Release one',
        force: true,
      );
      final GitTagRef ref = (await repository.tags.list()).single;
      expect(ref.target, built.commits.last);
    });

    test('refuses a target that names no object', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;

      await expectLater(
        repository.tags.create('v1', GitOid.parse('a' * 40)),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(await repository.tags.list(), isEmpty);
    });

    test('works in a bare repository', () async {
      final ScenarioRepository built =
          await factory.createBareRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;

      await repository.tags.create(
        'v1',
        built.commits.last,
        message: 'Release one',
        tagger: GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com'),
      );
      await repository.tags.create('start', built.commits[0]);

      expect(
        (await repository.tags.list()).map((GitTagRef tag) => tag.name),
        <String>['start', 'v1'],
      );
    });
  });

  group('GitTags.delete contract', () {
    test('deletes an existing tag, annotated or lightweight', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;
      await repository.tags
          .create('v1', built.commits.last, message: 'Release one');
      await repository.tags.create('start', built.commits[0]);

      await repository.tags.delete('v1');
      await repository.tags.delete('start');

      expect(await repository.tags.list(), isEmpty);
      expect(
        await repository.objects.objectExists(built.commits.last),
        isTrue,
      );
    });

    test('refuses a tag that does not exist', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;

      await expectLater(
        repository.tags.delete('no-such-tag'),
        throwsA(isA<GitRefNotFoundException>().having(
          (GitRefNotFoundException error) => error.name,
          'name',
          'no-such-tag',
        )),
      );
    });

    test('deletes a tag in a bare repository', () async {
      final ScenarioRepository built =
          await factory.createBareRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;
      await repository.tags.create('v1', built.commits.last);

      await repository.tags.delete('v1');

      expect(await repository.tags.list(), isEmpty);
    });
  });
}
