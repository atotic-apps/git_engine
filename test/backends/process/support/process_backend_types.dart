/// Internal barrel of the process backend types its own tests use.
///
/// It is not part of the package API: production code builds the engine
/// through `package:git_engine/process.dart` and depends on the contracts of
/// `package:git_engine/git_engine.dart`.
export 'package:git_engine/process.dart';
export 'package:git_engine/src/backends/process/git_command_exception.dart'
    show GitCommandException;
export 'package:git_engine/src/backends/process/git_repository_context.dart'
    show GitRepositoryContext;
export 'package:git_engine/src/backends/process/process_git_file_bare_repository.dart'
    show ProcessGitFileBareRepository;
export 'package:git_engine/src/backends/process/process_git_file_system.dart'
    show ProcessGitFileSystem;
export 'package:git_engine/src/backends/process/process_git_indexed_repository.dart'
    show ProcessGitIndexedRepository;
export 'package:git_engine/src/backends/process/process_git_process_launcher.dart'
    show ProcessGitLaunchedProcess, ProcessGitProcessLauncher;
export 'package:git_engine/src/backends/process/process_git_repository.dart'
    show ProcessGitRepository;
export 'package:git_engine/src/backends/process/process_git_runner.dart'
    show ProcessGitRunner;
export 'package:git_engine/src/backends/process/process_git_working_repository.dart'
    show ProcessGitWorkingRepository;
