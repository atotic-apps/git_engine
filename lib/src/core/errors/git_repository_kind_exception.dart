import 'git_exception.dart';

/// Base class of the failures raised when a repository is not of the kind an
/// opening call requires.
///
/// [path] is the path that was opened. Catch this type to handle both
/// mismatches at once, or one of its subclasses to handle a single kind.
/// {@category Errors}
abstract class GitRepositoryKindException extends GitException {
  /// Path of the repository whose kind did not match the request.
  final String path;

  /// Creates a failure for [path] described by [message].
  GitRepositoryKindException(this.path, String message) : super(message);
}
