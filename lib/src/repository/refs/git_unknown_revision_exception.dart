import '../../core/errors/git_exception.dart';

/// A revision an operation requires resolves to nothing.
///
/// Raised by the operations that take a revision expression —
/// `GitRefs.resetSoft`, `GitWorktree.reset` with a target, the checkouts,
/// `GitWorkingMerge.merge`, the history ranges, `GitRevisions.symbolicFullName`
/// — when the expression names no revision. Operations that document a null
/// result for a missing revision keep that result instead of raising.
///
/// The underlying engine failure that reported the refusal is carried in
/// [cause] when there is one.
/// {@category Errors}
class GitUnknownRevisionException extends GitException {
  /// Revision expression the operation was handed.
  final String expression;

  /// The underlying engine failure that reported the refusal.
  final GitException? cause;

  /// Creates the refusal of [expression], from the [cause] git reported when
  /// there is one.
  GitUnknownRevisionException({
    required this.expression,
    this.cause,
  }) : super('the revision expression "$expression" resolves to nothing');
}
