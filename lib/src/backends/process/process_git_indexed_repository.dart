import 'package:git_engine/git_engine.dart';
import 'index/process_git_index.dart';
import 'patches/process_git_indexed_patches.dart';
import 'process_git_repository.dart';

/// [GitIndexedRepository] implementation running git through a process
/// repository context.
///
/// It is the indexed view derived from a repository that has no work tree,
/// and the type [ProcessGitRepository.withIndexFile] returns for such a
/// repository. Deriving another index view from it keeps this type.
class ProcessGitIndexedRepository extends ProcessGitRepository
    implements GitIndexedRepository {
  /// Creates an indexed view running commands through [runner] inside
  /// [context].
  ProcessGitIndexedRepository({
    required super.runner,
    required super.context,
    super.fileSystem,
    super.platform,
    super.launcher,
  });

  /// Tree-to-index comparisons and index-only applies of this repository.
  @override
  ProcessGitIndexedPatches get patches =>
      ProcessGitIndexedPatches(repository: this);

  @override
  ProcessGitIndex get index => ProcessGitIndex(repository: this);

  @override
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
  ProcessGitIndexedRepository withEnvironment(
    Map<String, String> environment,
  ) {
    return ProcessGitIndexedRepository(
      runner: runner,
      context: context.withEnvironment(environment),
      fileSystem: fileSystem,
      platform: platform,
      launcher: launcher,
    );
  }
}
