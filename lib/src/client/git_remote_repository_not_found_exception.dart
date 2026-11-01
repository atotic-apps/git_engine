import '../core/errors/git_exception.dart';
import '../core/redact_url_userinfo.dart';

/// No repository exists at the remote location.
///
/// Raised by `GitFileClient.clone`, `fetch` and `push` when the remote side
/// reports the location holds no git repository: an HTTPS server answering
/// that the repository is not found, or an SSH path that is not a
/// repository. The underlying failure is carried in [cause].
/// {@category Errors}
class GitRemoteRepositoryNotFoundException extends GitException {
  /// The underlying engine failure that reported the absent repository.
  final GitException cause;

  /// Creates the failure from the [cause] that reported the absent
  /// repository.
  GitRemoteRepositoryNotFoundException({required this.cause})
      : super(redactUrlUserinfo(cause.message));
}
