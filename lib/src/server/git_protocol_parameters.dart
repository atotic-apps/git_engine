/// Git protocol negotiation parameters, independent of the transport.
///
/// Each transport carries them in its own form: the `Git-Protocol` header
/// over HTTP, the `GIT_PROTOCOL` variable over SSH. A value carries the
/// entries in the order they were received (`version=2`, a capability
/// name, …) and derives the requested protocol version from them.
/// {@category Server}
final class GitProtocolParameters {
  /// Entries `key` or `key=value`, in the order received.
  final List<String> entries;

  /// Creates parameters carrying [entries], in the order received.
  ///
  /// The list is copied; the value is immutable.
  GitProtocolParameters(List<String> entries)
      : entries = List.unmodifiable(entries);

  /// Parameters without any entry: no protocol version was requested.
  GitProtocolParameters.empty() : entries = const <String>[];

  static const String _versionPrefix = 'version=';

  /// Requested protocol version: `0` without an explicit request.
  ///
  /// Every `version=<n>` entry with a non-negative integer is considered, in
  /// order; the last valid one wins.
  int get version {
    var requested = 0;
    for (final String entry in entries) {
      if (!entry.startsWith(_versionPrefix)) {
        continue;
      }
      final int? value = int.tryParse(entry.substring(_versionPrefix.length));
      if (value != null && value >= 0) {
        requested = value;
      }
    }
    return requested;
  }

  @override
  bool operator ==(Object other) {
    if (other is! GitProtocolParameters ||
        other.entries.length != entries.length) {
      return false;
    }
    for (var i = 0; i < entries.length; i++) {
      if (other.entries[i] != entries[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(entries);

  @override
  String toString() => 'GitProtocolParameters(${entries.join(', ')})';
}
