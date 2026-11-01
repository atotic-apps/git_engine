import 'git_exception.dart';

/// A git command produced more standard output than it was allowed.
///
/// The limit bounds the bytes an operation retains from standard output;
/// standard error is bounded independently and does not count toward it. The
/// command is stopped and the output it already produced is discarded, so the
/// message never contains that output.
/// {@category Errors}
class GitOutputLimitException extends GitException {
  /// Maximum number of standard-output bytes the operation was allowed to
  /// produce.
  final int limit;

  /// Creates the failure of an operation that produced more than [limit]
  /// bytes on standard output.
  GitOutputLimitException({required this.limit})
      : super(
          'a git command produced more than $limit bytes on standard output',
        );
}
