import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

/// Decoding of the run result carried by the runner seam: raw bytes are
/// kept as received, the UTF-8 spelling is produced on demand, generation
/// failure is tolerated, and [GitRunResult.fromStrings] prepares results for
/// fake runners.
void main() {
  group('GitRunResult decoding', () {
    test('keeps raw bytes and decodes UTF-8 on demand', () {
      final GitRunResult result = GitRunResult(
        stdoutBytes: Uint8List.fromList(utf8.encode('héllo\n')),
        stderrBytes: Uint8List.fromList(utf8.encode('wörld\n')),
      );

      expect(result.stdout, 'héllo\n');
      expect(result.stderr, 'wörld\n');
      expect(result.stdoutBytes[1], 0xC3);
      expect(result.exitCode, 0);
    });

    test('tolerates malformed UTF-8 instead of throwing', () {
      final GitRunResult result = GitRunResult(
        stdoutBytes: Uint8List.fromList(<int>[0x61, 0xFF, 0x62]),
        stderrBytes: Uint8List(0),
      );

      expect(result.stdout, contains('�'));
      expect(result.stdoutBytes[1], 0xFF);
    });

    test('fromStrings builds results for fake runners', () {
      final GitRunResult result =
          GitRunResult.fromStrings('out', stderr: 'err', exitCode: 3);

      expect(result.stdout, 'out');
      expect(result.stderr, 'err');
      expect(result.exitCode, 3);
    });
  });
}
