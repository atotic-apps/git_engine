import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Runs the `GitObjectReader` contract against the repositories [factory]
/// builds.
///
/// The suite only talks to the interfaces of the backend under test and to the
/// factory: it never launches git itself, so the same cases can run unchanged
/// on another backend.
void runGitObjectReaderContract(BackendFactory factory) {
  group('GitObjectReader contract', () {
    test('reads a binary blob exactly, raw object included', () async {
      final GitRepository repository = await factory.createWorkingRepository();
      final GitObjectReader reader = repository.objects;
      final Uint8List bytes = Uint8List.fromList(<int>[
        for (int value = 0; value < 256; value++) value,
        0x0d,
        0x0a,
        0x00,
        0xff,
      ]);
      final GitOid oid = await repository.objects.writeObject(
        GitObjectType.blob,
        bytes,
      );

      expect(await reader.objectExists(oid), isTrue);
      expect(await reader.objectType(oid), GitObjectType.blob);
      expect(await reader.readBlob(oid), bytes);

      final GitRawObject raw = await reader.readObject(oid);
      expect(raw.type, GitObjectType.blob);
      expect(raw.content, bytes);
    });

    test('reads a tree with a subdirectory', () async {
      final ScenarioRepository scenario =
          await factory.createRepositoryFromScenario(const <ScenarioCommit>[
        ScenarioCommit(
          message: 'Add the documentation',
          files: <String, String>{
            'README.md': 'readme\n',
            'docs/guide.txt': 'the guide\n',
          },
        ),
      ]);
      final GitRepository repository = scenario.repository;
      final GitObjectReader reader = repository.objects;
      final GitCommit commit = await reader.readCommit(scenario.commits.single);

      final GitTree root = await reader.readTree(commit.tree);
      expect(root.oid, commit.tree);
      expect(
        root.entries.map((GitTreeEntry entry) => entry.path).toList(),
        <String>['README.md', 'docs'],
      );
      final GitTreeEntry docsEntry = root.entries
          .singleWhere((GitTreeEntry entry) => entry.path == 'docs');
      expect(docsEntry.type, GitObjectType.tree);

      final GitTree docs = await reader.readTree(docsEntry.oid);
      expect(docs.oid, docsEntry.oid);
      expect(docs.entries.single.path, 'guide.txt');
      expect(docs.entries.single.type, GitObjectType.blob);
      expect(
        utf8.decode(await reader.readBlob(docs.entries.single.oid)),
        'the guide\n',
      );
    });

    test('reads a merge commit with two parents, identities and dates',
        () async {
      final ScenarioRepository scenario =
          await factory.createRepositoryFromScenario(const <ScenarioCommit>[
        ScenarioCommit(
          message: 'Add a',
          files: <String, String>{'a.txt': 'a\n'},
        ),
        ScenarioCommit(
          message: 'Add b',
          files: <String, String>{'b.txt': 'b\n'},
        ),
      ]);
      final GitRepository repository = scenario.repository;
      final GitObjectReader reader = repository.objects;
      final GitOid first = scenario.commits.first;
      final GitOid second = scenario.commits.last;
      final GitCommit secondCommit = await reader.readCommit(second);

      final GitIdentity author =
          GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com');
      final GitIdentity committer =
          GitIdentity(name: 'Grace Hopper', email: 'grace@example.com');
      final DateTime authorDate = DateTime.utc(2021, 6, 1, 12, 30, 45);
      final DateTime committerDate = DateTime.utc(2021, 6, 2, 8, 5, 10);
      final GitOid merge = await repository.objects.commitTree(
        secondCommit.tree,
        <GitOid>[first, second],
        'Merge the two lines\n\nDetails here\n',
        author: author,
        committer: committer,
        authorDate: authorDate,
        committerDate: committerDate,
      );

      final GitCommit commit = await reader.readCommit(merge);
      expect(await reader.objectType(merge), GitObjectType.commit);
      expect(commit.tree, secondCommit.tree);
      expect(commit.parents, <GitOid>[first, second]);
      expect(commit.author, author);
      expect(commit.committer, committer);
      expect(commit.authorDate, authorDate);
      expect(commit.committerDate, committerDate);
      expect(commit.message, 'Merge the two lines\n\nDetails here');
    });

    test('reads an annotated tag', () async {
      final ScenarioRepository scenario =
          await factory.createRepositoryFromScenario(const <ScenarioCommit>[
        ScenarioCommit(
          message: 'Tag me',
          files: <String, String>{'a.txt': 'a\n'},
        ),
      ]);
      final GitRepository repository = scenario.repository;
      final GitObjectReader reader = repository.objects;
      final GitOid target = scenario.commits.single;
      final GitIdentity tagger =
          GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com');
      final DateTime taggerDate = DateTime.utc(2024, 1, 2, 3, 4, 5);
      final int seconds = taggerDate.millisecondsSinceEpoch ~/ 1000;
      final String serialized = 'object ${target.value}\n'
          'type commit\n'
          'tag v1.0.0\n'
          'tagger ${tagger.name} <${tagger.email}> $seconds +0000\n'
          '\n'
          'First release\n';
      final GitOid oid = await repository.objects.writeObject(
        GitObjectType.tag,
        utf8.encode(serialized),
      );

      expect(await reader.objectType(oid), GitObjectType.tag);
      final GitTag tag = await reader.readTag(oid);
      expect(tag.target, target);
      expect(tag.targetType, GitObjectType.commit);
      expect(tag.name, 'v1.0.0');
      expect(tag.tagger, tagger);
      expect(tag.taggerDate, taggerDate);
      expect(tag.message, 'First release');

      final GitRawObject raw = await reader.readObject(oid);
      expect(raw.type, GitObjectType.tag);
      expect(raw.content, utf8.encode(serialized));
    });

    test('reports an absent object without throwing for existence and type',
        () async {
      final GitRepository repository = await factory.createWorkingRepository();
      final GitObjectReader reader = repository.objects;
      final GitOid absent = GitOid.parse('0123456789' * 4);

      expect(await reader.objectExists(absent), isFalse);
      expect(await reader.objectType(absent), isNull);
      expect(
        () => reader.readObject(absent),
        throwsA(isA<GitException>()),
      );
      expect(
        () => reader.readBlob(absent),
        throwsA(isA<GitException>()),
      );
      expect(
        () => reader.readTree(absent),
        throwsA(isA<GitException>()),
      );
      expect(
        () => reader.readCommit(absent),
        throwsA(isA<GitException>()),
      );
      expect(
        () => reader.readTag(absent),
        throwsA(isA<GitException>()),
      );
    });

    test('reads in a bare repository and in a clone', () async {
      final GitRepository bare = await factory.createBareRepository();
      final GitOid bareBlob = await bare.objects.writeObject(
        GitObjectType.blob,
        utf8.encode('bare content\n'),
      );
      expect(await bare.objects.objectExists(bareBlob), isTrue);
      expect(await bare.objects.objectType(bareBlob), GitObjectType.blob);
      expect(
        utf8.decode(await bare.objects.readBlob(bareBlob)),
        'bare content\n',
      );

      final ScenarioRepository scenario =
          await factory.createRepositoryFromScenario(const <ScenarioCommit>[
        ScenarioCommit(
          message: 'Shared history',
          files: <String, String>{'shared.txt': 'shared\n'},
        ),
      ]);
      final GitRepository clone = await factory.cloneRepository(
        scenario.repository as GitFileRepository,
      );
      final GitCommit commit =
          await clone.objects.readCommit(scenario.commits.single);
      expect(commit.message, 'Shared history');
      final GitTree tree = await clone.objects.readTree(commit.tree);
      final GitTreeEntry entry = tree.entries.single;
      expect(entry.path, 'shared.txt');
      expect(utf8.decode(await clone.objects.readBlob(entry.oid)), 'shared\n');
    });
  });
}
