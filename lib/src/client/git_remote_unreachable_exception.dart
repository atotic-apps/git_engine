import '../core/errors/git_exception.dart';
import '../core/redact_url_userinfo.dart';

/// The remote host could not be reached.
///
/// Raised by `GitFileClient.clone`, `fetch` and `push` when git reports a
/// connection-level failure: an unknown host, a refused connection, a timed
/// out connection, or an SSH host key that could not be verified. The
/// underlying failure is carried in [cause].
/// {@category Errors}
class GitRemoteUnreachableException extends GitException {
  /// The underlying engine failure that reported the unreachable host.
  final GitException cause;

  /// Creates the failure from the [cause] that reported the connection.
  GitRemoteUnreachableException({required this.cause})
      : super(redactUrlUserinfo(cause.message));
}
