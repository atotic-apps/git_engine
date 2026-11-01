/// An identity authenticated by the host application.
///
/// Minimal capability contract: the host's own user type implements it, and
/// no role model is imposed. A null [GitPrincipal] means an anonymous
/// request; authorization decisions receive the identity, the served
/// repository identifier, and never the repository itself.
///
/// This is a capability contract: the host's own user type implements it, and
/// it only grows through a new interface in a major version.
/// {@category Server}
/// {@category Compatibility}
abstract interface class GitPrincipal {
  /// Name of the identity, for authorization decisions and logs.
  String get name;
}
