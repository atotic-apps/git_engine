import '../core/errors/git_exception.dart';
import '../core/redact_url_userinfo.dart';

/// A push was refused by the remote.
///
/// Raised by `GitFileClient.push` when the remote refuses a pushed ref: the
/// remote holds commits the local history does not contain in front of the
/// pushed ref, or a tag the remote already holds with another value. The
/// remote's own wording — `(non-fast-forward)` when the remote tip is
/// already known locally, `(fetch first)` when the history diverged unseen,
/// `(already exists)` for such a tag — is carried in the [cause].
/// {@category Errors}
class GitPushRejectedException extends GitException {
  /// The underlying engine failure that refused the push.
  final GitException cause;

  /// Creates the failure from the [cause] that refused the push.
  GitPushRejectedException({required this.cause})
      : super(redactUrlUserinfo(cause.message));
}
