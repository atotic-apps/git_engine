import 'git_repository_kind_exception.dart';

/// A repository was opened as a bare repository but has a work tree.
///
/// Raised by `GitRepositoryManager.openBare` when git reports that the
/// repository is not bare.
/// {@category Errors}
class GitNotABareRepositoryException extends GitRepositoryKindException {
  /// Creates the failure for the working repository at [path].
  GitNotABareRepositoryException(String path)
      : super(path, 'not a bare repository: $path');
}
