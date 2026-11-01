/// Creates a repository in a temporary directory, writes a file, reads the
/// status, stages and commits it, reads the commit and its history, creates
/// branches and tags, and lists them. The temporary directory is removed at
/// the end.
///
/// Requires git 2.28 or newer on the `PATH` (`init --initial-branch`).
///
///     dart run example/local_repository.dart
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main() async {
  final Directory sandbox =
      await Directory.systemTemp.createTemp('git_engine_local_');
  try {
    final File globalConfig = File(_join(sandbox.path, 'gitconfig'));
    await globalConfig.writeAsString('');
    final ProcessGitEngine engine = ProcessGitEngine(
      globalEnvironment: <String, String>{
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': globalConfig.path,
      },
    );
    final String path = _join(sandbox.path, 'repository');
    final GitWorkingRepository repository =
        await engine.init(path, initialBranch: 'main');
    print('initialized ${repository.path} '
        'on ${await repository.branches.current()}');

    await File(_join(path, 'notes.txt')).writeAsString('First note\n');
    print('status after writing a file:');
    for (final GitStatusEntry entry in await repository.worktree.status()) {
      print('  ${entry.code} ${entry.path}');
    }

    await repository.worktree.add(<String>['notes.txt']);
    print('status after staging:');
    for (final GitStatusEntry entry in await repository.worktree.status()) {
      print('  ${entry.code} ${entry.path}');
    }

    final GitIdentity identity = GitIdentity(
      name: 'Ada Lovelace',
      email: 'ada@example.com',
    );
    final GitOid commit = await repository.worktree.commit(
      'Add the first note',
      identity: identity,
    );
    print('committed ${commit.short()}');

    final GitCommit read = await repository.objects.readCommit(commit);
    print('read back: "${read.message}" by ${read.author.name}');
    final List<GitOid> touching =
        await repository.history.commitsTouching('notes.txt');
    print('commits touching notes.txt: ${touching.length}');
    final List<GitLogCommit> log =
        await repository.history.log(limit: 5, path: 'notes.txt');
    print('log of notes.txt: '
        '${log.map((GitLogCommit entry) => entry.oid.short()).join(', ')}');

    await repository.worktree.checkoutNewBranch('topic');
    await File(_join(path, 'topic.txt')).writeAsString('Topic\n');
    await repository.worktree.addAll();
    final GitOid topic = await repository.worktree.commit(
      'Start the topic',
      identity: identity,
    );
    print('branch ${await repository.branches.current()} '
        'at ${topic.short()}');

    final GitOid mainTree = (await repository.objects.readCommit(commit)).tree;
    final GitOid topicTree = (await repository.objects.readCommit(topic)).tree;
    final List<String> addedPaths = await repository.patches.changedPaths(
      mainTree,
      topicTree,
      kinds: <GitChangeKind>{GitChangeKind.added},
    );
    print('files added between main and topic: ${addedPaths.join(', ')}');

    // Branch administration without touching the work tree.
    await repository.branches.create('review', startPoint: 'main');
    await repository.branches.rename('review', 'inspection');
    for (final GitBranch branch in await repository.branches.list()) {
      print('branch ${branch.name} at ${branch.oid.short()}'
          '${branch.isCurrent ? ' (current)' : ''}');
    }

    // Tags: a lightweight one and an annotated one read back through readTag.
    await repository.tags.create('topic-start', topic);
    await repository.tags.create(
      'v1.0.0',
      topic,
      message: 'First release',
      tagger: identity,
    );
    final GitTagRef release = (await repository.tags.list()).last;
    final GitTag tag = await repository.objects.readTag(release.oid);
    print('tag ${release.name} on ${release.target.short()} '
        'annotated: "${tag.message}" by ${tag.tagger.name}');
    await repository.tags.delete('topic-start');
    print('tags left: '
        '${(await repository.tags.list()).map((GitTagRef tag) => tag.name)}');
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
