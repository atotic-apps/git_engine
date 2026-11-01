import 'dart:io' show gzip;

/// The `dart:io` gzip decoder a `dart:io` transport hands to the smart HTTP
/// processing.
///
/// It accepts the `gzip` content encoding, case-insensitively, and binds the
/// gzip decoder of `dart:io` to the encoded body. Every other encoding is
/// refused by returning null, which the processing reports as 415.
Stream<List<int>>? dartIoGzipBodyDecoder(
  String contentEncoding,
  Stream<List<int>> body,
) {
  if (contentEncoding.toLowerCase() != 'gzip') {
    return null;
  }
  return gzip.decoder.bind(body);
}
