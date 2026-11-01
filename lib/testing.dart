/// Test seams for the process backend.
///
/// Import this library to supply a runner, a process launcher, a file system
/// or a platform to the backend.
library;

export 'src/backends/process/git_file_system.dart'
    show GitFileSystem, GitFileSystemEntry;
export 'src/backends/process/git_platform.dart'
    show GitOperatingSystem, GitPathStyle, GitPlatform;
export 'src/backends/process/git_process_launcher.dart'
    show GitLaunchedProcess, GitProcessLaunchRequest, GitProcessLauncher;
export 'src/backends/process/git_runner.dart'
    show GitRunner, GitRunRequest, GitRunResult;
export 'src/backends/process/memory_git_file_system.dart'
    show MemoryGitFileSystem;
