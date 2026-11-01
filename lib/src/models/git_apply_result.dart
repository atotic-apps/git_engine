/// Outcome of applying a patch.
///
/// A conflict is a result, not an exception: when a three-way apply leaves
/// conflict markers behind, the operation reports [GitApplyConflicted] with
/// the affected paths instead of throwing.
/// {@category Getting started}
sealed class GitApplyResult {
  const GitApplyResult();
}

/// The patch applied cleanly, to the work tree, the index or both.
/// {@category Getting started}
final class GitApplyApplied extends GitApplyResult {
  /// Creates the result of a patch that applied cleanly.
  const GitApplyApplied();
}

/// The patch applied with unresolved conflicts.
///
/// Only produced by a three-way apply; [paths] lists the files where conflict
/// markers remain.
/// {@category Getting started}
final class GitApplyConflicted extends GitApplyResult {
  /// Paths left with conflict markers, relative to the repository root.
  final List<String> paths;

  /// Creates the result listing [paths] as left with conflict markers.
  GitApplyConflicted(List<String> paths)
      : paths = List<String>.unmodifiable(paths);

  @override
  String toString() => 'GitApplyConflicted(${paths.join(', ')})';
}

/// The patch was refused; nothing was applied.
/// {@category Getting started}
final class GitApplyRefused extends GitApplyResult {
  /// Human-readable description of the refusal.
  ///
  /// Its text is backend-defined and is not the standard error of any specific
  /// tool.
  final String message;

  /// Creates the refusal carrying [message].
  const GitApplyRefused(this.message);

  @override
  String toString() => 'GitApplyRefused($message)';
}
