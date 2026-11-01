import 'dart:convert';
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the `GitIndex` contract against [factory].
///
/// The suite asks the factory for repositories whose explicit index view is
/// already prepared, then reads and writes that index only through [GitIndex]
/// and [GitObjects], so the same cases run on working and bare repositories.
void defineGitIndexContract(BackendFactory factory) {
  group('GitIndex', () {
    for (final IndexedRepositoryKind kind in IndexedRepositoryKind.values) {
      group(kind.label, () {
        test('writes the tree of the active index', () async {
          final GitIndexedRepository repository =
              await factory.createIndexedRepository(
            kind,
            files: <String, String>{
              'app.txt': 'hello\n',
              'nested/note.txt': 'note\n',
            },
          );

          final GitOid oid = await repository.index.writeTree();
          final GitTree tree = await repository.objects.readTree(oid);

          expect(tree.oid, oid);
          expect(
            tree.entries.map((GitTreeEntry entry) => entry.path).toList(),
            <String>['app.txt', 'nested'],
          );
          final GitTree nested = await repository.objects.readTree(
            tree.entries
                .singleWhere((GitTreeEntry entry) => entry.path == 'nested')
                .oid,
          );
          expect(nested.entries.single.path, 'note.txt');
          expect(nested.entries.single.type, GitObjectType.blob);
        });

        test('loads a tree into the active index', () async {
          final GitIndexedRepository repository =
              await factory.createIndexedRepository(
            kind,
            files: <String, String>{'tracked.txt': 'one\n'},
          );
          final GitOid tree = await _treeWithFile(
            repository,
            'loaded.txt',
            'loaded\n',
          );
          expect(await repository.index.writeTree(), isNot(tree));

          await repository.index.readTree(tree);

          expect(await repository.index.writeTree(), tree);
        });

        test('leaves .git/index unchanged on a temporary index', () async {
          final GitIndexedRepository repository =
              await factory.createIndexedRepository(
            kind,
            files: <String, String>{'tracked.txt': 'one\n'},
          );
          final GitOid tree = await _treeWithFile(
            repository,
            'loaded.txt',
            'loaded\n',
          );
          final GitFileRepository fileRepository =
              repository as GitFileRepository;
          final File ownIndex =
              File(_join(await fileRepository.gitDir(), 'index'));
          final List<int>? before =
              ownIndex.existsSync() ? ownIndex.readAsBytesSync() : null;

          await repository.withTemporaryIndex<void>(
            (GitIndexedRepository indexed) async {
              await indexed.index.readTree(tree);
              expect(await indexed.index.writeTree(), tree);
            },
          );

          expect(ownIndex.existsSync(), before != null);
          if (before != null) {
            expect(ownIndex.readAsBytesSync(), before);
          }
        });

        test('refuses an unknown object and leaves the index unchanged',
            () async {
          final GitIndexedRepository repository =
              await factory.createIndexedRepository(
            kind,
            files: <String, String>{'tracked.txt': 'one\n'},
          );
          final GitOid before = await repository.index.writeTree();

          await expectLater(
            repository.index.readTree(
              GitOid.parse('9999999999999999999999999999999999999999'),
            ),
            throwsA(isA<GitException>()),
          );

          expect(await repository.index.writeTree(), before);
        });

        test('refuses a blob and leaves the index unchanged', () async {
          final GitIndexedRepository repository =
              await factory.createIndexedRepository(
            kind,
            files: <String, String>{'tracked.txt': 'one\n'},
          );
          final GitOid blob = await repository.objects.writeObject(
            GitObjectType.blob,
            utf8.encode('not a tree\n'),
          );
          final GitOid before = await repository.index.writeTree();

          await expectLater(
            repository.index.readTree(blob),
            throwsA(isA<GitException>()),
          );

          expect(await repository.index.writeTree(), before);
        });

        test('refuses a commit and leaves the index unchanged', () async {
          final GitIndexedRepository repository =
              await factory.createIndexedRepository(
            kind,
            files: <String, String>{'tracked.txt': 'one\n'},
          );
          final GitOid tree = await _treeWithFile(
            repository,
            'loaded.txt',
            'loaded\n',
          );
          final GitIdentity identity = GitIdentity(
            name: 'Index Fixture',
            email: 'index-fixture@example.com',
          );
          final GitOid commit = await repository.objects.commitTree(
            tree,
            const <GitOid>[],
            'Not a tree\n',
            author: identity,
            committer: identity,
          );
          final GitOid before = await repository.index.writeTree();

          await expectLater(
            repository.index.readTree(commit),
            throwsA(isA<GitException>()),
          );

          expect(await repository.index.writeTree(), before);
        });

        test('removes a file from the index without touching a work tree',
            () async {
          final GitIndexedRepository repository =
              await factory.createIndexedRepository(
            kind,
            files: <String, String>{
              'tracked.txt': 'one\n',
              'dir/nested.txt': 'content\n',
            },
          );

          await repository.index.remove(<String>['tracked.txt']);

          final GitTree tree = await repository.objects.readTree(
            await repository.index.writeTree(),
          );
          expect(
            tree.entries.map((GitTreeEntry entry) => entry.path).toList(),
            <String>['dir'],
          );
          if (repository is GitWorkingRepository) {
            final List<GitStatusEntry> entries =
                await repository.worktree.status();
            expect(
              entries.any((GitStatusEntry entry) =>
                  entry.path == 'tracked.txt' && entry.isDeleted),
              isTrue,
              reason: 'removing from the index is a staged deletion',
            );
            expect(
              entries.any((GitStatusEntry entry) =>
                  entry.path == 'tracked.txt' && entry.isUntracked),
              isTrue,
              reason: 'the file left in place is untracked',
            );
          }
        });

        test('ignores missing paths', () async {
          final GitIndexedRepository repository =
              await factory.createIndexedRepository(
            kind,
            files: <String, String>{'tracked.txt': 'one\n'},
          );
          final GitOid before = await repository.index.writeTree();

          await repository.index.remove(<String>['missing.txt']);

          expect(await repository.index.writeTree(), before);
        });

        test('does nothing without paths', () async {
          final GitIndexedRepository repository =
              await factory.createIndexedRepository(
            kind,
            files: <String, String>{'tracked.txt': 'one\n'},
          );
          final GitOid before = await repository.index.writeTree();

          await repository.index.remove(const <String>[]);

          expect(await repository.index.writeTree(), before);
        });

        test('removes a directory recursively when asked', () async {
          final GitIndexedRepository repository =
              await factory.createIndexedRepository(
            kind,
            files: <String, String>{
              'dir/nested.txt': 'content\n',
              'other.txt': 'other\n',
            },
          );

          await repository.index.remove(<String>['dir'], recursive: true);

          final GitTree tree = await repository.objects.readTree(
            await repository.index.writeTree(),
          );
          expect(
            tree.entries.map((GitTreeEntry entry) => entry.path).toList(),
            <String>['other.txt'],
          );
          if (repository is GitWorkingRepository) {
            final List<GitStatusEntry> entries =
                await repository.worktree.status();
            expect(
              entries.any((GitStatusEntry entry) =>
                  entry.path == 'dir/nested.txt' && entry.isDeleted),
              isTrue,
              reason: 'the directory is removed from the index',
            );
            expect(
              entries.any((GitStatusEntry entry) =>
                  entry.isUntracked && entry.path.startsWith('dir/')),
              isTrue,
              reason: 'the files left in place are untracked',
            );
          }
        });

        test('lists the three stages of a real conflict', () async {
          final GitIndexedRepository repository =
              await factory.createConflictedIndexedRepository(
            kind,
            path: 'shared.txt',
          );

          final List<GitUnmergedEntry> entries =
              await repository.index.unmergedEntries();

          expect(entries, hasLength(3));
          expect(
            entries.map((GitUnmergedEntry entry) => entry.stage).toList(),
            <int>[1, 2, 3],
          );
          expect(
            entries.map((GitUnmergedEntry entry) => entry.path).toSet(),
            <String>{'shared.txt'},
          );
          expect(
            entries.map((GitUnmergedEntry entry) => entry.mode).toSet(),
            <String>{'100644'},
          );
          expect(
            entries.map((GitUnmergedEntry entry) => entry.oid).toSet(),
            hasLength(3),
          );

          final List<String> contents = <String>[];
          for (final GitUnmergedEntry entry in entries) {
            contents.add(utf8.decode(
              await repository.objects.readBlob(entry.oid),
            ));
          }
          expect(contents, <String>['base\n', 'main\n', 'other\n']);
        });

        test('reports an empty list on a clean index', () async {
          final GitIndexedRepository repository =
              await factory.createIndexedRepository(
            kind,
            files: <String, String>{'tracked.txt': 'one\n'},
          );

          expect(await repository.index.unmergedEntries(), isEmpty);
        });
      });
    }
  });
}

/// Writes a tree holding [name] with [content] and returns its object name.
Future<GitOid> _treeWithFile(
  GitRepository repository,
  String name,
  String content,
) async {
  final GitOid blob = await repository.objects.writeObject(
    GitObjectType.blob,
    utf8.encode(content),
  );
  final List<int> entry = <int>[...utf8.encode('100644 $name'), 0];
  for (var index = 0; index < blob.value.length; index += 2) {
    entry.add(int.parse(blob.value.substring(index, index + 2), radix: 16));
  }
  return repository.objects.writeObject(GitObjectType.tree, entry);
}

/// Joins [base] and [relative] with the platform separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}
