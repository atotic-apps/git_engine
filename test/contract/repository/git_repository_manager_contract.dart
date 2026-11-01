import 'dart:convert';
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the typed opening and creation contract of [GitRepositoryManager].
///
/// The type of a repository is fixed when it is opened, from git's answer, so
/// every call that knows the expected kind returns it directly. The suite
/// builds its own working and bare repositories on disk, and checks both the
/// returned types and the typed refusals of the mismatched accessors.
void defineGitRepositoryManagerContract(BackendFactory factory) {
  group('GitRepositoryManager', () {
    late EngineSandbox sandbox;
    late GitRepositoryManager manager;

    setUp(() async {
      sandbox = await factory.createEngineSandbox();
      manager = sandbox.manager;
    });

    group('open', () {
      test('a clone opens as a working repository', () async {
        final GitFileBareRepository source =
            await _sourceWithCommit(manager, sandbox.newPath('source.git'));
        final GitWorkingRepository clone = await sandbox.client.clone(
          source.path,
          sandbox.newPath('clone'),
        );

        final GitFileRepository opened = await manager.open(clone.path);

        expect(opened, isA<GitWorkingRepository>());
        expect(opened, isA<GitIndexedRepository>());
        expect(opened, isA<GitFileRepository>());
        expect(opened, isNot(isA<GitBareRepository>()));
        expect(
          await (opened as GitWorkingRepository).toplevel(),
          isNotEmpty,
        );
      });

      test('a bare repository opens as a file bare repository', () async {
        final GitFileBareRepository bare = await manager.initBare(
          sandbox.newPath('bare.git'),
          initialBranch: 'main',
        );

        final GitFileRepository opened = await manager.open(bare.path);

        expect(opened, isA<GitFileBareRepository>());
        expect(opened, isA<GitBareRepository>());
        expect(opened, isA<GitFileRepository>());
        expect(opened, isNot(isA<GitWorkingRepository>()));
      });
    });

    group('typed opening', () {
      test('openWorking refuses a bare repository', () async {
        final GitFileBareRepository bare = await manager.initBare(
          sandbox.newPath('bare.git'),
        );

        await expectLater(
          manager.openWorking(bare.path),
          throwsA(
            isA<GitNotAWorkingRepositoryException>()
                .having((GitRepositoryKindException error) => error.path,
                    'path', bare.path)
                .having((GitRepositoryKindException error) => error, 'kind',
                    isA<GitRepositoryKindException>()),
          ),
        );
      });

      test('openBare refuses a working repository', () async {
        final GitWorkingRepository working =
            await manager.init(sandbox.newPath('working'));

        await expectLater(
          manager.openBare(working.path),
          throwsA(
            isA<GitNotABareRepositoryException>()
                .having((GitRepositoryKindException error) => error.path,
                    'path', working.path)
                .having((GitRepositoryKindException error) => error, 'kind',
                    isA<GitRepositoryKindException>()),
          ),
        );
      });

      test('the refusals are manager failures, not command failures', () async {
        final GitFileBareRepository bare = await manager.initBare(
          sandbox.newPath('bare.git'),
        );
        final GitWorkingRepository working =
            await manager.init(sandbox.newPath('working'));

        await expectLater(
          manager.openWorking(bare.path),
          throwsA(
            isA<GitException>().having((GitException error) => error, 'kind',
                isA<GitNotAWorkingRepositoryException>()),
          ),
        );
        await expectLater(
          manager.openBare(working.path),
          throwsA(
            isA<GitException>().having((GitException error) => error, 'kind',
                isA<GitNotABareRepositoryException>()),
          ),
        );
      });
    });

    group('init', () {
      test('creates a working repository on the initial branch', () async {
        final GitWorkingRepository working = await manager.init(
          sandbox.newPath('working'),
          initialBranch: 'trunk',
        );

        expect(working, isA<GitWorkingRepository>());
        expect(working, isA<GitFileRepository>());
        expect(working, isNot(isA<GitBareRepository>()));
        expect(await working.toplevel(), isNotEmpty);
        expect(await working.branches.current(), 'trunk');
      });

      test('initBare creates a bare repository on the initial branch',
          () async {
        final GitFileBareRepository bare = await manager.initBare(
          sandbox.newPath('bare.git'),
          initialBranch: 'start',
        );

        expect(bare, isA<GitFileBareRepository>());
        expect(bare, isA<GitBareRepository>());
        expect(bare, isNot(isA<GitWorkingRepository>()));
        expect(await bare.branches.current(), 'start');
      });
    });

    group('occupied targets', () {
      test('init refuses a directory that already holds files', () async {
        final String target = sandbox.newPath('occupied');
        final File marker = await _holdFile(target, 'notes.txt');

        await expectLater(
          manager.init(target),
          throwsA(
            isA<GitOccupiedDirectoryException>().having(
              (GitOccupiedDirectoryException error) => error.path,
              'path',
              target,
            ),
          ),
        );

        expect(
          await marker.readAsString(),
          'kept\n',
          reason: 'the refusal leaves the content untouched',
        );
        expect(
          Directory(_inside(target, '.git')).existsSync(),
          isFalse,
          reason: 'no repository was created',
        );
      });

      test('initBare refuses a directory that already holds files', () async {
        final String target = sandbox.newPath('occupied.git');
        final File marker = await _holdFile(target, 'notes.txt');

        await expectLater(
          manager.initBare(target),
          throwsA(isA<GitOccupiedDirectoryException>()),
        );

        expect(
          await marker.readAsString(),
          'kept\n',
          reason: 'the refusal leaves the content untouched',
        );
      });

      test('the refusal is a manager failure, not a command failure', () async {
        final String target = sandbox.newPath('refused.git');
        await _holdFile(target, 'notes.txt');

        await expectLater(
          manager.initBare(target),
          throwsA(
            isA<GitException>().having((GitException error) => error, 'kind',
                isA<GitOccupiedDirectoryException>()),
          ),
        );
      });

      test('allowOccupied lets git initialize beside the files it holds',
          () async {
        final String target = sandbox.newPath('allowed');
        final File marker = await _holdFile(target, 'notes.txt');

        final GitWorkingRepository working =
            await manager.init(target, allowOccupied: true);

        expect(await working.toplevel(), isNotEmpty);
        expect(
          await marker.readAsString(),
          'kept\n',
          reason: 'git keeps the files it finds',
        );
      });

      test('allowOccupied reinitializes an existing store and keeps its data',
          () async {
        final String path = sandbox.newPath('store.git');
        final GitFileBareRepository source =
            await _sourceWithCommit(manager, path);

        final GitFileBareRepository reinitialized =
            await manager.initBare(path, allowOccupied: true);

        expect(
          await reinitialized.refs.resolveRef('refs/heads/main'),
          await source.refs.resolveRef('refs/heads/main'),
          reason: 'reinitializing keeps the commits the store already holds',
        );
      });
    });
  });
}

/// Creates the directory [path] holding one file named [name] and returns
/// that file.
Future<File> _holdFile(String path, String name) async {
  await Directory(path).create(recursive: true);
  final File marker = File(_inside(path, name));
  await marker.writeAsString('kept\n');
  return marker;
}

/// Joins [directory] and [name] with the platform separator.
String _inside(String directory, String name) =>
    '$directory${Platform.pathSeparator}$name';

/// Creates a bare repository at [path] carrying one commit on `main`.
Future<GitFileBareRepository> _sourceWithCommit(
  GitRepositoryManager manager,
  String path,
) async {
  final GitFileBareRepository source = await manager.initBare(
    path,
    initialBranch: 'main',
  );
  final GitOid tree = await source.objects.writeObject(
    GitObjectType.tree,
    const <int>[],
  );
  final GitOid commit = await source.objects.writeObject(
    GitObjectType.commit,
    _commitContent(tree),
  );
  final GitRefTransaction transaction = source.beginRefTransaction();
  transaction.update('refs/heads/main', commit);
  await transaction.commit();
  return source;
}

/// Serialized content of a commit pointing at [tree].
List<int> _commitContent(GitOid tree) {
  const String timestamp = '1622550645 +0000';
  return utf8.encode(
    'tree ${tree.value}\n'
    'author Contract Engine <engine@example.com> $timestamp\n'
    'committer Contract Engine <engine@example.com> $timestamp\n'
    '\n'
    'Initial commit\n',
  );
}
