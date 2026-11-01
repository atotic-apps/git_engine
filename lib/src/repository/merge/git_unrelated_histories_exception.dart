import '../../core/errors/git_exception.dart';

/// A merge was refused because the two histories share no common ancestor.
///
/// Raised by `GitWorkingMerge.merge` without `allowUnrelatedHistories`, and
/// by `GitMerge.mergeTree` under the same condition: git refuses to merge two
/// histories no commit links. Merging with `allowUnrelatedHistories: true`
/// does not raise.
///
/// The underlying engine failure that reported the refusal is carried in
/// [cause] when there is one.
/// {@category Errors}
class GitUnrelatedHistoriesException extends GitException {
  /// The underlying engine failure that reported the refusal.
  final GitException? cause;

  /// Creates the refusal, from the [cause] git reported when there is one.
  GitUnrelatedHistoriesException({this.cause})
      : super(
          'the two histories share no common ancestor; allow them with '
          'allowUnrelatedHistories',
        );
}
