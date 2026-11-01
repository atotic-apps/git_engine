import 'dart:async';

import 'git_principal.dart';
import 'git_served_repository_id.dart';

/// Decides whether an identity may read or write a served repository.
///
/// The policy receives the authenticated identity (null = anonymous) and the
/// [GitServedRepositoryId], never the repository itself, and may decide
/// asynchronously. [canRead] guards clone and fetch; [canWrite] guards push
/// once a receive-pack service exists. Both members are part of the contract
/// from the start so that its shape is proven before push arrives.
///
/// This is a capability contract: host applications implement it, and it only
/// grows through a new interface in a major version.
/// {@category Server}
/// {@category Compatibility}
abstract interface class GitAuthorizationPolicy {
  /// Whether [principal] may read [repository].
  FutureOr<bool> canRead(
    GitPrincipal? principal,
    GitServedRepositoryId repository,
  );

  /// Whether [principal] may write [repository].
  FutureOr<bool> canWrite(
    GitPrincipal? principal,
    GitServedRepositoryId repository,
  );
}

/// The read-only policy shipped with the library: reading is allowed to
/// everyone, including anonymous requests, and writing is refused.
/// {@category Server}
final class GitReadOnlyAuthorizationPolicy implements GitAuthorizationPolicy {
  /// Creates the policy.
  const GitReadOnlyAuthorizationPolicy();

  @override
  bool canRead(
    GitPrincipal? principal,
    GitServedRepositoryId repository,
  ) =>
      true;

  @override
  bool canWrite(
    GitPrincipal? principal,
    GitServedRepositoryId repository,
  ) =>
      false;
}
