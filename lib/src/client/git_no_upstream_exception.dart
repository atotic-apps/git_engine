import '../core/errors/git_exception.dart';

/// A pull had no branch to integrate.
///
/// Raised by `GitFileClient.pull` when no branch is given and none can be
/// derived: `HEAD` is detached, or the current branch has no upstream
/// configured. Naming the remote and the branch explicitly avoids it.
/// {@category Errors}
class GitNoUpstreamException extends GitException {
  /// Creates the failure described by [message].
  GitNoUpstreamException(super.message);
}
