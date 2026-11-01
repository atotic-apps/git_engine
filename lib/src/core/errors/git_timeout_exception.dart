import 'git_exception.dart';

/// A git operation did not finish within the delay it was given.
///
/// The delay bounds the operation, not the way a backend stops the work it
/// started: a backend that keeps details of the stopped work reports them as
/// [cause]. Code portable between backends catches this type to handle an
/// operation that ran out of time, whatever the backend.
/// {@category Errors}
class GitTimeoutException extends GitException {
  /// Delay after which the operation was reported as timed out.
  final Duration timeout;

  /// The backend failure that produced this one, when there is one.
  ///
  /// A backend that runs no git command leaves it null; the process backend
  /// attaches the command arguments and the output captured before it stopped
  /// the command.
  @override
  final GitException? cause;

  /// Creates the timeout of an operation that did not finish within [timeout],
  /// with the backend failure that carries its details as [cause] when there
  /// is one.
  GitTimeoutException({required this.timeout, this.cause})
      : super(
          'a git operation did not finish within '
          '${timeout.inMilliseconds} ms',
        );
}
