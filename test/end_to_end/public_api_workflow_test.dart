@Tags(['git'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import 'package:test/test.dart';

/// A complete repository workflow driven only through the public contracts:
/// the manager creates and opens a repository, the repository facade commits
/// and merges, the client clones, and the clone is read back through its own
/// objects and work tree.
void main() {
  test(
    'a repository is created, committed, branched, merged and cloned through '
    'the public contracts',
    () async {
      final Directory root =
          await Directory.systemTemp.createTemp('git_engine_public_workflow_');
      addTearDown(() => _deleteRecursively(root));

      final ProcessGitEngine engine = ProcessGitEngine();
      final GitRepositoryManager manager = engine;
      final GitFileClient client = engine;

      final GitWorkingRepository repository = await manager.init(
        _join(root.path, 'repository'),
        initialBranch: 'main',
      );
      await repository.config.set('user.name', 'Public Workflow');
      await repository.config.set('user.email', 'workflow@example.com');

      _write(repository.path, 'readme.md', '# base\n');
      await repository.worktree.addAll();
      final GitOid base = await repository.worktree.commit('base');

      await repository.worktree.checkoutNewBranch('feature');
      _write(repository.path, 'feature.txt', 'feature\n');
      await repository.worktree.addAll();
      final GitOid feature = await repository.worktree.commit('feature');

      await repository.worktree.checkout('main');
      _write(repository.path, 'main.txt', 'main\n');
      await repository.worktree.addAll();
      final GitOid main = await repository.worktree.commit('main');
      expect(await repository.history.isAncestor(base, main), isTrue);

      final GitMergeResult merged = await repository.merge.merge('feature');
      expect(merged, isA<GitMergeCommit>());
      final GitOid mergeCommit =
          (await repository.revisions.resolveRevision('HEAD'))!;
      final GitCommit mergeRecord =
          await repository.objects.readCommit(mergeCommit);
      expect(mergeRecord.parents, <GitOid>[main, feature]);
      expect(await repository.history.isAncestor(feature, mergeCommit), isTrue);

      const Set<String> expectedPaths = <String>{
        'feature.txt',
        'main.txt',
        'readme.md',
      };
      final GitTree mergedTree =
          await repository.objects.readTree(mergeRecord.tree);
      expect(
        mergedTree.entries.map((GitTreeEntry entry) => entry.path).toSet(),
        expectedPaths,
      );

      final GitWorkingRepository clone = await client.clone(
        repository.path,
        _join(root.path, 'clone'),
      );
      expect(await clone.revisions.resolveRevision('HEAD'), mergeCommit);
      expect(await clone.worktree.isClean(), isTrue);

      final GitCommit cloneRecord = await clone.objects.readCommit(mergeCommit);
      expect(cloneRecord.message, mergeRecord.message);
      final GitTree cloneTree = await clone.objects.readTree(cloneRecord.tree);
      expect(
        cloneTree.entries.map((GitTreeEntry entry) => entry.path).toSet(),
        expectedPaths,
      );
      final GitOid readme = cloneTree.entries
          .singleWhere((GitTreeEntry entry) => entry.path == 'readme.md')
          .oid;
      expect(utf8.decode(await clone.objects.readBlob(readme)), '# base\n');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// Writes [content] into [filesystemRoot]/[relative], creating parents.
void _write(String filesystemRoot, String relative, String content) {
  final File file = File(_join(filesystemRoot, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

/// Joins [base] and [relative] with the platform separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

/// Deletes [directory], retrying while Windows may still hold a handle.
Future<void> _deleteRecursively(Directory directory) async {
  for (var attempt = 0;; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt >= 4) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
