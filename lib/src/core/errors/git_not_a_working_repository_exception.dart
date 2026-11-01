import 'git_repository_kind_exception.dart';

/// A repository was opened as a working repository but is bare.
///
/// Raised by `GitRepositoryManager.openWorking` when git reports that the
/// repository has no work tree.
/// {@category Errors}
class GitNotAWorkingRepositoryException extends GitRepositoryKindException {
  /// Creates the failure for the bare repository at [path].
  GitNotAWorkingRepositoryException(String path)
      : super(path, 'not a working repository: $path');
}
