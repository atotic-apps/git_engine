/// Creates a local bare origin, clones it, commits, pushes with tags and an
/// upstream, fetches and pulls in a second clone. It also lists the remote
/// URL forms the client accepts, without opening a network connection, and
/// shows the typed exceptions of the client.
///
/// Requires git 2.28 or newer on the `PATH`. The temporary directory is
/// removed at the end.
///
///     dart run example/client.dart
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main() async {
  final Directory sandbox =
      await Directory.systemTemp.createTemp('git_engine_client_');
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
    await File(_join(work.path, 'app.txt')).writeAsString('hello\n');
    await work.worktree.addAll();
    final GitOid first =
        await work.worktree.commit('Add the application', identity: identity);
    await client.push(
      work,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/main'],
    );
    print('pushed ${first.short()} to origin/main');

    final GitWorkingRepository other =
        await client.clone(origin.path, _join(sandbox.path, 'other'));
    print('the second clone checked out '
        '${(await other.revisions.resolveRevision('HEAD'))?.short()}');

    await File(_join(work.path, 'app.txt')).writeAsString('hello again\n');
    await work.worktree.addAll();
    final GitOid second =
        await work.worktree.commit('Say it again', identity: identity);
    await work.refs.updateRef('refs/tags/v1', second);
    await client.push(
      work,
      remote: 'origin',
      refspecs: <String>['main'],
      setUpstream: true,
      tags: true,
    );
    print('pushed main with its tags; main follows origin/main');
    await client.fetch(other, remote: 'origin');
    print('fetch brought origin/main to '
        '${(await other.revisions.resolveRevision('origin/main'))?.short()}; '
        'its own HEAD stays at '
        '${(await other.revisions.resolveRevision('HEAD'))?.short()}');

    final GitMergeResult pulled = await client.pull(other);
    print('pull integrated the fetched work: $pulled');

    // Every form below is accepted for a clone source or a remote location.
    // They are only listed here, so this example opens no network connection:
    //   https://example.com/team/project.git
    //   ssh://git@example.com/team/project.git
    //   git@example.com:team/project.git
    //   file:///srv/project.git
    // A local path is accepted too, and so is the scp-like spelling above.
    print('accepted schemes: ${client.supportedSchemes.join(', ')}');

    // A remote helper is refused before git runs.
    try {
      await client.clone(
        'ext::git upload-pack /nowhere',
        _join(sandbox.path, 'refused'),
      );
    } on GitUnsupportedUrlException catch (error) {
      print('refused before git runs: ${error.runtimeType}');
    }

    // A missing local repository is reported with the matching typed error.
    try {
      await client.clone(
        _join(sandbox.path, 'missing'),
        _join(sandbox.path, 'missing-clone'),
      );
    } on GitRemoteRepositoryNotFoundException catch (error) {
      print('typed client error: ${error.runtimeType}');
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
