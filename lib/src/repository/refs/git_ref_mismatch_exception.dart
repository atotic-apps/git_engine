import '../../core/errors/git_exception.dart';
import '../../core/redact_url_userinfo.dart';

/// A ref update was rejected because the ref held a value other than the one
/// the caller expected.
///
/// Raised by `GitRefs.updateRef` and `GitRefs.deleteRef` when an `expectedOld`
/// value does not match the ref's current target. The underlying engine
/// failure that rejected the update is carried in [cause] when there is one.
/// {@category Errors}
class GitRefMismatchException extends GitException {
  /// The underlying engine failure that rejected the update.
  final GitException? cause;

  /// Creates the failure from the [cause] that rejected the update.
  GitRefMismatchException({this.cause})
      : super(
          redactUrlUserinfo(
            cause?.message ??
                'the ref held a value other than the expected one',
          ),
        );
}
