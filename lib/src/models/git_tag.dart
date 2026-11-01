import 'git_identity.dart';
import 'git_object_type.dart';
import 'git_oid.dart';

/// An annotated tag object: the object it points at, its name, the tagger and
/// the message.
///
/// A lightweight tag has no tag object; it is only a ref pointing straight at
/// its target and cannot be read as a [GitTag].
/// {@category Getting started}
class GitTag {
  /// Object the tag points at.
  final GitOid target;

  /// Kind of the object [target] names.
  final GitObjectType targetType;

  /// Tag name without the `refs/tags/` prefix, e.g. `v1.0.0`.
  final String name;

  /// Identity that created the tag.
  final GitIdentity tagger;

  /// Instant the tag was created, in UTC.
  final DateTime taggerDate;

  /// Tag message without git's trailing newline.
  final String message;

  /// Creates a tag named [name] pointing at [target] of [targetType], made
  /// by [tagger] with [message].
  GitTag({
    required this.target,
    required this.targetType,
    required this.name,
    required this.tagger,
    required this.taggerDate,
    required this.message,
  });

  @override
  String toString() => 'tag $name -> ${targetType.name} $target';
}
