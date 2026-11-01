@Tags(['git'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backends/process/support/test_repository.dart';

/// One scenario chaining every domain against a real git: a bare origin, a
/// clone that pushes, a second clone that fetches, a commit fabricated on the
/// bare origin through a temporary index, a commit fabricated on an alternate
/// index, and a merge that leaves a clean work tree.
void main() {
  test(
    'bare origin, clone, push, fetch, temporary index, merge-tree, merge',
    () async {
      final TestRepository sandbox = await createTestRepository();
      final String root = sandbox.sandbox.path;
      final ProcessGitEngine engine = ProcessGitEngine(runner: sandbox.runner);

      // A bare repository to push to, with no work tree of its own.
      final String originPath = _join(root, 'origin.git');
      final GitFileBareRepository origin = await engine.initBare(
        originPath,
        initialBranch: 'main',
      );
      expect(origin, isA<GitFileBareRepository>());
      expect(origin, isNot(isA<GitWorkingRepository>()));
      expect(await origin.branches.current(), 'main');

      // A working clone that fixes its identity once, in the process
      // repository context, so every commit it makes carries it.
      final String workPath = _join(root, 'work');
      final ProcessGitWorkingRepository work = ((await engine.clone(
              originPath, workPath)) as ProcessGitWorkingRepository)
          .withEnvironment(<String, String>{
        'GIT_AUTHOR_NAME': 'E2E Author',
        'GIT_AUTHOR_EMAIL': 'author@example.com',
        'GIT_COMMITTER_NAME': 'E2E Committer',
        'GIT_COMMITTER_EMAIL': 'committer@example.com',
      });
      expect(await work.toplevel(), isNotEmpty);

      // A branch, two files, one commit.
      await work.worktree.checkoutNewBranch('feature');
      expect(await work.branches.current(), 'feature');
      final List<int> payload = _payload();
      await _writeBytes(
        _join(workPath, 'app.txt'),
        utf8.encode('hello\n'),
      );
      await _writeBytes(
        _join(_join(workPath, 'bin'), 'data.bin'),
        payload,
      );
      await work.worktree.addAll();
      final GitOid first = await work.worktree.commit('Add the application');
      expect(await work.revisions.resolveRevision('feature'), first);
      expect(await work.worktree.isClean(), isTrue);
      final GitCommit firstCommit = await work.objects.readCommit(first);
      expect(
        <String>[firstCommit.author.name, firstCommit.committer.name],
        <String>['E2E Author', 'E2E Committer'],
      );

      // The push lands on the bare origin.
      await engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['feature:refs/heads/main'],
      );
      expect(await origin.revisions.resolveRevision('main'), first);

      // A second clone checks the first commit out.
      final String otherPath = _join(root, 'other');
      final GitWorkingRepository other =
          await engine.clone(originPath, otherPath);
      expect(await other.revisions.resolveRevision('HEAD'), first);

      // A second commit is pushed, and the second clone fetches it: its own
      // HEAD stays where it was.
      await _writeBytes(
        _join(workPath, 'app.txt'),
        utf8.encode('hello again\n'),
      );
      await work.worktree.addAll();
      final GitOid second = await work.worktree.commit('Say it again');
      await engine.push(
        work,
        remote: 'origin',
        refspecs: <String>['feature:refs/heads/main'],
      );
      expect(await origin.revisions.resolveRevision('main'), second);
      expect(await other.remotes.list(), <String>['origin']);
      expect(await other.remotes.getUrl('origin'), contains('origin.git'));

      await engine.fetch(other, remote: 'origin');
      expect(await other.revisions.resolveRevision('origin/main'), second);
      expect(await other.revisions.resolveRevision('HEAD'), first);
      expect(
        await other.config.get('remote.origin.url'),
        contains('origin.git'),
      );

      // A commit fabricated on the bare origin through a temporary index: the
      // action gets an indexed view seeded from the branch tree, the file is
      // removed afterwards, and the bare repository gains no index of its own.
      final String originIndexPath = _join(originPath, 'index');
      expect(File(originIndexPath).existsSync(), isFalse);
      final GitTree originTree = await origin.objects.readTree(
        (await origin.revisions.resolveRevision('main^{tree}'))!,
      );
      final GitOid bareCommit = await origin.withTemporaryIndex<GitOid>(
        (GitIndexedRepository indexed) async {
          await indexed.index.remove(<String>['bin'], recursive: true);
          final GitOid tree = await indexed.index.writeTree();
          return indexed.objects.commitTree(
            tree,
            <GitOid>[second],
            'Fabricated on the bare origin\n',
            author: GitIdentity(
              name: 'E2E Author',
              email: 'author@example.com',
            ),
            committer: GitIdentity(
              name: 'E2E Committer',
              email: 'committer@example.com',
            ),
          );
        },
        fromTree: originTree.oid,
      );
      expect(
        await origin.objects.objectType(bareCommit),
        GitObjectType.commit,
      );
      expect(
        (await origin.objects.readCommit(bareCommit)).parents,
        <GitOid>[second],
      );
      expect(
        (await origin.objects.readTree(
          (await origin.objects.readCommit(bareCommit)).tree,
        ))
            .entries
            .map((GitTreeEntry entry) => entry.path)
            .toList(),
        <String>['app.txt'],
      );
      expect(File(originIndexPath).existsSync(), isFalse);

      // A commit fabricated on a temporary index: the clone's own index and
      // HEAD must come out of it untouched.
      final String indexPath = _join(_join(workPath, '.git'), 'index');
      final List<int> indexBefore = _snapshot(indexPath);
      expect(await work.worktree.status(), isEmpty);

      final GitOid fabricated = await work.withTemporaryIndex<GitOid>(
        (GitWorkingRepository staging) async {
          final GitTree base = await staging.objects.readTree(
            (await staging.revisions.resolveRevision('HEAD^{tree}'))!,
          );
          expect(
            base.entries.map((GitTreeEntry entry) => entry.path).toList(),
            <String>['app.txt', 'bin'],
          );
          await staging.worktree.addAll();

          // A file the clone has not staged only shows up in a diff once the
          // temporary index records the intent to add it.
          await _writeBytes(
            _join(_join(workPath, 'notes'), 'generated.bin'),
            payload,
          );
          await staging.worktree.intentToAdd(<String>['notes/generated.bin']);
          expect(
            await staging.patches.changedPathsAgainstWorkTree(),
            <String>['notes/generated.bin'],
          );
          final Uint8List patch =
              await staging.patches.binaryDiffAgainstWorkTree();
          expect(patch, isNotEmpty);
          expect(
            utf8.decode(patch, allowMalformed: true),
            contains('GIT binary patch'),
          );
          final GitApplyResult applied =
              await staging.patches.applyToIndex(patch);
          expect(applied, isA<GitApplyApplied>());

          final GitOid tree = await staging.index.writeTree();
          final GitTree written = await staging.objects.readTree(tree);
          expect(
            written.entries.map((GitTreeEntry entry) => entry.path).toList(),
            <String>['app.txt', 'bin', 'notes'],
          );
          final GitTree notes = await staging.objects.readTree(
            written.entries
                .singleWhere((GitTreeEntry entry) => entry.path == 'notes')
                .oid,
          );
          expect(notes.entries.single.path, 'generated.bin');
          expect(
            notes.entries.single.oid,
            await work.objects.hashObject(payload),
          );

          return staging.objects.commitTree(
            tree,
            <GitOid>[second],
            'Fabricated from an alternate index\n',
          );
        },
      );
      expect(
        await work.objects.objectType(fabricated),
        GitObjectType.commit,
      );
      final GitCommit fabricatedCommit =
          await work.objects.readCommit(fabricated);
      expect(fabricatedCommit.parents, <GitOid>[second]);

      // The clone's own index and HEAD never moved; only the new file, still
      // untracked, differs.
      expect(_snapshot(indexPath), indexBefore);
      expect(await work.revisions.resolveRevision('HEAD'), second);
      final List<GitStatusEntry> status = await work.worktree.status();
      expect(status, hasLength(1));
      expect(status.single.path, 'notes/');
      expect(status.single.isUntracked, isTrue);

      // Removing the file the diff was built from restores the work tree.
      await work.worktree.clean(directories: true);
      expect(await work.worktree.isClean(), isTrue);
      expect(_snapshot(indexPath), indexBefore);

      // Both branches move on: merge-tree computes the result in memory, the
      // merge folds it into history.
      await work.worktree.checkoutNewBranch('side');
      await _writeBytes(_join(workPath, 'side.txt'), utf8.encode('side\n'));
      await work.worktree.addAll();
      final GitOid sideCommit = await work.worktree.commit('Add the side note');

      await work.worktree.checkout('feature');
      await _writeBytes(_join(workPath, 'app.txt'), utf8.encode('hello!\n'));
      await work.worktree.addAll();
      final GitOid featureCommit = await work.worktree.commit('Greet louder');
      expect(await work.worktree.isClean(), isTrue);

      final GitOid headBeforeMergeTree =
          (await work.revisions.resolveRevision('HEAD'))!;
      try {
        final GitMergeTreeResult predicted =
            await work.merge.mergeTree(featureCommit, sideCommit);
        expect(predicted.isConflicted, isFalse);
        final GitTree predictedTree =
            await work.objects.readTree(predicted.tree);
        expect(
          predictedTree.entries
              .map((GitTreeEntry entry) => entry.path)
              .toList(),
          <String>['app.txt', 'bin', 'side.txt'],
        );
        expect(
          await work.worktree.status(),
          isEmpty,
          reason: 'merge-tree leaves the index and the work tree alone',
        );
      } on GitFeatureUnavailableException {
        expect(
          await work.revisions.resolveRevision('HEAD'),
          headBeforeMergeTree,
        );
        expect(await work.worktree.status(), isEmpty);
      }

      final GitMergeResult merged = await work.merge.merge('side');
      expect(merged, isA<GitMergeCommit>());
      final GitOid mergeCommit =
          (await work.revisions.resolveRevision('HEAD'))!;
      expect(
        (await work.objects.readCommit(mergeCommit)).parents,
        <GitOid>[featureCommit, sideCommit],
      );
      expect(await work.merge.isMerging(), isFalse);
      final GitOid mergeHead = (await work.revisions.resolveRevision('HEAD'))!;
      expect(await work.history.isAncestor(sideCommit, mergeHead), isTrue);
      expect(await work.history.isAncestor(second, mergeHead), isTrue);
      expect(await work.branches.current(), 'feature');
      expect(await work.worktree.isClean(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// Payload of the binary file: every byte value, so the diff really is a
/// binary patch and the content is checked byte for byte.
List<int> _payload() => <int>[
      for (int i = 0; i < 256; i++) i,
      0x0d,
      0x0a,
      0x00,
      0xff,
    ];

/// Writes [bytes] into [path], creating the parent directories.
Future<void> _writeBytes(String path, List<int> bytes) async {
  final File file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

/// Content of the file at [path], or an empty list when it does not exist.
List<int> _snapshot(String path) {
  final File file = File(path);
  return file.existsSync() ? file.readAsBytesSync() : <int>[];
}

/// Joins [base] and [relative] with the platform separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}
