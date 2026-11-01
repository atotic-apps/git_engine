import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the contract of [GitObjectWriter] against [factory].
///
/// The suite builds every object through [GitObjectWriter.writeObject] and
/// reads it back through the repository's object accessors, so it stays on
/// library interfaces and runs unchanged on any backend.
void defineGitObjectWriterContract(BackendFactory factory) {
  group('GitObjectWriter', () {
    late GitRepository repository;
    late GitObjectWriter writer;

    setUp(() async {
      repository = await factory.createWorkingRepository();
      writer = repository.objects;
    });

    test('writes a blob and hashObject leaves it unwritten', () async {
      final List<int> content = utf8.encode('blob content\n');

      final GitOid computed = await repository.objects.hashObject(content);
      expect(await repository.objects.objectExists(computed), isFalse);
      expect(await repository.objects.objectType(computed), isNull);

      final GitOid written =
          await writer.writeObject(GitObjectType.blob, content);
      expect(written, computed);
      expect(await repository.objects.objectExists(written), isTrue);
      expect(
        await repository.objects.objectType(written),
        GitObjectType.blob,
      );
    });

    test('writes a tree', () async {
      final GitOid blob = await writer.writeObject(
        GitObjectType.blob,
        utf8.encode('hello\n'),
      );
      final List<int> content = _treeEntry('100644', 'hello.txt', blob);

      final GitOid tree = await writer.writeObject(GitObjectType.tree, content);

      expect(
        await repository.objects.objectType(tree),
        GitObjectType.tree,
      );
      final GitTree read = await repository.objects.readTree(tree);
      expect(read.oid, tree);
      expect(read.entries, hasLength(1));
      expect(read.entries.single.path, 'hello.txt');
      expect(read.entries.single.type, GitObjectType.blob);
      expect(read.entries.single.mode, '100644');
      expect(read.entries.single.oid, blob);
    });

    test('writes a commit', () async {
      final GitOid blob =
          await writer.writeObject(GitObjectType.blob, utf8.encode('hello\n'));
      final GitOid tree = await writer.writeObject(
        GitObjectType.tree,
        _treeEntry('100644', 'hello.txt', blob),
      );

      final GitOid commit =
          await writer.writeObject(GitObjectType.commit, _commitContent(tree));

      expect(
        await repository.objects.objectType(commit),
        GitObjectType.commit,
      );
      final GitCommit readCommit = await repository.objects.readCommit(commit);
      expect(readCommit.message, 'A fabricated commit');
      expect(readCommit.parents, isEmpty);
      final GitTree read = await repository.objects.readTree(readCommit.tree);
      expect(read.oid, tree);
      expect(read.entries.single.oid, blob);
    });

    test('writes an annotated tag', () async {
      final GitOid blob =
          await writer.writeObject(GitObjectType.blob, utf8.encode('hello\n'));
      final GitOid tree = await writer.writeObject(
        GitObjectType.tree,
        _treeEntry('100644', 'hello.txt', blob),
      );
      final GitOid commit =
          await writer.writeObject(GitObjectType.commit, _commitContent(tree));

      final GitOid tag = await writer.writeObject(
        GitObjectType.tag,
        _tagContent(commit),
      );

      expect(await repository.objects.objectType(tag), GitObjectType.tag);
      final GitTag readTag = await repository.objects.readTag(tag);
      expect(readTag.target, commit);
      final GitCommit tagged = await repository.objects.readCommit(commit);
      final GitTree peeled = await repository.objects.readTree(tagged.tree);
      expect(peeled.oid, tree);
      expect(peeled.entries.single.oid, blob);
    });

    test('refuses content that is invalid for the type', () async {
      await expectLater(
        writer.writeObject(
          GitObjectType.commit,
          utf8.encode('this is not a commit\n'),
        ),
        throwsA(
          isA<GitInvalidObjectException>().having(
            (GitInvalidObjectException error) => error.type,
            'type',
            GitObjectType.commit,
          ),
        ),
      );
      await expectLater(
        writer.writeObject(
          GitObjectType.tree,
          utf8.encode('this is not a tree\n'),
        ),
        throwsA(isA<GitInvalidObjectException>()),
      );
    });
  });
}

/// Serialized content of a tree holding one file.
List<int> _treeEntry(String mode, String name, GitOid oid) {
  final List<int> content = <int>[...utf8.encode('$mode $name'), 0];
  for (var index = 0; index < oid.value.length; index += 2) {
    content.add(int.parse(oid.value.substring(index, index + 2), radix: 16));
  }
  return content;
}

/// Serialized content of a commit without parents.
List<int> _commitContent(GitOid tree) {
  return utf8.encode(
    'tree ${tree.value}\n'
    'author Ada Lovelace <ada@example.com> 1622550645 +0000\n'
    'committer Grace Hopper <grace@example.com> 1622637045 +0000\n'
    '\n'
    'A fabricated commit\n',
  );
}

/// Serialized content of an annotated tag pointing at [commit].
List<int> _tagContent(GitOid commit) {
  return utf8.encode(
    'object ${commit.value}\n'
    'type commit\n'
    'tag v1\n'
    'tagger Ada Lovelace <ada@example.com> 1622550645 +0000\n'
    '\n'
    'Release v1\n',
  );
}
