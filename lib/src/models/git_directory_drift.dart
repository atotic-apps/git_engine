/// Differences between a [GitDirectorySnapshot] and the git directory as it
/// stands now, reported file by file.
///
/// Every list holds git-directory relative paths spelled with forward
/// slashes, sorted: [modified] files the capture holds whose content changed,
/// [added] files created since the capture, and [deleted] files of the
/// capture that are gone.
/// {@category Getting started}
final class GitDirectoryDrift {
  /// Captured files whose content changed.
  final List<String> modified;

  /// Files created since the capture.
  final List<String> added;

  /// Captured files that are gone.
  final List<String> deleted;

  /// Creates a drift report of the three lists.
  GitDirectoryDrift({
    required List<String> modified,
    required List<String> added,
    required List<String> deleted,
  })  : modified = List<String>.unmodifiable(modified),
        added = List<String>.unmodifiable(added),
        deleted = List<String>.unmodifiable(deleted);

  /// Whether nothing drifted at all.
  bool get isEmpty => modified.isEmpty && added.isEmpty && deleted.isEmpty;

  @override
  String toString() =>
      'GitDirectoryDrift(modified: $modified, added: $added, deleted: $deleted)';
}
