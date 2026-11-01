import 'dart:typed_data';

import '../../models/git_commit.dart';
import '../../models/git_object_type.dart';
import '../../models/git_oid.dart';
import '../../models/git_raw_object.dart';
import '../../models/git_tag.dart';
import '../../models/git_tree.dart';

/// Read access to the objects of one repository, addressed by object name.
///
/// This is the narrow capability contract around object storage: every
/// operation names an object with a [GitOid] and none interprets a revision
/// expression. Resolving `HEAD~2` or `main^{tree}` belongs to a revision
/// resolver, not here.
///
/// Every command runs inside the owning repository's context, so a derived
/// view (an alternate index, extra environment variables) applies here too.
/// The operations behave the same in a bare repository and in a clone with a
/// work tree. Every failure is a `GitException`, except where an operation
/// documents a null result (an absent object).
/// {@category Getting started}
/// {@category Compatibility}
abstract interface class GitObjectReader {
  /// Whether [oid] names an object stored in the repository.
  ///
  /// An object that is absent, or never existed, yields false instead of an
  /// exception.
  Future<bool> objectExists(GitOid oid);

  /// Kind of the object [oid] names, or null when no such object is stored.
  Future<GitObjectType?> objectType(GitOid oid);

  /// Reads [oid] as a raw object: its type and its serialized content.
  ///
  /// Nothing is interpreted: a tree keeps its binary format, and a commit or
  /// a tag keeps its header lines. Throws a `GitException` when [oid] names
  /// no object.
  Future<GitRawObject> readObject(GitOid oid);

  /// Reads the content of the blob [oid] as bytes, exactly as stored.
  ///
  /// The bytes are never decoded, so a binary blob comes back unchanged.
  /// Throws a `GitException` when [oid] names no object or does not name a
  /// blob.
  Future<Uint8List> readBlob(GitOid oid);

  /// Reads the tree [oid] names.
  ///
  /// The returned tree lists its immediate entries; the paths of its entries
  /// are relative to the repository root. To read a subtree, pass the [GitOid]
  /// of the tree entry that names it.
  Future<GitTree> readTree(GitOid oid);

  /// Reads the commit [oid] names: its tree, parents, author, committer and
  /// message.
  ///
  /// Throws a `GitException` when [oid] names no object or does not name a
  /// commit.
  Future<GitCommit> readCommit(GitOid oid);

  /// Reads the annotated tag [oid] names: its target, name, tagger and
  /// message.
  ///
  /// Throws a `GitException` when [oid] names no object or does not name a
  /// tag. A lightweight tag has no tag object and cannot be read this way;
  /// resolve its ref to the object it points at instead.
  Future<GitTag> readTag(GitOid oid);
}
