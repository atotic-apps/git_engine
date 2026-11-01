import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'branches/process_git_branches.dart';
import 'config/process_git_config.dart';
import 'git_file_system.dart';
import 'git_platform.dart';
import 'git_process_launcher.dart';
import 'git_repository_context.dart';
import 'git_runner.dart';
import 'gitdir/process_git_directory_files.dart';
import 'history/process_git_history.dart';
import 'merge/process_git_merge.dart';
import 'objects/process_git_objects.dart';
import 'patches/process_git_patches.dart';
import 'process_git_engine.dart';
import 'process_git_file_system.dart';
import 'process_git_indexed_repository.dart';
import 'process_git_platform.dart';
import 'process_git_process_launcher.dart';
import 'process_git_runner.dart';
import 'refs/process_git_ref_transaction.dart';
import 'refs/process_git_refs.dart';
import 'refs/process_git_revisions.dart';
import 'remotes/process_git_remotes.dart';
import 'tags/process_git_tags.dart';

/// Shared implementation of a disk-backed repository running git through a
/// [GitRunner] inside the repository [context].
///
/// It is the common process type behind [ProcessGitWorkingRepository],
/// [ProcessGitFileBareRepository] and the indexed view: it carries the
/// domains available to any repository, plus the escape hatches of the
/// process backend — [context], [runCommand] and [withEnvironment]. Those
/// escape hatches are deliberately absent from [GitFileRepository], which
/// stays independent of any backend.
abstract class ProcessGitRepository implements GitFileRepository {
  /// Runner every command goes through.
  final GitRunner runner;

  /// Execution context handed to every command of this repository.
  final GitRepositoryContext context;

  /// File system this repository inspects; the `dart:io` one by default,
  /// an in-memory one in tests.
  final GitFileSystem fileSystem;

  /// Platform facts — operating system, path style, environment — the
  /// commands of this repository are bound to; the host's by default.
  final GitPlatform platform;

  /// Launcher of the streaming processes of this repository, such as archive
  /// output; built on [runner] when it is a [ProcessGitRunner].
  final GitProcessLauncher launcher;

  /// Creates a repository view running commands through [runner] inside
  /// [context]; [fileSystem] and [platform] default to the `dart:io` file
  /// system and the platform of the host, and [launcher] to one over
  /// [runner] when it is a [ProcessGitRunner].
  ///
  /// The [context] path is made absolute through [fileSystem], so a relative
  /// or synthetic path lands identically on the file system the repository
  /// actually inspects.
  ProcessGitRepository({
    required this.runner,
    required GitRepositoryContext context,
    GitFileSystem? fileSystem,
    GitPlatform? platform,
    GitProcessLauncher? launcher,
  })  : fileSystem = fileSystem ?? const ProcessGitFileSystem(),
        platform = platform ?? hostGitPlatform,
        launcher = launcher ??
            ProcessGitProcessLauncher(
              runner: runner is ProcessGitRunner ? runner : null,
            ),
        context = _absolutizeContext(
          context,
          fileSystem ?? const ProcessGitFileSystem(),
        );

  /// [context] whose path is made absolute through [fileSystem].
  static GitRepositoryContext _absolutizeContext(
    GitRepositoryContext context,
    GitFileSystem fileSystem,
  ) {
    return GitRepositoryContext(
      path: fileSystem.absolutePath(context.path),
      environment: context.environment,
    );
  }

  @override
  String get path => context.path;

  @override
  Future<String> gitDir() async {
    final GitRunResult result = await runCommand(const <String>[
      'rev-parse',
      '--absolute-git-dir',
    ]);
    return result.stdout.trim();
  }

  @override
  Future<void> pruneWorktrees() {
    return runCommand(const <String>['worktree', 'prune']);
  }

  @override
  GitDirectoryFiles get gitDirectoryFiles =>
      ProcessGitDirectoryFiles(repository: this);

  @override
  GitConfig get config => ProcessGitConfig(repository: this);

  @override
  GitRemotes get remotes => ProcessGitRemotes(repository: this);

  @override
  ProcessGitBranches get branches => ProcessGitBranches(repository: this);

  @override
  ProcessGitTags get tags => ProcessGitTags(repository: this);

  @override
  ProcessGitRefs get refs => ProcessGitRefs(repository: this);

  @override
  ProcessGitRevisions get revisions => ProcessGitRevisions(repository: this);

  @override
  ProcessGitHistory get history => ProcessGitHistory(repository: this);

  @override
  ProcessGitRefTransaction beginRefTransaction() {
    return ProcessGitRefTransaction(repository: this);
  }

  @override
  ProcessGitObjects get objects => ProcessGitObjects(repository: this);

  @override
  ProcessGitPatches get patches => ProcessGitPatches(repository: this);

  @override
  GitMerge get merge => ProcessGitMerge(
        repository: this,
        runtime: ProcessGitEngine(
          runner: runner,
          fileSystem: fileSystem,
          platform: platform,
          launcher: launcher,
        ),
      );

  /// A view of this repository whose commands all work on [indexFilePath]
  /// instead of the repository's own index.
  ///
  /// Relative paths are resolved against [path].
  ProcessGitIndexedRepository withIndexFile(String indexFilePath) {
    return ProcessGitIndexedRepository(
      runner: runner,
      context: context.withIndexFile(indexFilePath),
      fileSystem: fileSystem,
      platform: platform,
      launcher: launcher,
    );
  }

  @override
  Future<T> withTemporaryIndex<T>(
    Future<T> Function(GitIndexedRepository repository) action, {
    GitOid? fromTree,
  }) async {
    final String directory = await fileSystem
        .createTemporaryDirectory('git_engine_temporary_index_');
    try {
      final ProcessGitIndexedRepository repository = withIndexFile(
        platform.pathStyle.join(directory, 'index'),
      );
      await repository.runCommand(<String>[
        'read-tree',
        fromTree?.value ?? '--empty',
      ]);
      return await action(repository);
    } finally {
      await _deleteRecursively(directory);
    }
  }

  /// Deletes the temporary [directory] holding the index, retrying while the
  /// system may still hold a handle on it, as Windows commonly does.
  Future<void> _deleteRecursively(String directory) async {
    for (var attempt = 0;; attempt++) {
      try {
        await fileSystem.deleteDirectory(directory, recursive: true);
        return;
      } catch (error) {
        if (attempt >= 4) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  /// A view of the same repository whose commands additionally receive
  /// [environment] — merged over the current context variables, which are
  /// useful e.g. to fix an identity. This view is never modified.
  ///
  /// An escape hatch of the process backend: [GitFileRepository] has no
  /// notion of environment variables.
  ProcessGitRepository withEnvironment(Map<String, String> environment);

  /// Runs git [arguments] inside the repository [context], with [stdin] when
  /// given.
  ///
  /// A low-level escape hatch towards the process backend: typed domain
  /// accessors are preferred where they exist. The runner reports failures as
  /// [GitCommandException], or as a domain exception it recognizes.
  Future<GitRunResult> runCommand(
    List<String> arguments, {
    Uint8List? stdin,
  }) {
    return runner.run(GitRunRequest(
      arguments: arguments,
      workingDirectory: context.path,
      environment: context.environment,
      stdin: stdin,
    ));
  }
}
