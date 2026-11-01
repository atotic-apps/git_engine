import '../core/errors/git_exception.dart';
import '../core/redact_url_userinfo.dart';

/// A fetch or push named a ref the remote does not have.
///
/// Raised by `GitFileClient.fetch` for a refspec whose remote side resolves to
/// nothing, and by `GitFileClient.push` when pushing a ref to a destination the
/// remote cannot name. The underlying failure is carried in [cause].
/// {@category Errors}
class GitRemoteRefNotFoundException extends GitException {
  /// The underlying engine failure that reported the missing ref.
  final GitException cause;

  /// Creates the failure from the [cause] that named the missing ref.
  GitRemoteRefNotFoundException({required this.cause})
      : super(redactUrlUserinfo(cause.message));
}
