import 'dart:io';

import 'package:test/test.dart';

/// The `dart:io` server entry point and the declarations it exposes.
const Map<String, String> _serverIoExports = <String, String>{
  'DartIoGitHttpServer': 'src/server/dart_io/dart_io_git_http_server.dart',
  'dartIoGzipBodyDecoder': 'src/server/dart_io/dart_io_body_decoder.dart',
};

void main() {
  group('dart:io server entry point', () {
    test('server_io.dart exports the documented adapter declarations', () {
      final String source = File('lib/server_io.dart').readAsStringSync();
      for (final MapEntry<String, String> exported
          in _serverIoExports.entries) {
        expect(
          source,
          contains("export '${exported.value}'"),
          reason: '${exported.key} must stay in its adapter file',
        );
        expect(
          RegExp('show\\s+${exported.key}\\b').hasMatch(source),
          isTrue,
          reason: 'server_io.dart must export ${exported.key}',
        );
      }
    });
  });
}
