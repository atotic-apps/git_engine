import 'git_oid.dart';

/// A tag reference: its short name, the object the reference names and the
/// final object that object resolves to.
/// {@category Getting started}
class GitTagRef {
  /// Tag name without the `refs/tags/` prefix, e.g. `v1.0.0`.
  final String name;

  /// Object the reference names: the tag object of an annotated tag, the
  /// target object of a lightweight one.
  final GitOid oid;

  /// Final object the tag resolves to: [oid] itself for a lightweight tag,
  /// the object the tag points at for an annotated one.
  final GitOid target;

  /// Whether the reference names a tag object, i.e. the tag is annotated.
  final bool isAnnotated;

  /// Creates a tag named [name] on [oid], resolving to [target], annotated
  /// when [isAnnotated] holds.
  const GitTagRef({
    required this.name,
    required this.oid,
    required this.target,
    required this.isAnnotated,
  });

  @override
  bool operator ==(Object other) =>
      other is GitTagRef &&
      other.name == name &&
      other.oid == oid &&
      other.target == target &&
      other.isAnnotated == isAnnotated;

  @override
  int get hashCode => Object.hash(name, oid, target, isAnnotated);

  @override
  String toString() => '$name -> $target${isAnnotated ? ' (annotated)' : ''}';
}
