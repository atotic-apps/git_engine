import 'package:git_engine/src/backends/process/git_repository_context.dart'
    show GitRepositoryContext;
import 'package:git_engine/src/backends/process/process_git_working_repository.dart'
    show ProcessGitWorkingRepository;
import 'package:git_engine/testing.dart';

export 'process_backend_types.dart';

/// A working repository whose commands go through [runner], whose disk
/// access goes through [fileSystem] and whose paths follow [platform].
///
/// The context path is synthetic, so the tests never touch a disk. With the
/// path style of the given [platform] it runs either spelling on any machine.
ProcessGitWorkingRepository memoryWorkingRepository(
  GitRunner runner,
  MemoryGitFileSystem fileSystem, {
  GitPlatform? platform,
  String path = '/repo',
}) {
  return ProcessGitWorkingRepository(
    runner: runner,
    context: GitRepositoryContext(path: path),
    fileSystem: fileSystem,
    platform: platform ?? GitPlatform.linux,
  );
}
