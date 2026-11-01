/// How `git reset` moves `HEAD`, the index and the work tree.
/// {@category Getting started}
enum GitResetMode {
  /// Moves `HEAD` only; the index and the work tree are left untouched, so
  /// the changes of the discarded commits stay staged.
  soft,

  /// Moves `HEAD` and resets the index to it; the work tree is left
  /// untouched, so the changes stay as unstaged modifications.
  mixed,

  /// Moves `HEAD`, resets the index to it and overwrites the work tree, so
  /// staged and unstaged modifications of tracked files are lost.
  hard,
}
