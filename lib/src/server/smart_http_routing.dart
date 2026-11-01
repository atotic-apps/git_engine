part of 'git_smart_http_handler.dart';

/// The protocol suffix ending [path], or a malformed request failure when
/// the path carries none.
///
/// Every suffix starts with `/`, which keeps the match on a segment
/// boundary: `/othergit-upload-pack` does not end with
/// `/git-upload-pack`.
String _protocolSuffix(String path) {
  for (final String suffix in const <String>[
    _infoRefsSuffix,
    _uploadPackSuffix,
    _receivePackSuffix,
  ]) {
    if (path.endsWith(suffix)) {
      return suffix;
    }
  }
  throw _MalformedRequestException(
    'the path carries no protocol suffix',
  );
}

/// Decodes the percent-encoded [encodedRemainder] left of the protocol
/// suffix into path segments, refusing an ambiguous path.
List<String> _decodeSegments(String encodedRemainder) {
  final String trimmed = encodedRemainder.startsWith('/')
      ? encodedRemainder.substring(1)
      : encodedRemainder;
  if (trimmed.isEmpty) {
    return const <String>[];
  }
  final List<String> segments = <String>[];
  for (final String raw in trimmed.split('/')) {
    if (raw.isEmpty) {
      throw _MalformedRequestException('empty path segment');
    }
    final String decoded;
    try {
      decoded = Uri.decodeComponent(raw);
    } on Object {
      throw _MalformedRequestException(
        'invalid percent-encoding in $raw',
      );
    }
    if (decoded.isEmpty ||
        decoded == '.' ||
        decoded == '..' ||
        decoded.contains('/') ||
        decoded.contains('\u0000')) {
      throw _MalformedRequestException(
        'ambiguous path segment: $raw',
      );
    }
    segments.add(decoded);
  }
  return segments;
}

/// The protocol parameters carried by the `Git-Protocol` header.
GitProtocolParameters _protocolParameters(GitHttpHeaders headers) {
  final List<String> entries = <String>[];
  for (final String value in headers.values('git-protocol')) {
    for (final String part in value.split(',')) {
      final String entry = part.trim();
      if (entry.isNotEmpty) {
        entries.add(entry);
      }
    }
  }
  return GitProtocolParameters(entries);
}
