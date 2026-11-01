import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the `GitRepositoryWriter` contract against [factory].
///
/// Every operation of the suite goes through the narrow contract: it builds
/// objects and commits with [GitObjectStore.writeObject], moves references
/// with [GitRepositoryWriter.beginRefTransaction], and reads back with
/// [GitObjectReader], [GitRefReader] and [GitHistoryReader]. It never uses a
/// work tree, a revision expression or a configuration accessor, so the same
/// cases run unchanged on any backend.
void defineGitRepositoryWriterContract(BackendFactory factory) {
  group('GitRepositoryWriter', () {
    for (final _RepositoryKind kind in _RepositoryKind.values) {
      group(kind.label, () {
        late GitRepositoryWriter writer;

        setUp(() async {
          final GitRepository repository = await kind.create(factory);
          writer = repository;
        });

        test('writes objects and moves a reference atomically', () async {
          final GitObjectStore store = writer.objects;
          final GitOid blob = await store.writeObject(
            GitObjectType.blob,
            utf8.encode('narrow contract\n'),
          );
          final GitOid tree = await store.writeObject(
            GitObjectType.tree,
            _treeEntry('contract.txt', blob),
          );
          final GitOid commit = await store.writeObject(
            GitObjectType.commit,
            _commitContent(tree, message: 'Written through the writer'),
          );

          final GitRefTransaction transaction = writer.beginRefTransaction();
          transaction.create('refs/heads/written', commit);
          await transaction.commit();

          expect(await writer.refs.resolveRef('refs/heads/written'), commit);
          expect(await store.objectExists(blob), isTrue);
          expect(await store.objectType(commit), GitObjectType.commit);

          final GitCommit readCommit = await store.readCommit(commit);
          expect(readCommit.tree, tree);
          expect(readCommit.message, 'Written through the writer');
          final GitTree readTree = await store.readTree(tree);
          expect(readTree.entries.single.path, 'contract.txt');
          expect(readTree.entries.single.oid, blob);
          expect(utf8.decode(await store.readBlob(blob)), 'narrow contract\n');
        });

        test('walks the history it wrote', () async {
          final GitObjectStore store = writer.objects;
          final GitOid tree = await store.writeObject(
            GitObjectType.tree,
            const <int>[],
          );
          final GitOid root = await store.writeObject(
            GitObjectType.commit,
            _commitContent(tree, message: 'Root'),
          );
          final GitOid child = await store.writeObject(
            GitObjectType.commit,
            _commitContent(tree, parent: root, message: 'Child'),
          );
          final GitOid other = await store.writeObject(
            GitObjectType.commit,
            _commitContent(tree, message: 'Other root'),
          );

          final GitHistoryReader history = writer.history;
          expect(await history.isAncestor(root, child), isTrue);
          expect(await history.isAncestor(child, root), isFalse);
          expect(await history.mergeBase(child, root), root);
          expect(await history.mergeBase(child, other), isNull);
        });
      });
    }
  });
}

/// The two repository shapes the writer contract runs on.
enum _RepositoryKind {
  /// A repository with a work tree and an active index.
  working('working repository'),

  /// A bare repository with no work tree.
  bare('bare repository');

  const _RepositoryKind(this.label);

  /// Human-readable name used in the test group.
  final String label;

  /// Builds a fresh repository of this shape through [factory].
  Future<GitRepository> create(BackendFactory factory) {
    switch (this) {
      case _RepositoryKind.working:
        return factory.createWorkingRepository();
      case _RepositoryKind.bare:
        return factory.createBareRepository();
    }
  }
}

/// Serialized content of a tree holding one blob entry.
List<int> _treeEntry(String name, GitOid oid) {
  final List<int> content = <int>[...utf8.encode('100644 $name'), 0];
  for (var index = 0; index < oid.value.length; index += 2) {
    content.add(int.parse(oid.value.substring(index, index + 2), radix: 16));
  }
  return content;
}

/// Serialized content of a commit pointing at [tree].
List<int> _commitContent(
  GitOid tree, {
  GitOid? parent,
  required String message,
}) {
  final StringBuffer buffer = StringBuffer('tree ${tree.value}\n');
  if (parent != null) {
    buffer.write('parent ${parent.value}\n');
  }
  buffer
    ..write('author Contract Writer <writer@example.com> 1622550645 +0000\n')
    ..write('committer Contract Writer <writer@example.com> 1622550645 +0000\n')
    ..write('\n')
    ..write('$message\n');
  return utf8.encode(buffer.toString());
}
