/// Clones a public repository, fetches its tags and pulls over HTTPS.
/// Defaults to GitHub's tiny octocat/Hello-World repository. Pass another
/// URL to use your own server, or --log <file> to keep the output.
///
/// All local changes happen in a temporary clone, deleted at the end.
/// To demonstrate a fast-forward pull, only that clone is reset to a parent
/// commit. Nothing is pushed and no write access to the remote is needed.
///
///     dart run example/remote_client.dart --log build/https-example.log
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main(List<String> arguments) async {
  final (String source, String? logPath) = _parse(arguments);
  final IOSink? log;
  if (logPath == null) {
    log = null;
  } else {
    final File file = File(logPath);
    await file.parent.create(recursive: true);
    log = file.openWrite();
  }
  void write(String message) {
    print(message);
    log?.writeln(message);
  }

  Directory? sandbox;
  try {
    final ProcessGitEngine engine = ProcessGitEngine();
    final GitFileClient client = engine;
    final GitEngineRuntime runtime = engine;
    write('Remote client example — ${DateTime.now().toUtc()}');
    write('OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    write('Dart: ${Platform.version}');
    write('Git: ${await runtime.engineVersion()}');
    write('Source: $source');

    sandbox = await Directory.systemTemp.createTemp('git_engine_remote_');
    final GitWorkingRepository repository = await client.clone(
      source,
      '${sandbox.path}${Platform.pathSeparator}repository',
    );
    final GitOid? clonedHead =
        await repository.revisions.resolveRevision('HEAD');
    if (clonedHead == null) {
      throw StateError(
          'This example needs a repository with at least one commit.');
    }
    write(
        'cloned ${await repository.branches.current()} at ${clonedHead.short()}');

    for (final GitLogCommit entry in await repository.history.log(limit: 3)) {
      write('  ${entry.oid.short()} ${entry.commit.message.split('\n').first}');
    }

    await client.fetch(repository, remote: 'origin', tags: GitTagFetch.all);
    if (await repository.revisions.resolveRevision('HEAD') != clonedHead) {
      throw StateError('Fetching unexpectedly moved the local HEAD.');
    }
    final List<GitTagRef> tags = await repository.tags.list();
    write('fetched origin and all tags (${tags.length}); local HEAD unchanged');
    for (final GitTagRef tag in tags.take(3)) {
      write('  $tag');
    }

    final GitOid? upstream =
        await repository.revisions.resolveRevision('@{upstream}');
    if (upstream == null) {
      throw StateError('The cloned branch has no upstream.');
    }
    final GitCommit tip = await repository.objects.readCommit(upstream);
    if (tip.parents.isNotEmpty) {
      // Rewind only our disposable clone so pull has a real update to fetch
      // and merge, even when nobody changed the public repository today.
      await repository.worktree.reset(
        mode: GitResetMode.hard,
        target: tip.parents.first.value,
      );
      write('temporary clone reset to ${tip.parents.first.short()}');
    }

    final GitMergeResult result = await client.pull(
      repository,
      mode: GitMergeMode.fastForwardOnly,
    );
    final GitOid? head = await repository.revisions.resolveRevision('HEAD');
    final GitOid? fetchedUpstream =
        await repository.revisions.resolveRevision('@{upstream}');
    if (head != fetchedUpstream || !await repository.worktree.isClean()) {
      throw StateError('Pull did not leave a clean clone at its upstream.');
    }
    if (tip.parents.isNotEmpty && result is! GitMergeFastForward) {
      throw StateError('Expected a fast-forward after rewinding the clone.');
    }
    write('pull: $result');
    write('local HEAD matches upstream; work tree is clean');
    write('remote client example passed');
  } catch (error, stack) {
    exitCode = 1;
    write('FAILED: $error\n$stack');
  } finally {
    try {
      if (sandbox != null) {
        await _deleteRecursively(sandbox);
        write('temporary directory removed');
      }
    } catch (error, stack) {
      exitCode = 1;
      write('Cleanup failed: $error\n$stack');
    } finally {
      await log?.close();
    }
  }
}

(String, String?) _parse(List<String> arguments) {
  String? source;
  String? logPath;
  for (var index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    if (argument == '--log' &&
        index + 1 < arguments.length &&
        logPath == null) {
      logPath = arguments[++index];
    } else if (!argument.startsWith('-') && source == null) {
      source = argument;
    } else {
      throw const FormatException(
        'Usage: dart run example/remote_client.dart [URL] [--log file]',
      );
    }
  }
  return (source ?? 'https://github.com/octocat/Hello-World.git', logPath);
}

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
