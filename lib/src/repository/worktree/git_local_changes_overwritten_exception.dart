import '../../core/errors/git_exception.dart';

/// A checkout or a merge was refused because it would overwrite the local
/// state of the work tree.
///
/// Raised by `GitWorktree.checkout`, `GitWorktree.checkoutDetached`,
/// `GitWorktree.checkoutNewBranch` and `GitWorkingMerge.merge` when git
/// refuses because the local changes or the untracked files it would
/// overwrite are not committed. [paths] carries the paths git named, and is
/// empty when git reported none.
///
/// The underlying engine failure that reported the refusal is carried in
/// [cause] when there is one.
/// {@category Errors}
class GitLocalChangesOverwrittenException extends GitException {
  /// Paths git would overwrite and used as the reason to refuse, in the order
  /// git named them; empty when git did not name any.
  final List<String> paths;

  /// The underlying engine failure that reported the refusal.
  final GitException? cause;

  /// Creates the refusal naming the overwritten [paths], from the [cause]
  /// git reported when there is one.
  GitLocalChangesOverwrittenException({
    this.paths = const <String>[],
    this.cause,
  }) : super(
          paths.isEmpty
              ? 'the operation would overwrite uncommitted local state'
              : 'the operation would overwrite the local state of: '
                  '${paths.join(', ')}',
        );
}
