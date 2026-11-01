import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// Identity every seed commit of these workflow suites carries.
final GitIdentity seedIdentity = GitIdentity(
  name: 'Seed Keeper',
  email: 'seed@example.com',
);

/// Creates an isolated sandbox for source workflows and registers its
/// deletion with [addTearDown].
///
/// The sandbox seals git off from the machine configuration:
/// `GIT_CONFIG_NOSYSTEM=1` and `GIT_CONFIG_GLOBAL` point at an empty file,
/// so every repository starts with git's own defaults.
Future<SourcesSandbox> createSourcesSandbox() async {
  final SourcesSandbox sandbox = await SourcesSandbox.create();
  addTearDown(sandbox.dispose);
  return sandbox;
}

/// A throwaway directory holding every repository of one test.
final class SourcesSandbox {
  /// Sandbox root; every path of the suite is allocated under it.
  final Directory root;

  /// Runner sealed off from the machine git configuration.
  final ProcessGitRunner runner;

  /// Engine over [runner]: it opens, creates, clones and exchanges.
  final ProcessGitEngine engine;

  int _scratchCounter = 0;

  SourcesSandbox._({
    required this.root,
    required this.runner,
  }) : engine = ProcessGitEngine(runner: runner);

  /// Creates the sandbox with its isolated git environment.
  static Future<SourcesSandbox> create() async {
    final Directory root =
        await Directory.systemTemp.createTemp('git_engine_sources_');
    try {
      final File globalConfig = File(join(root.path, 'gitconfig-global'));
      await globalConfig.create();
      final ProcessGitRunner runner = ProcessGitRunner(
        globalEnvironment: <String, String>{
          'GIT_CONFIG_NOSYSTEM': '1',
          'GIT_CONFIG_GLOBAL': globalConfig.path,
        },
      );
      return SourcesSandbox._(root: root, runner: runner);
    } catch (_) {
      await deleteRecursively(root);
      rethrow;
    }
  }

  /// A path named [name] directly under the sandbox root.
  String path(String name) => join(root.path, name);

  /// Lands on [branch] of the bare repository at [barePath], writes [files],
  /// commits [message] and pushes `HEAD` to the branch.
  ///
  /// Returns the tip the branch carries afterwards. The throwaway clone used
  /// to stage the commit is deleted before returning.
  Future<GitOid> pushTip(
    String barePath, {
    required String branch,
    required Map<String, String> files,
    required String message,
  }) async {
    final String scratch = path('seed-${_scratchCounter++}');
    final GitWorkingRepository work = await engine.clone(barePath, scratch);
    try {
      // A clone of an unborn repository already sits on the branch git will
      // create; switching to it would be a no-op git may refuse.
      if (await work.branches.current() != branch) {
        await work.worktree.checkoutNewBranch(branch, resetIfExists: true);
      }
      files.forEach((String relative, String content) {
        final File file = File(join(scratch, relative));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
      });
      await work.worktree.addAll();
      await work.worktree.commit(message, identity: seedIdentity);
      await engine.push(
        work,
        remote: barePath,
        refspecs: <String>['HEAD:refs/heads/$branch'],
      );
      return (await work.revisions.resolveRevision('refs/heads/$branch'))!;
    } finally {
      await deleteRecursively(Directory(scratch));
    }
  }

  /// Deletes the sandbox, retrying because Windows may hold file locks right
  /// after git exits.
  Future<void> dispose() => deleteRecursively(root);
}

/// Joins [base] and [relative] with the platform separator.
String join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

/// Deletes [directory], retrying a few times for Windows file locks.
Future<void> deleteRecursively(Directory directory) async {
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

/// One regular file of an uncompressed tar archive.
final class TarFileEntry {
  /// Path of the file inside the archive.
  final String name;

  /// Content of the file, decoded as UTF-8.
  final String text;

  /// Creates an entry of [name] and [text].
  const TarFileEntry({required this.name, required this.text});
}

/// Regular-file entries of an uncompressed tar archive, in archive order.
///
/// Directory entries and metadata records are skipped; their payloads still
/// advance the reading position.
List<TarFileEntry> readTarFiles(Uint8List bytes) {
  final List<TarFileEntry> entries = <TarFileEntry>[];
  var offset = 0;
  while (offset + 512 <= bytes.length) {
    final Uint8List header = bytes.sublist(offset, offset + 512);
    if (header.every((int byte) => byte == 0)) {
      break;
    }
    final String name = _tarField(header.sublist(0, 100));
    final String typeFlag = String.fromCharCode(header[156]);
    final int size =
        int.parse(_tarField(header.sublist(124, 136)).trim(), radix: 8);
    offset += 512;
    if (typeFlag == '0' || typeFlag == '\x00') {
      entries.add(TarFileEntry(
        name: name,
        text: utf8.decode(bytes.sublist(offset, offset + size)),
      ));
    }
    offset += (size + 511) & ~511;
  }
  return entries;
}

/// The [field] bytes up to the first NUL, decoded as UTF-8.
String _tarField(Uint8List field) {
  final int end = field.indexOf(0);
  return utf8.decode(end < 0 ? field : field.sublist(0, end));
}
