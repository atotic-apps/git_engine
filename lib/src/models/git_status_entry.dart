/// State of a path reported by `git status`, on one side of the index.
/// {@category Getting started}
enum GitFileState {
  /// The path is identical on this side.
  unchanged,

  /// The path was added on this side.
  added,

  /// The path content or mode changed on this side.
  modified,

  /// The path was deleted on this side.
  deleted,

  /// The path was renamed on this side; the previous name is carried by
  /// [GitStatusEntry.originalPath].
  renamed,

  /// The path was copied on this side; the source name is carried by
  /// [GitStatusEntry.originalPath].
  copied,

  /// The kind of the path changed (a regular file became a symlink, say).
  typeChanged,

  /// The path is part of an unresolved merge.
  unmerged,

  /// The path is not tracked at all.
  untracked,
}

/// One entry of the work tree status, as reported by `git status`.
///
/// An entry compares the same path on three sides — `HEAD`, the index and the
/// work tree — and reports the index and work tree sides separately, so a
/// path both staged and modified afterwards is a single entry with an index
/// state and a work tree state.
/// {@category Getting started}
class GitStatusEntry {
  /// Two-letter status code, e.g. `M `, ` M` or `??`.
  ///
  /// The first letter describes the index, the second the work tree, with
  /// git's own meanings: ` ` unchanged, `M` modified, `A` added, `D` deleted,
  /// `R` renamed, `C` copied, `T` type changed, `U` unmerged, `?` untracked.
  final String code;

  /// Path relative to the work tree root, with the original spelling and
  /// encoding.
  final String path;

  /// Path this entry was renamed or copied from, or null when it was not.
  final String? originalPath;

  /// State of the path in the index.
  final GitFileState indexState;

  /// State of the path in the work tree.
  final GitFileState workTreeState;

  /// Creates an entry from its status [code] and [path], with the state
  /// of each side and the original [originalPath] of a rename or copy.
  const GitStatusEntry({
    required this.code,
    required this.path,
    required this.indexState,
    required this.workTreeState,
    this.originalPath,
  });

  /// Whether the index holds a change for this path — a staged addition,
  /// modification, deletion, rename, copy or type change.
  bool get isIndexed {
    return switch (indexState) {
      GitFileState.added ||
      GitFileState.modified ||
      GitFileState.deleted ||
      GitFileState.renamed ||
      GitFileState.copied ||
      GitFileState.typeChanged =>
        true,
      _ => false,
    };
  }

  /// Whether the work tree holds an unstaged modification.
  ///
  /// A staged modification with no further change on disk is
  /// [isIndexed], not [isModified].
  bool get isModified => workTreeState == GitFileState.modified;

  /// Whether the path is untracked.
  bool get isUntracked =>
      indexState == GitFileState.untracked ||
      workTreeState == GitFileState.untracked;

  /// Whether the path was deleted, in the index or in the work tree.
  bool get isDeleted =>
      indexState == GitFileState.deleted ||
      workTreeState == GitFileState.deleted;

  /// Whether the path was renamed, in the index or in the work tree.
  bool get isRenamed =>
      indexState == GitFileState.renamed ||
      workTreeState == GitFileState.renamed;

  /// Whether the path is part of an unresolved merge.
  bool get isConflicted => _unmergedCodes.contains(code);

  /// The unmerged status codes (`UU`, `AA`, `DD`, `AU`, `UA`, `DU`, `UD`).
  static const Set<String> _unmergedCodes = <String>{
    'DD',
    'AU',
    'UD',
    'UA',
    'DU',
    'AA',
    'UU',
  };

  @override
  bool operator ==(Object other) {
    return other is GitStatusEntry &&
        other.code == code &&
        other.path == path &&
        other.originalPath == originalPath &&
        other.indexState == indexState &&
        other.workTreeState == workTreeState;
  }

  @override
  int get hashCode =>
      Object.hash(code, path, originalPath, indexState, workTreeState);

  @override
  String toString() {
    final String rename = originalPath == null ? '' : ' (from $originalPath)';
    return '$code $path$rename';
  }
}
