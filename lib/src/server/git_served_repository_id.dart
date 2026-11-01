/// Opaque identifier of a served repository, chosen by the host application.
///
/// The host maps each repository it serves to an identifier of its own; every
/// server contract ([GitPrincipal]-based authorization, upload-pack services)
/// addresses repositories through this value and never sees a path or a
/// storage location. A backend resolves the identifier to its own
/// representation.
///
/// The value is immutable, with equality and `hashCode` by value. No
/// normalization is ever applied: no `.git` suffix removal, no case change,
/// no interpretation as a path.
/// {@category Server}
final class GitServedRepositoryId {
  /// The identifier as chosen by the host.
  final String value;

  /// Creates the identifier [value].
  const GitServedRepositoryId(this.value);

  @override
  bool operator ==(Object other) =>
      other is GitServedRepositoryId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
