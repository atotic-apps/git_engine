import 'git_oid.dart';

/// A reference: its full name, e.g. `refs/heads/main`, and the object it
/// points at.
/// {@category Getting started}
class GitRef {
  /// Full name of the reference.
  final String name;

  /// Object the reference points at.
  final GitOid oid;

  /// Creates a reference of [name] pointing at [oid].
  const GitRef({required this.name, required this.oid});

  @override
  bool operator ==(Object other) =>
      other is GitRef && other.name == name && other.oid == oid;

  @override
  int get hashCode => Object.hash(name, oid);

  @override
  String toString() => '$name -> $oid';
}
