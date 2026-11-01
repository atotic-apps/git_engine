import 'package:git_engine/git_engine.dart';

/// Every path recorded in the active index of [repository], sorted.
///
/// The index is written as a tree, then the tree is walked recursively:
/// subtrees are entries that must be read again to reach their files.
Future<List<String>> indexPaths(GitIndexedRepository repository) async {
  final GitOid tree = await repository.index.writeTree();
  final List<String> paths = <String>[];
  await _collectPaths(repository.objects, tree, '', paths);
  paths.sort();
  return paths;
}

/// Appends every leaf path of [tree] under [prefix] to [paths].
Future<void> _collectPaths(
  GitObjectReader objects,
  GitOid treeOid,
  String prefix,
  List<String> paths,
) async {
  final GitTree tree = await objects.readTree(treeOid);
  for (final GitTreeEntry entry in tree.entries) {
    final String path = prefix.isEmpty ? entry.path : '$prefix/${entry.path}';
    if (entry.type == GitObjectType.tree) {
      await _collectPaths(objects, entry.oid, path, paths);
    } else {
      paths.add(path);
    }
  }
}
