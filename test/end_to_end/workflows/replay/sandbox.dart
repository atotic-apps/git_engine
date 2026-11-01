import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

/// Identity used for every commit of the replay scenarios.
final GitIdentity sandboxIdentity = GitIdentity(
  name: 'Sandbox Author',
  email: 'sandbox@example.com',
);

/// A throwaway sandbox rooted at one directory of the system temporary
/// directory, isolating the installed git from the machine configuration and
/// exposing a real engine over it.
///
/// Helper private to the replay workflow suites: it only prepares real,
/// disposable repositories and never asserts behaviour of its own.
final class ReplaySandbox {
  /// Sandbox root directory.
  final Directory root;

  /// Runner running the installed git with an isolated configuration.
  final ProcessGitRunner runner;

  /// Engine on top of [runner].
  final ProcessGitEngine engine;

  ReplaySandbox._(this.root, this.runner)
      : engine = ProcessGitEngine(runner: runner);

  /// Creates a sandbox and registers its deletion with the current test.
  static Future<ReplaySandbox> create() async {
    final Directory root = await Directory.systemTemp.createTemp(
      'git_engine_replay_',
    );
    final File globalConfig = File(join(root.path, 'gitconfig-global'));
    await globalConfig.create();
    final ReplaySandbox sandbox = ReplaySandbox._(
      root,
      ProcessGitRunner(
        globalEnvironment: <String, String>{
          'GIT_CONFIG_NOSYSTEM': '1',
          'GIT_CONFIG_GLOBAL': globalConfig.path,
        },
      ),
    );
    addTearDown(sandbox.dispose);
    return sandbox;
  }

  /// Path of a sandboxed directory or file.
  String path(String name) => join(root.path, name);

  /// Runs git in [directory]; helper for state checks and setup plumbing.
  Future<GitRunResult> run(String directory, List<String> arguments) =>
      runner.run(GitRunRequest(
        arguments: arguments,
        workingDirectory: directory,
      ));

  /// Runs git in [directory] and fails the test when git refuses.
  Future<String> ok(String directory, List<String> arguments) async {
    final GitRunResult result = await run(directory, arguments);
    if (result.exitCode != 0) {
      fail('git ${arguments.join(' ')} refused: ${result.stderr}');
    }
    return result.stdout.trim();
  }

  /// Writes [content] into a file relative to [directory], creating parent
  /// directories as needed.
  void write(String directory, String relative, Object content) {
    final File file = File(join(directory, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      content is String ? utf8Bytes(content) : content as List<int>,
    );
  }

  /// Reads a file relative to [directory] as bytes.
  Uint8List readBytes(String directory, String relative) =>
      File(join(directory, relative)).readAsBytesSync();

  /// Reads a file relative to [directory] as text.
  String readText(String directory, String relative) =>
      String.fromCharCodes(readBytes(directory, relative));

  /// Initializes a working repository named [name].
  Future<GitWorkingRepository> initWorking(String name) async =>
      engine.init(path(name), initialBranch: 'main');

  /// Initializes a bare repository named [name].
  Future<GitFileBareRepository> initBare(String name) async =>
      engine.initBare(path(name), initialBranch: 'main');

  /// Clones [source] into the sandbox directory [name].
  Future<GitWorkingRepository> clone(String source, String name) async =>
      engine.clone(source, path(name));

  /// Writes [files] into the work tree of [repository], stages everything and
  /// commits [message]; returns the new commit.
  Future<GitOid> commit(
    GitWorkingRepository repository,
    Map<String, String> files,
    String message,
  ) async {
    final String directory = await repository.toplevel();
    for (final MapEntry<String, String> entry in files.entries) {
      write(directory, entry.key, entry.value);
    }
    await repository.worktree.addAll();
    return repository.worktree.commit(
      message,
      identity: sandboxIdentity,
    );
  }

  /// Stages every change of the work tree of [repository] — untracked files
  /// and deletions included — and returns the tree of the staged state,
  /// through a temporary index so the real index never moves.
  Future<GitOid> workTree(GitOid fromTree, GitWorkingRepository repository) =>
      repository.withTemporaryIndex<GitOid>(
        (GitIndexedRepository indexed) async {
          await (indexed as GitWorkingRepository).worktree.addAll();
          return indexed.index.writeTree();
        },
        fromTree: fromTree,
      );

  /// Fabricates a commit of the tree [tree] with [parents], through a
  /// temporary index; no ref moves.
  Future<GitOid> commitWorkTree(
    GitWorkingRepository repository, {
    required GitOid tree,
    required List<GitOid> parents,
    required String message,
  }) =>
      repository.withTemporaryIndex<GitOid>(
        (GitIndexedRepository indexed) => indexed.objects.commitTree(
          tree,
          parents,
          message,
          author: sandboxIdentity,
          committer: sandboxIdentity,
        ),
        fromTree: tree,
      );

  /// Object name git resolves [rev] to in the repository rooted at [path].
  Future<GitOid> resolve(String path, String rev) async => GitOid.parse(
        await ok(path, <String>['rev-parse', rev]),
      );

  /// HEAD of the repository rooted at [path].
  Future<String> head(String path) => ok(path, <String>['rev-parse', 'HEAD']);

  /// Joins [base] and [relative] with the platform separator.
  static String join(String base, String relative) =>
      '$base${Platform.pathSeparator}$relative';

  /// Deletes the sandbox, retrying because Windows may hold file locks right
  /// after git exits.
  Future<void> dispose() async {
    for (var attempt = 0;; attempt++) {
      try {
        await root.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 4) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}

/// Encodes [content] as UTF-8 bytes.
Uint8List utf8Bytes(String content) =>
    Uint8List.fromList(const Utf8Codec().encode(content));

/// Joins [base] and [relative] with the platform separator.
String join(String base, String relative) => ReplaySandbox.join(base, relative);
