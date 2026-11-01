import '../../models/git_identity.dart';
import '../../models/git_oid.dart';
import '../../models/git_tag_ref.dart';
import '../refs/git_invalid_ref_name_exception.dart';
import '../refs/git_ref_exists_exception.dart';
import '../refs/git_ref_not_found_exception.dart';
import '../refs/git_unknown_revision_exception.dart';

/// Tags of one repository: listing, creating and deleting.
///
/// A tag is annotated or lightweight. An annotated tag names a tag object;
/// its content — the object it points at, its tagger and its message — is
/// read through `GitObjectReader.readTag` with the object name the listing's
/// `GitTagRef.oid` carries. A lightweight tag is only a reference naming its
/// target object.
///
/// Every command runs inside the owning repository's context, so a derived
/// view (an alternate index, extra environment variables) applies here too.
/// Every failure is a `GitException`; the refusals a caller can treat are
/// named on the operation.
///
/// The tag names the operations take are short names, rejected before any
/// command runs when they cannot be reference names: the rules documented
/// on [GitInvalidRefNameException]. A violating name raises
/// [GitInvalidRefNameException] before any git call.
///
/// ```dart
/// final List<GitTagRef> tags = await repo.tags.list();
/// await repo.tags.create('v1.0.0', head, message: 'First release');
/// await repo.tags.create('snapshot', base);
/// await repo.tags.delete('snapshot');
/// ```
/// {@category Getting started}
abstract interface class GitTags {
  /// Tags, sorted by name, annotated and lightweight ones alike.
  Future<List<GitTagRef>> list();

  /// Creates the tag [name] on [target].
  ///
  /// With [message] the tag is annotated and [tagger] and [date] name its
  /// author and its instant; both default to the identity git is configured
  /// with and to now. Without [message] the tag is lightweight. With [force],
  /// an existing tag is moved to [target] instead of the refusal below.
  ///
  /// Raises [GitInvalidRefNameException] when [name] cannot be a tag name,
  /// [GitRefExistsException] when [name] is already taken and [force]
  /// is false, [GitUnknownRevisionException] when [target] names no object.
  Future<void> create(
    String name,
    GitOid target, {
    String? message,
    GitIdentity? tagger,
    DateTime? date,
    bool force = false,
  });

  /// Deletes the tag [name].
  ///
  /// Raises [GitInvalidRefNameException] when [name] cannot be a tag name,
  /// [GitRefNotFoundException] when [name] does not exist.
  Future<void> delete(String name);
}
