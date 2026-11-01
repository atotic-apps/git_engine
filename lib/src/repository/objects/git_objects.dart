import '../../models/git_archive_format.dart';
import '../../models/git_identity.dart';
import '../../models/git_object_type.dart';
import '../../models/git_oid.dart';
import 'git_object_reader.dart';
import 'git_object_store.dart';
import 'git_object_writer.dart';

/// Objects, trees and commits of one repository, usable without touching the
/// work tree.
///
/// The reading operations are the [GitObjectReader] capability, addressed by
/// [GitOid]; together with [GitObjectWriter] they form the [GitObjectStore]
/// capability, which this facade implements. The rest of the facade adds
/// shortcuts and plumbing commands.
///
/// Every command runs inside the owning repository's context, so a derived
/// view applies here too: with extra environment variables, [commitTree] uses
/// them as well.
///
/// Writing is available through the [GitObjectWriter] capacity primitive
/// [writeObject]; [hashObject], [commitTree] and [archive] are shortcuts of
/// this facade.
///
/// The operations mirror git's plumbing commands ([hashObject] for
/// `hash-object`, [commitTree] for `commit-tree`, [archive] for `archive`);
/// none of them updates a ref or the work tree. Index operations live on
/// `GitIndex` instead. Every failure is a `GitException`, except where an
/// operation documents a null or false result (an absent object).
///
/// ```dart
/// final GitOid blob = await repo.objects.writeObject(
///     GitObjectType.blob, <int>[1, 2, 3]);
/// final GitCommit commit = await repo.objects.readCommit(head);
/// final GitTree tree = await repo.objects.readTree(commit.tree);
/// final Uint8List content = await repo.objects.readBlob(blob);
/// final GitOid made = await repo.objects.commitTree(
///     tree.oid, <GitOid>[head], 'Fabricated\n');
/// final Stream<List<int>> archive = repo.objects.archive(head);
/// ```
/// {@category Getting started}
abstract interface class GitObjects implements GitObjectStore {
  /// Computes the object name of [bytes] as an object of [type].
  ///
  /// Nothing is stored. Use [writeObject] to store the object. The content
  /// is hashed verbatim, including non-ASCII bytes.
  Future<GitOid> hashObject(
    List<int> bytes, {
    GitObjectType type = GitObjectType.blob,
  });

  /// Creates a commit object from [tree] and [parents] without updating any
  /// ref, like `git commit-tree`.
  ///
  /// [message] is recorded as given, byte for byte: trailing spaces, blank
  /// lines at the start or the end and lines starting with `#` are all kept.
  /// One final newline is appended when [message] does not already end with
  /// one. [author] and [committer] default to the identity git is configured
  /// with; when given they are passed through the repository context, as are
  /// [authorDate] and [committerDate]. Dates are recorded with the offset of
  /// the [DateTime] they carry.
  ///
  /// Returns the object name of the new commit.
  Future<GitOid> commitTree(
    GitOid tree,
    List<GitOid> parents,
    String message, {
    GitIdentity? author,
    GitIdentity? committer,
    DateTime? authorDate,
    DateTime? committerDate,
  });

  /// Streams an archive of [treeish] as raw bytes.
  ///
  /// [treeish] names a tree or a commit; a commit is archived as its tree. To
  /// archive a directory, resolve `<rev>:<directory>` first with
  /// `GitRevisions.resolveRevision` and pass the tree it names.
  ///
  /// The bytes arrive as they are produced, so an archive larger than memory
  /// can be written straight to a file or a response. Cancelling the
  /// subscription stops the operation and releases its resources. A failure
  /// arrives as an error of the stream, a `GitException`.
  Stream<List<int>> archive(
    GitOid treeish, {
    GitArchiveFormat format = GitArchiveFormat.tar,
  });
}
