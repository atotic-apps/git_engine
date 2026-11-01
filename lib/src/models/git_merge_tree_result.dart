import 'git_oid.dart';

/// Result of an in-memory merge (`git merge-tree`): the tree the merge would
/// produce and the paths that conflict in it.
///
/// Neither the index nor the work tree is touched by the operation.
/// {@category Getting started}
class GitMergeTreeResult {
  /// Object name of the merged top-level tree. When [conflictingFiles] is not
  /// empty, those paths of this tree embed conflict markers.
  final GitOid tree;

  /// Paths that carry conflicts in [tree]. Empty for a clean merge.
  final List<String> conflictingFiles;

  /// Creates the result of an in-memory merge: the merged [tree] and the
  /// [conflictingFiles] it carries.
  const GitMergeTreeResult({
    required this.tree,
    required this.conflictingFiles,
  });

  /// Whether the merge produced any conflicting path.
  bool get isConflicted => conflictingFiles.isNotEmpty;

  @override
  bool operator ==(Object other) {
    return other is GitMergeTreeResult &&
        other.tree == tree &&
        _listEquals(other.conflictingFiles, conflictingFiles);
  }

  @override
  int get hashCode => Object.hash(tree, Object.hashAll(conflictingFiles));

  @override
  String toString() => '$tree ${conflictingFiles.join(', ')}';
}

/// Whether two string lists hold the same elements in the same order.
bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
