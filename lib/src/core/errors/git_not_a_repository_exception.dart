import 'git_exception.dart';
import '../redact_url_userinfo.dart';

/// The working directory is not inside a git repository.
///
/// Raised when a repository operation is attempted in a directory that git
/// does not recognize as a repository. The underlying engine failure is
/// carried in [cause].
/// {@category Errors}
class GitNotARepositoryException extends GitException {
  /// The underlying engine failure that reported the missing repository.
  final GitException cause;

  /// Creates the failure from the [cause] that reported it.
  GitNotARepositoryException({required this.cause})
      : super(redactUrlUserinfo(cause.message));
}
