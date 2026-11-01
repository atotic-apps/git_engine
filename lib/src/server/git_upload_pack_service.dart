import 'git_protocol_parameters.dart';
import 'git_served_repository_id.dart';
import 'git_service_response.dart';

/// Serves clone and fetch for a repository designated by its identifier.
///
/// The service implements the git protocol for one transport-independent
/// half of a fetch exchange: the reference advertisement and the stateless
/// RPC that negotiates and produces a pack. Transports (smart HTTP, later
/// SSH) route their requests to it; the repository's storage is resolved by
/// the backend that builds the service.
///
/// This is a capability contract: backends implement it, and it only grows
/// through a new interface in a major version. Implementations keep their
/// memory bounded and follow the streaming promises of [GitServiceResponse].
/// {@category Server}
/// {@category Compatibility}
abstract interface class GitUploadPackService {
  /// Produces the first response of the protocol for [repository].
  ///
  /// In protocol v0/v1 the body advertises the references; in protocol v2 it
  /// announces the capabilities, and the references then come through the
  /// `ls-refs` command of a later [uploadPack] request.
  Future<GitServiceResponse> advertiseRefs(
    GitServedRepositoryId repository, {
    required GitProtocolParameters protocol,
  });

  /// Answers one stateless RPC of [repository] — the negotiation and pack of
  /// v0/v1, or one v2 command — reading [request] only as fast as it
  /// consumes it.
  Future<GitServiceResponse> uploadPack(
    GitServedRepositoryId repository,
    Stream<List<int>> request, {
    required GitProtocolParameters protocol,
  });
}
