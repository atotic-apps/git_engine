/// One conflict block found in a work tree file.
///
/// The three lines are 1-based: [startLine] is the `<<<<<<<` line,
/// [separatorLine] the `=======` line and [endLine] the `>>>>>>>` line, the
/// structure git leaves behind in a file both sides of a merge or of an apply
/// moved.
/// {@category Getting started}
final class GitConflictRegion {
  /// Path of the file, relative to the work tree root.
  final String path;

  /// Line of the `<<<<<<<` start marker.
  final int startLine;

  /// Line of the `=======` separator marker.
  final int separatorLine;

  /// Line of the `>>>>>>>` end marker.
  final int endLine;

  /// Creates a region of [path] delimited by the three marker lines.
  const GitConflictRegion({
    required this.path,
    required this.startLine,
    required this.separatorLine,
    required this.endLine,
  });

  @override
  String toString() =>
      'GitConflictRegion($path: $startLine-$separatorLine-$endLine)';
}
