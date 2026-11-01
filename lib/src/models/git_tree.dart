import 'git_object_type.dart';
import 'git_oid.dart';

/// One entry of a tree object: a blob, a subtree or a gitlink.
/// {@category Getting started}
class GitTreeEntry {
  /// Octal file mode as git prints it, e.g. `100644`, `100755`, `120000`,
  /// `040000` for a subtree or `160000` for a gitlink.
  final String mode;

  /// Kind of object the entry points at.
  final GitObjectType type;

  /// Object the entry points at.
  final GitOid oid;

  /// Path of the entry relative to the repository root, `/`-separated.
  final String path;

  /// Creates an entry of [path] pointing at [oid] with [mode] and [type].
  const GitTreeEntry({
    required this.mode,
    required this.type,
    required this.oid,
    required this.path,
  });

  @override
  bool operator ==(Object other) =>
      other is GitTreeEntry &&
      other.mode == mode &&
      other.type == type &&
      other.oid == oid &&
      other.path == path;

  @override
  int get hashCode => Object.hash(mode, type, oid, path);

  @override
  String toString() => '$mode ${type.name} $oid\t$path';
}

/// A tree object: its object name and the entries it lists.
/// {@category Getting started}
class GitTree {
  /// Object name of the tree itself.
  final GitOid oid;

  /// Entries of the tree, ordered the way git stores them.
  final List<GitTreeEntry> entries;

  /// Creates the tree named [oid] listing [entries].
  GitTree({required this.oid, required List<GitTreeEntry> entries})
      : entries = List<GitTreeEntry>.unmodifiable(entries);

  @override
  String toString() => '$oid (${entries.length} entries)';
}
