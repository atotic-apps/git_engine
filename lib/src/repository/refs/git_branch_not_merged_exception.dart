import '../../core/errors/git_exception.dart';

/// A branch was deleted without `force` although it is not fully merged.
///
/// Raised by `GitBranches.delete` without `force`, when git refuses so the
/// commits reachable only from the branch are not lost. Deleting with
/// `force: true` does not raise.
///
/// The underlying engine failure that reported the refusal is carried in
/// [cause] when there is one.
/// {@category Errors}
class GitBranchNotMergedException extends GitException {
  /// Branch git refused to delete.
  final String branch;

  /// The underlying engine failure that reported the refusal.
  final GitException? cause;

  /// Creates the refusal of [branch], from the [cause] git reported when
  /// there is one.
  GitBranchNotMergedException({
    required this.branch,
    this.cause,
  }) : super('the branch "$branch" is not fully merged');
}
