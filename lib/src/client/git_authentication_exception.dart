import '../core/errors/git_exception.dart';
import '../core/redact_url_userinfo.dart';

/// The remote refused the offered credentials or demanded credentials that
/// the environment did not provide.
///
/// Raised by `GitFileClient.clone`, `fetch` and `push` when git reports an
/// authentication failure: a rejected password or token over HTTPS, or an
/// SSH connection denied for the offered key. The library supplies no
/// credentials itself; git uses what the environment provides. The
/// underlying failure is carried in [cause].
/// {@category Errors}
class GitAuthenticationException extends GitException {
  /// The underlying engine failure that reported the refused credentials.
  final GitException cause;

  /// Creates the failure from the [cause] that reported the refusal.
  GitAuthenticationException({required this.cause})
      : super(redactUrlUserinfo(cause.message));
}
