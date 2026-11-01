import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

/// Creates the service one scenario runs against: a fresh instance per
/// scenario, wired by the backend that executes the suite.
typedef UploadPackServiceFactory = GitUploadPackService Function();

/// Declares the contract of [GitUploadPackService] over any backend.
///
/// The suite only uses the interface of the service: it addresses a
/// repository by identifier, negotiates the protocol through
/// [GitProtocolParameters], and checks the streaming promises of
/// [GitServiceResponse] — a single-subscription body, produced only for a
/// consumer, and a [GitServiceResponse.cancel] that completes. Every
/// backend that implements the interface runs this suite unchanged; the
/// bytes of a correct protocol answer are the backend's own business.
void defineGitUploadPackServiceContract(
  UploadPackServiceFactory createService,
) {
  group('GitUploadPackService contract', () {
    const GitServedRepositoryId repository =
        GitServedRepositoryId('contract-repo');

    /// A neutral request body: a single flush-pkt.
    final List<int> flushOnly = utf8.encode('0000');

    test('advertiseRefs answers a single-subscription response', () async {
      final GitUploadPackService service = createService();

      final GitServiceResponse response = await service.advertiseRefs(
        repository,
        protocol: GitProtocolParameters.empty(),
      );

      final List<int> body = await drain(response.body);
      expect(body, isNotEmpty);
      expect(
        () => response.body.listen((List<int> chunk) {}),
        throwsStateError,
        reason: 'the body is single-subscription',
      );
      await response.cancel();
    });

    test('cancel completes without the body being listened to', () async {
      final GitUploadPackService service = createService();

      final GitServiceResponse response = await service.advertiseRefs(
        repository,
        protocol: GitProtocolParameters.empty(),
      );

      await response.cancel();
    });

    test('uploadPack answers a single-subscription response', () async {
      final GitUploadPackService service = createService();

      final GitServiceResponse response = await service.uploadPack(
        repository,
        Stream<List<int>>.value(flushOnly),
        protocol: GitProtocolParameters.empty(),
      );

      final List<int> body = await drain(response.body);
      expect(body, isNotNull);
      expect(
        () => response.body.listen((List<int> chunk) {}),
        throwsStateError,
        reason: 'the body is single-subscription',
      );
      await response.cancel();
    });

    test('protocol version 2 is accepted on both operations', () async {
      final GitUploadPackService service = createService();
      final GitProtocolParameters protocol =
          GitProtocolParameters(<String>['version=2']);

      final GitServiceResponse advertisement = await service.advertiseRefs(
        repository,
        protocol: protocol,
      );
      await drain(advertisement.body);

      final GitServiceResponse rpc = await service.uploadPack(
        repository,
        Stream<List<int>>.value(flushOnly),
        protocol: protocol,
      );
      await drain(rpc.body);

      await advertisement.cancel();
      await rpc.cancel();
    });

    test('addresses every repository through its identifier', () async {
      final GitUploadPackService service = createService();
      const GitServedRepositoryId other =
          GitServedRepositoryId('contract-repo-other');

      final GitServiceResponse first = await service.advertiseRefs(
        repository,
        protocol: GitProtocolParameters.empty(),
      );
      final GitServiceResponse second = await service.advertiseRefs(
        other,
        protocol: GitProtocolParameters.empty(),
      );

      await drain(first.body);
      await drain(second.body);
      expect(first.body, isNot(same(second.body)));
      await first.cancel();
      await second.cancel();
    });
  });
}

/// Reads [body] until its end and returns the bytes it delivered.
Future<List<int>> drain(Stream<List<int>> body) async {
  final BytesBuilder builder = BytesBuilder();
  await body.forEach(builder.add);
  return builder.takeBytes();
}
