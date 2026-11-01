import '../core/errors/git_exception.dart';
import 'git_served_repository_id.dart';

/// A served repository identifier no backend resolution knows.
///
/// A server service resolves the [GitServedRepositoryId] a transport
/// derived from the request to the backend's own representation; when that
/// resolution knows no repository for the identifier, the service throws
/// this failure and the transport answers the client exactly as for an
/// unknown URL — 404 over smart HTTP.
/// {@category Errors}
final class GitUnknownServedRepositoryException extends GitException {
  /// The identifier no resolution knows.
  final GitServedRepositoryId repository;

  /// Creates the failure for [repository].
  GitUnknownServedRepositoryException(this.repository)
      : super('no served repository is known under "${repository.value}"');
}
