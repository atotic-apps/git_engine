/// Writes a commit on a bare repository without a work tree, through
/// `withTemporaryIndex`, then predicts a merge with `mergeTree` without
/// touching the index or a work tree.
///
/// Requires git 2.28 or newer for the commit. `mergeTree` needs git 2.38 or
/// newer and raises `GitFeatureUnavailableException` on an older git.
///
///     dart run example/bare_repository.dart
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main() async {
  final Directory sandbox =
      await Directory.systemTemp.createTemp('git_engine_bare_');
  try {
    final File globalConfig = File(_join(sandbox.path, 'gitconfig'));
    await globalConfig.writeAsString('');
    final ProcessGitEngine engine = ProcessGitEngine(
      globalEnvironment: <String, String>{
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': globalConfig.path,
      },
    );
    final GitFileClient client = engine;
    final GitIdentity identity = GitIdentity(
      name: 'Ada Lovelace',
      email: 'ada@example.com',
    );

    final GitFileBareRepository origin = await engine.initBare(
      _join(sandbox.path, 'origin.git'),
      initialBranch: 'main',
    );
    final GitWorkingRepository work =
        await client.clone(origin.path, _join(sandbox.path, 'work'));
    await File(_join(work.path, 'main.txt')).writeAsString('main\n');
    await work.worktree.addAll();
    await work.worktree.commit('Add main.txt', identity: identity);
    await client.push(
      work,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/main'],
    );

    await work.worktree.checkoutNewBranch('side');
    await File(_join(work.path, 'side.txt')).writeAsString('side\n');
    await work.worktree.addAll();
    await work.worktree.commit('Add side.txt', identity: identity);
    await client.push(
      work,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/side'],
    );

    final GitOid mainCommit = (await origin.revisions.resolveRevision('main'))!;
    final GitOid sideCommit = (await origin.revisions.resolveRevision('side'))!;
    final GitOid mainTree = (await origin.objects.readCommit(mainCommit)).tree;

    // The temporary index is seeded from the main tree; the commit is written
    // on the bare repository and the temporary index is removed afterwards.
    final GitOid bareCommit = await origin.withTemporaryIndex<GitOid>(
      (GitIndexedRepository indexed) async {
        final GitOid tree = await indexed.index.writeTree();
        return indexed.objects.commitTree(
          tree,
          <GitOid>[mainCommit],
          'Commit written without a work tree',
          author: identity,
          committer: identity,
        );
      },
      fromTree: mainTree,
    );
    await origin.refs.updateRef(
      'refs/heads/main',
      bareCommit,
      expectedOld: mainCommit,
    );
    print('bare repository committed ${bareCommit.short()} on main');

    try {
      final GitMergeTreeResult predicted =
          await origin.merge.mergeTree(bareCommit, sideCommit);
      print('mergeTree predicted ${predicted.tree.short()} with '
          '${predicted.conflictingFiles.length} conflicting file(s)');
    } on GitFeatureUnavailableException catch (error) {
      print('mergeTree unavailable on this git: ${error.message}');
    }
  } finally {
    await _deleteRecursively(sandbox);
    print('temporary directory removed');
  }
}

/// Joins [base] and [relative] with the platform separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

/// Deletes [directory], retrying while Windows still holds file locks.
Future<void> _deleteRecursively(Directory directory) async {
  for (var attempt = 0;; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt >= 4) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
