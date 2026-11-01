import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../../support/archive_readers.dart';
import '../backend_factory.dart';

/// Declares the archive and message contracts of [GitObjects] against
/// [factory].
///
/// The suite only uses the public facade, so the same cases run unchanged on
/// another backend.
void defineGitObjectsContract(BackendFactory factory) {
  group('GitObjects.archive', () {
    late ScenarioRepository scenario;

    setUp(() async {
      scenario = await factory.createRepositoryFromScenario(
        const <ScenarioCommit>[
          ScenarioCommit(
            message: 'Add the documentation',
            files: <String, String>{
              'top.txt': 'top\n',
              'docs/guide.txt': 'the guide\n',
              'docs/accent/cafe.txt': 'accented\n',
            },
          ),
        ],
      );
    });

    test('streams a tar of a commit with its files', () async {
      final Uint8List bytes = await _collect(
          scenario.repository.objects.archive(scenario.commits.single));

      final Map<String, String> contents = <String, String>{
        for (final ArchiveFileEntry entry in readTarEntries(bytes))
          entry.name: entry.text,
      };
      expect(contents, <String, String>{
        'top.txt': 'top\n',
        'docs/guide.txt': 'the guide\n',
        'docs/accent/cafe.txt': 'accented\n',
      });
    });

    test('streams a zip of a commit with its files', () async {
      final Uint8List bytes = await _collect(
        scenario.repository.objects.archive(
          scenario.commits.single,
          format: GitArchiveFormat.zip,
        ),
      );

      expect(
        readZipNames(bytes).where((String name) => !name.endsWith('/')).toSet(),
        <String>{'top.txt', 'docs/guide.txt', 'docs/accent/cafe.txt'},
      );
    });

    test('archives a subdirectory resolved from a revision expression',
        () async {
      final GitOid docs =
          (await scenario.repository.revisions.resolveRevision('HEAD:docs'))!;
      final Uint8List bytes =
          await _collect(scenario.repository.objects.archive(docs));

      final Map<String, String> contents = <String, String>{
        for (final ArchiveFileEntry entry in readTarEntries(bytes))
          entry.name: entry.text,
      };
      expect(contents, <String, String>{
        'guide.txt': 'the guide\n',
        'accent/cafe.txt': 'accented\n',
      });
    });

    test('reports an unknown object as a stream error', () async {
      final GitRepository repository = scenario.repository;
      final GitOid absent = GitOid.parse('0123456789' * 4);

      await expectLater(
        repository.objects.archive(absent),
        emitsError(isA<GitException>()),
      );
    });
  });

  group('GitObjects.commitTree message', () {
    late GitRepository repository;
    late GitOid tree;

    setUp(() async {
      final ScenarioRepository scenario =
          await factory.createRepositoryFromScenario(
        const <ScenarioCommit>[
          ScenarioCommit(
            message: 'Base',
            files: <String, String>{'a.txt': 'a\n'},
          ),
        ],
      );
      repository = scenario.repository;
      tree =
          (await repository.objects.readCommit(scenario.commits.single)).tree;
    });

    test('keeps trailing spaces, blank lines and comment lines', () async {
      const String message = '\n\nsubject   \n\n\nbody   \n# kept\n\n';
      expect(
        await _storedMessage(repository, tree, message),
        message,
      );
    });

    test('adds one final newline when the message lacks it', () async {
      expect(
        await _storedMessage(repository, tree, 'no final newline'),
        'no final newline\n',
      );
      expect(
        await _storedMessage(repository, tree, 'subject\n\nbody'),
        'subject\n\nbody\n',
      );
    });

    test('keeps a message that already ends with a newline unchanged',
        () async {
      const String message = 'subject\n\nbody\n\n';
      expect(await _storedMessage(repository, tree, message), message);
    });
  });
}

/// Collects [stream] into one byte buffer.
Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// Message recorded in the commit object [message] produces on [tree].
Future<String> _storedMessage(
  GitRepository repository,
  GitOid tree,
  String message,
) async {
  final GitOid oid = await repository.objects.commitTree(
    tree,
    const <GitOid>[],
    message,
  );
  final String raw = utf8.decode(
    (await repository.objects.readObject(oid)).content,
    allowMalformed: true,
  );
  final int separator = raw.indexOf('\n\n');
  expect(separator, isNonNegative);
  return raw.substring(separator + 2);
}
