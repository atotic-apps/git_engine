import 'package:git_engine/git_engine.dart';
import 'git_runner.dart';
import 'merge/process_git_working_merge.dart';
import 'patches/process_git_working_patches.dart';
import 'process_git_engine.dart';
import 'process_git_indexed_repository.dart';
import 'worktree/process_git_worktree.dart';

/// [GitWorkingRepository] implementation running git through a process
/// repository context.
///
/// It is returned when a repository with a work tree is opened or cloned.
/// Deriving an index view from it keeps this type, because the work tree is
/// still there.
class ProcessGitWorkingRepository extends ProcessGitIndexedRepository
    implements GitWorkingRepository {
  /// Creates a working repository running commands through [runner] inside
  /// [context].
  ProcessGitWorkingRepository({
    required super.runner,
    required super.context,
    super.fileSystem,
    super.platform,
    super.launcher,
  });

  @override
  Future<String> toplevel() async {
    final GitRunResult result = await runCommand(const <String>[
      'rev-parse',
      '--show-toplevel',
    ]);
    return result.stdout.trim();
  }

  /// Work tree and index of this repository, all through its context.
  @override
  ProcessGitWorktree get worktree => ProcessGitWorktree(repository: this);

  /// Index-to-work-tree comparisons and work-tree applies of this
  /// repository.
  @override
  ProcessGitWorkingPatches get patches =>
      ProcessGitWorkingPatches(repository: this);

  /// Merging into this work tree, plus the in-memory merges of a repository.
  @override
  GitWorkingMerge get merge => ProcessGitWorkingMerge(
        repository: this,
        runtime: ProcessGitEngine(
          runner: runner,
          fileSystem: fileSystem,
          platform: platform,
          launcher: launcher,
        ),
      );

  /// A working view whose commands work on [indexFilePath].
  @override
  ProcessGitWorkingRepository withIndexFile(String indexFilePath) {
    return ProcessGitWorkingRepository(
      runner: runner,
      context: context.withIndexFile(indexFilePath),
      fileSystem: fileSystem,
      platform: platform,
      launcher: launcher,
    );
  }

  /// A working view carrying [environment] over its current variables.
  @override
  ProcessGitWorkingRepository withEnvironment(
    Map<String, String> environment,
  ) {
    return ProcessGitWorkingRepository(
      runner: runner,
      context: context.withEnvironment(environment),
      fileSystem: fileSystem,
      platform: platform,
      launcher: launcher,
    );
  }

  /// A working view whose active index is temporary, deleted afterwards.
  ///
  /// The view is a [ProcessGitWorkingRepository] because `withIndexFile` keeps
  /// the working type, so the action can use the work tree too.
  @override
  Future<T> withTemporaryIndex<T>(
    Future<T> Function(GitWorkingRepository repository) action, {
    GitOid? fromTree,
  }) {
    return super.withTemporaryIndex<T>(
      (GitIndexedRepository repository) =>
          action(repository as GitWorkingRepository),
      fromTree: fromTree,
    );
  }
}
