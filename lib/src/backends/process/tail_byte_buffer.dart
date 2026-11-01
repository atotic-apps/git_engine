import 'dart:typed_data';

/// Default number of most recent bytes [TailByteBuffer] keeps: 16 MiB.
const int defaultTailByteBufferLimit = 16 * 1024 * 1024;

/// Keeps the most recent bytes written to it, up to a fixed limit.
///
/// The retained bytes are the tail of the stream, never its beginning: a
/// failing command is diagnosed from its final message. The buffer may hold
/// up to twice [limit] before it drops the oldest bytes, so trimming is paid
/// once per limit worth of output rather than on every chunk. [takeBytes]
/// always returns at most [limit] bytes.
///
/// Adding a chunk never throws and never stops the producer: an endless
/// stream simply loses its oldest part.
final class TailByteBuffer {
  /// Creates a buffer retaining the most recent [limit] bytes.
  TailByteBuffer({this.limit = defaultTailByteBufferLimit})
      : assert(limit > 0, 'limit must be positive');

  /// Maximum number of bytes [takeBytes] returns.
  final int limit;

  final BytesBuilder _bytes = BytesBuilder(copy: false);

  /// Adds [chunk], dropping the oldest bytes once the buffer outgrows the
  /// limit.
  void add(List<int> chunk) {
    if (chunk.isEmpty) {
      return;
    }
    if (chunk.length >= limit) {
      _bytes.clear();
      _bytes.add(chunk.sublist(chunk.length - limit));
      return;
    }
    _bytes.add(chunk);
    if (_bytes.length > limit * 2) {
      final Uint8List held = _bytes.takeBytes();
      _bytes.add(held.sublist(held.length - limit));
    }
  }

  /// Returns the retained bytes and empties the buffer: at most [limit]
  /// bytes, the most recent ones.
  Uint8List takeBytes() {
    final Uint8List held = _bytes.takeBytes();
    if (held.length <= limit) {
      return held;
    }
    return held.sublist(held.length - limit);
  }
}
