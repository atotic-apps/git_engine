import '../../core/errors/git_exception.dart';

/// A merge in fast-forward-only mode was refused because no fast-forward is
/// possible from the current `HEAD` to the requested revision: the histories
/// have diverged, the revision is behind the head, or they share no ancestor.
///
/// The original head, index and work tree are untouched.
/// {@category Errors}
class GitMergeNotFastForwardException extends GitException {
  /// The underlying engine failure that established the refusal.
  final GitException? cause;

  /// Creates the refusal carrying git's own [message] and its [cause] when
  /// there is one.
  GitMergeNotFastForwardException(super.message, {this.cause});
}
