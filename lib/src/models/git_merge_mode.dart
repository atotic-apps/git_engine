/// Which merges [GitWorkingMerge.merge] is allowed to perform.
/// {@category Getting started}
enum GitMergeMode {
  /// git's own default: fast-forward when the history allows it, otherwise
  /// create a merge commit.
  auto,

  /// Fold into the current head only when the history allows a fast-forward;
  /// anything else is refused with a `GitMergeNotFastForwardException` and
  /// nothing is merged.
  fastForwardOnly,

  /// Always create a merge commit, even when the history could be folded by
  /// a fast-forward.
  noFastForward,
}
