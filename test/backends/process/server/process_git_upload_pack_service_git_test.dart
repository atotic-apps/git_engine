@Tags(['git'])
library;

import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../../../contract/server/git_upload_pack_service_contract.dart';
import '../support/bare_test_repository.dart';

/// The identifiers the test resolution serves.
const Set<String> _served = <String>{
  'contract-repo',
  'contract-repo-other',
  'served',
};

Future<void> main() async {
  final BareTestRepository fixture = await BareTestRepository.create();
  tearDownAll(fixture.dispose);

  /// A fresh service per scenario, launched on the isolated runner.
  ProcessGitUploadPackService buildService() => ProcessGitUploadPackService(
        resolveRepository: (GitServedRepositoryId id) =>
            _served.contains(id.value) ? fixture.repository : null,
        launcher: ProcessGitProcessLauncher(runner: fixture.runner),
        inactivityTimeout: const Duration(minutes: 1),
        bufferBytes: 64 * 1024,
      );

  defineGitUploadPackServiceContract(buildService);

  group('ProcessGitUploadPackService advertisement', () {
    test('protocol v0 advertises the references', () async {
      final ProcessGitUploadPackService service = buildService();

      final GitServiceResponse response = await service.advertiseRefs(
        const GitServedRepositoryId('served'),
        protocol: GitProtocolParameters.empty(),
      );

      final String text =
          utf8.decode(await drain(response.body), allowMalformed: true);
      expect(text, contains(fixture.headOid),
          reason: 'the commit the bare repository serves is advertised');
      expect(text, contains(' HEAD'), reason: 'HEAD is advertised');
    });

    test('protocol v2 announces the capabilities', () async {
      final ProcessGitUploadPackService service = buildService();

      final GitServiceResponse response = await service.advertiseRefs(
        const GitServedRepositoryId('served'),
        protocol: GitProtocolParameters(<String>['version=2']),
      );

      final String text =
          utf8.decode(await drain(response.body), allowMalformed: true);
      expect(text, contains('version 2'),
          reason: 'the GIT_PROTOCOL variable reached git');
      expect(text, contains('ls-refs'),
          reason: 'the v2 capabilities are announced');
    });

    test('an identifier the resolution does not know fails as unknown',
        () async {
      final ProcessGitUploadPackService service = buildService();

      await expectLater(
        service.advertiseRefs(
          const GitServedRepositoryId('nowhere'),
          protocol: GitProtocolParameters.empty(),
        ),
        throwsA(isA<GitUnknownServedRepositoryException>()),
      );
      await expectLater(
        service.uploadPack(
          const GitServedRepositoryId('nowhere'),
          const Stream<List<int>>.empty(),
          protocol: GitProtocolParameters.empty(),
        ),
        throwsA(isA<GitUnknownServedRepositoryException>()),
      );
    });
  });

  group('ProcessGitUploadPackService negotiation', () {
    test('a protocol v0 negotiation produces a pack', () async {
      final ProcessGitUploadPackService service = buildService();
      final String request = '${_pktLine('want ${fixture.headOid}\n')}'
          '0000'
          '${_pktLine('done\n')}';

      final GitServiceResponse response = await service.uploadPack(
        const GitServedRepositoryId('served'),
        Stream<List<int>>.value(utf8.encode(request)),
        protocol: GitProtocolParameters.empty(),
      );

      final List<int> bytes = await drain(response.body);
      expect(bytes, isNotEmpty);
      final String text = utf8.decode(bytes, allowMalformed: true);
      expect(text, contains('PACK'),
          reason: 'git answered the negotiation with a packfile');
    });
  });
}

/// Frames [payload] as one pkt-line: its byte length in four hexadecimal
/// digits, then the payload.
String _pktLine(String payload) {
  final int length = payload.length + 4;
  return length.toRadixString(16).padLeft(4, '0') + payload;
}
