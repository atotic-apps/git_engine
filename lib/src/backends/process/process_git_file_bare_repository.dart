import 'package:git_engine/git_engine.dart';

import 'process_git_repository.dart';

/// [GitFileBareRepository] implementation running git through a process
/// repository context.
///
/// It is returned when a bare repository is opened, initialized or cloned.
/// It has no work tree and no default index: [withIndexFile] yields an
/// indexed view whose commands work on an explicit index file and never on
/// the repository's own index.
class ProcessGitFileBareRepository extends ProcessGitRepository
    implements GitFileBareRepository {
  /// Creates a bare repository running commands through [runner] inside
  /// [context].
  ProcessGitFileBareRepository({
    required super.runner,
    required super.context,
    super.fileSystem,
    super.platform,
    super.launcher,
  });

  @override
  ProcessGitFileBareRepository withEnvironment(
    Map<String, String> environment,
  ) {
    return ProcessGitFileBareRepository(
      runner: runner,
      context: context.withEnvironment(environment),
      fileSystem: fileSystem,
      platform: platform,
      launcher: launcher,
    );
  }
}
