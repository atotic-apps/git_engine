import '../../core/errors/git_exception.dart';

/// An in-progress merge was aborted although none is in progress.
///
/// Raised by `GitWorkingMerge.abort` when no merge is in progress — no
/// conflict was left behind and no merge was staged by a `noCommit` merge.
/// The head, index and work tree are untouched.
///
/// The underlying engine failure that reported the refusal is carried in
/// [cause] when there is one.
/// {@category Errors}
class GitNoMergeInProgressException extends GitException {
  /// The underlying engine failure that reported the refusal.
  final GitException? cause;

  /// Creates the refusal, from the [cause] git reported when there is one.
  GitNoMergeInProgressException({this.cause})
      : super('no merge is in progress');
}
