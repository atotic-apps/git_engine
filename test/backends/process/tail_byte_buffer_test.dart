import 'dart:typed_data';

import 'package:git_engine/src/backends/process/tail_byte_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('TailByteBuffer', () {
    test('returns a short stream unchanged', () {
      final TailByteBuffer buffer = TailByteBuffer();
      buffer.add(const <int>[1, 2, 3]);
      buffer.add(const <int>[4, 5]);

      expect(buffer.takeBytes(), <int>[1, 2, 3, 4, 5]);
    });

    test('keeps only the most recent bytes of a stream over the limit', () {
      final TailByteBuffer buffer = TailByteBuffer();
      final Uint8List chunk = Uint8List(1024 * 1024);
      chunk.fillRange(0, chunk.length, 120);
      buffer.add(const <int>[101, 97, 114, 108, 121]);
      for (var index = 0; index < 17; index++) {
        buffer.add(chunk);
      }
      buffer.add(const <int>[108, 97, 116, 101]);
      final Uint8List retained = buffer.takeBytes();

      expect(retained.length, defaultTailByteBufferLimit);
      expect(retained.sublist(retained.length - 4), <int>[108, 97, 116, 101]);
      expect(retained.sublist(0, 5), isNot(<int>[101, 97, 114, 108, 121]));
    });

    test('keeps the last bytes of a chunk larger than the limit', () {
      final TailByteBuffer buffer = TailByteBuffer(limit: 4);
      buffer.add(const <int>[1, 2, 3, 4, 5, 6, 7, 8, 9]);

      expect(buffer.takeBytes(), <int>[6, 7, 8, 9]);
    });

    test('drops the oldest bytes once the buffer doubles the limit', () {
      final TailByteBuffer buffer = TailByteBuffer(limit: 4);
      for (var value = 1; value <= 9; value++) {
        buffer.add(<int>[value]);
      }

      expect(buffer.takeBytes(), <int>[6, 7, 8, 9]);
    });

    test('returns nothing for an empty stream', () {
      expect(TailByteBuffer().takeBytes(), isEmpty);
    });
  });
}
