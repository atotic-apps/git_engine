/// The process backend: its engine, its upload-pack service and the missing
/// executable error.
///
/// Import this library at the composition root to construct the backend, then
/// hold its objects through the contracts of `git_engine.dart`.
library;

export 'src/backends/process/git_executable_not_found_exception.dart'
    show GitExecutableNotFoundException;
export 'src/backends/process/process_git_engine.dart' show ProcessGitEngine;
export 'src/backends/process/server/process_git_upload_pack_service.dart'
    show ProcessGitUploadPackService;
