import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';
import 'patches_contract_support.dart';

/// Declares the patch application contract of the indexed and working
/// facades for [factory].
///
/// Work-tree applies, and the index-only applies that leave the work tree
/// alone, run on a working clone. Applying to the index of a bare repository
/// goes through a temporary index view obtained from `withTemporaryIndex`.
void defineGitPatchesApplyContract(BackendFactory factory) {
  group('patch application', () {
    late GitWorkingRepository repository;

    setUp(() async {
      repository = await factory.createWorkingRepository();
    });

    test('round-trips a binary file into another clone', () async {
      final List<int> originalBinary = <int>[0, 1, 2, 0, 10, 13, 255];
      final List<int> changedBinary = <int>[0, 9, 8, 7, 0, 13, 10, 254, 1];
      await commitFiles(
        repository,
        <String, Object>{'data.bin': originalBinary},
        'base',
      );
      writeRepoFile(repository.path, 'data.bin', changedBinary);
      final Uint8List patch =
          await repository.patches.binaryDiffAgainstWorkTree();
      expect(
        utf8.decode(patch, allowMalformed: true),
        contains('GIT binary patch'),
      );

      final GitWorkingRepository clone =
          await factory.cloneRepository(repository);

      expect(await clone.patches.apply(patch), isA<GitApplyApplied>());
      expect(readRepoBytes(clone, 'data.bin'), changedBinary);
    });

    test('round-trips CRLF line endings into another clone', () async {
      const String changedText = 'one\r\nchanged\r\nthree\r\n';
      await commitFiles(
        repository,
        <String, Object>{'crlf.txt': 'one\r\ntwo\r\n'},
        'base',
      );
      writeRepoFile(repository.path, 'crlf.txt', changedText);
      final Uint8List patch =
          await repository.patches.binaryDiffAgainstWorkTree();

      final GitWorkingRepository clone =
          await factory.cloneRepository(repository);

      expect(await clone.patches.apply(patch), isA<GitApplyApplied>());
      final Uint8List cloneText = readRepoBytes(clone, 'crlf.txt');
      expect(cloneText, utf8Bytes(changedText));
      expect(cloneText, contains(13));
    });

    test('refuses a patch that does not apply when checking', () async {
      await commitFiles(
        repository,
        <String, Object>{'file.txt': 'one\ntwo\n'},
        'base',
      );
      writeRepoFile(repository.path, 'file.txt', 'one\nchanged\n');
      final Uint8List patch =
          await repository.patches.binaryDiffAgainstWorkTree();
      writeRepoFile(repository.path, 'file.txt', 'unrelated\n');

      final GitApplyResult result =
          await repository.patches.apply(patch, check: true);

      expect(result, isA<GitApplyRefused>());
      expect((result as GitApplyRefused).message, isNotEmpty);
      expect(readRepoText(repository, 'file.txt'), 'unrelated\n');
      expect(
        await repository.patches.changedPathsAgainstWorkTree(),
        <String>['file.txt'],
      );
    });

    test('applies check only patches without touching files', () async {
      await commitFiles(
        repository,
        <String, Object>{'file.txt': 'one\ntwo\n'},
        'base',
      );
      writeRepoFile(repository.path, 'file.txt', 'one\nchanged\n');
      final Uint8List patch =
          await repository.patches.binaryDiffAgainstWorkTree();
      writeRepoFile(repository.path, 'file.txt', 'one\ntwo\n');

      expect(
        await repository.patches.apply(patch, check: true),
        isA<GitApplyApplied>(),
      );
      expect(readRepoText(repository, 'file.txt'), 'one\ntwo\n');
      expect(
        await repository.patches.changedPathsAgainstWorkTree(),
        isEmpty,
      );
    });

    test('three-way apply leaves markers and names the files', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{'conflict.txt': 'one\ntwo\nthree\n'},
        'base',
      );
      final GitOid mine = await commitFiles(
        repository,
        <String, Object>{'conflict.txt': 'one\nmine\nthree\n'},
        'mine',
      );
      final Uint8List patch = await repository.patches.binaryDiff(base, mine);

      await repository.worktree.reset(
        mode: GitResetMode.hard,
        target: base.value,
      );
      await commitFiles(
        repository,
        <String, Object>{'conflict.txt': 'one\ntheirs\nthree\n'},
        'theirs',
      );

      final GitApplyResult result =
          await repository.patches.apply(patch, threeWay: true);

      expect(result, isA<GitApplyConflicted>());
      expect((result as GitApplyConflicted).paths, <String>['conflict.txt']);
      final String content = readRepoText(repository, 'conflict.txt');
      expect(content, contains('<<<<<<<'));
      expect(content, contains('======='));
      expect(content, contains('>>>>>>>'));
    });

    test('reverses an already applied patch', () async {
      await commitFiles(
        repository,
        <String, Object>{'file.txt': 'v1\n'},
        'base',
      );
      writeRepoFile(repository.path, 'file.txt', 'v2\n');
      final Uint8List patch =
          await repository.patches.binaryDiffAgainstWorkTree();
      writeRepoFile(repository.path, 'file.txt', 'v1\n');

      expect(
        await repository.patches.apply(patch),
        isA<GitApplyApplied>(),
      );
      expect(readRepoText(repository, 'file.txt'), 'v2\n');
      expect(
        await repository.patches.apply(patch, reverse: true),
        isA<GitApplyApplied>(),
      );
      expect(readRepoText(repository, 'file.txt'), 'v1\n');
    });
  });

  group('index-only patch application', () {
    late GitWorkingRepository repository;

    setUp(() async {
      repository = await factory.createWorkingRepository();
    });

    test('writes the index and leaves the work tree alone', () async {
      final GitOid head = await commitFiles(
        repository,
        <String, Object>{'file.txt': 'base\n'},
        'base',
      );
      writeRepoFile(repository.path, 'file.txt', 'changed\n');
      final Uint8List patch =
          await repository.patches.binaryDiffAgainstWorkTree();
      writeRepoFile(repository.path, 'file.txt', 'base\n');

      expect(
        await repository.patches.applyToIndex(patch),
        isA<GitApplyApplied>(),
      );

      expect(readRepoText(repository, 'file.txt'), 'base\n');
      expect(
        await repository.patches.changedPathsAgainstIndex(head),
        <String>['file.txt'],
      );
    });

    test('check verifies the patch without changing the index', () async {
      await commitFiles(
        repository,
        <String, Object>{'file.txt': 'base\n'},
        'base',
      );
      writeRepoFile(repository.path, 'file.txt', 'changed\n');
      final Uint8List patch =
          await repository.patches.binaryDiffAgainstWorkTree();
      final GitOid before = await repository.index.writeTree();

      expect(
        await repository.patches.applyToIndex(patch, check: true),
        isA<GitApplyApplied>(),
      );

      expect(await repository.index.writeTree(), before);
    });

    test('reverse restores the index tree', () async {
      await commitFiles(
        repository,
        <String, Object>{'file.txt': 'v1\n'},
        'base',
      );
      final GitOid before = await repository.index.writeTree();
      writeRepoFile(repository.path, 'file.txt', 'v2\n');
      final Uint8List patch =
          await repository.patches.binaryDiffAgainstWorkTree();
      writeRepoFile(repository.path, 'file.txt', 'v1\n');

      expect(
        await repository.patches.applyToIndex(patch),
        isA<GitApplyApplied>(),
      );
      expect(await repository.index.writeTree(), isNot(before));
      expect(
        await repository.patches.applyToIndex(patch, reverse: true),
        isA<GitApplyApplied>(),
      );
      expect(await repository.index.writeTree(), before);
    });

    test('three-way apply leaves unmerged entries in the index', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{'conflict.txt': 'one\ntwo\nthree\n'},
        'base',
      );
      final GitOid mine = await commitFiles(
        repository,
        <String, Object>{'conflict.txt': 'one\nmine\nthree\n'},
        'mine',
      );
      final Uint8List patch = await repository.patches.binaryDiff(base, mine);
      await repository.worktree.reset(
        mode: GitResetMode.hard,
        target: base.value,
      );
      await commitFiles(
        repository,
        <String, Object>{'conflict.txt': 'one\ntheirs\nthree\n'},
        'theirs',
      );

      final GitApplyResult result =
          await repository.patches.applyToIndex(patch, threeWay: true);

      expect(result, isA<GitApplyConflicted>());
      expect((result as GitApplyConflicted).paths, <String>['conflict.txt']);
      expect(await repository.index.unmergedEntries(), isNotEmpty);
      expect(
        readRepoText(repository, 'conflict.txt'),
        'one\ntheirs\nthree\n',
      );
    });

    test('works on a temporary index and leaves the main index intact',
        () async {
      final GitOid head = await commitFiles(
        repository,
        <String, Object>{'file.txt': 'base\n'},
        'base',
      );
      final File mainIndex = File(joinPath(await repository.gitDir(), 'index'));
      final Uint8List mainIndexBefore = mainIndex.readAsBytesSync();

      await repository.withTemporaryIndex<void>(
        (GitWorkingRepository alternate) async {
          await alternate.worktree.addAll();

          writeRepoFile(repository.path, 'file.txt', 'changed\n');
          final Uint8List patch =
              await alternate.patches.binaryDiffAgainstWorkTree();
          writeRepoFile(repository.path, 'file.txt', 'base\n');

          expect(
            await alternate.patches.applyToIndex(patch),
            isA<GitApplyApplied>(),
          );

          expect(
            await alternate.patches.changedPathsAgainstIndex(head),
            <String>['file.txt'],
          );
          expect(readRepoText(repository, 'file.txt'), 'base\n');
        },
      );

      expect(mainIndex.readAsBytesSync(), mainIndexBefore);
    });

    test('applies to the index of a bare repository through withTemporaryIndex',
        () async {
      final ScenarioRepository source =
          await factory.createRepositoryFromScenario(<ScenarioCommit>[
        const ScenarioCommit(
          message: 'Add a',
          files: <String, String>{'a.txt': 'a\n'},
        ),
        const ScenarioCommit(
          message: 'Add b',
          files: <String, String>{'b.txt': 'b\n'},
        ),
      ]);
      final Uint8List patch = await source.repository.patches
          .binaryDiff(source.commits[0], source.commits[1]);
      final GitFileBareRepository bare = await factory.createBareRepository();

      await bare.withTemporaryIndex<void>(
        (GitIndexedRepository indexed) async {
          final GitOid emptyTree = await indexed.objects.writeObject(
            GitObjectType.tree,
            const <int>[],
          );

          expect(
            await indexed.patches.applyToIndex(patch),
            isA<GitApplyApplied>(),
          );

          expect(
            await indexed.patches.changedPathsAgainstIndex(emptyTree),
            <String>['b.txt'],
          );
          final GitOid tree = await indexed.index.writeTree();
          final GitTree written = await indexed.objects.readTree(tree);
          final GitTreeEntry entry = written.entries
              .singleWhere((GitTreeEntry entry) => entry.path == 'b.txt');
          expect(await indexed.objects.readBlob(entry.oid), utf8Bytes('b\n'));
        },
      );

      expect(
        File(joinPath(await bare.gitDir(), 'index')).existsSync(),
        isFalse,
      );
    });
  });
}
