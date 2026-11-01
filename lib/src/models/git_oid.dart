/// A git object name: a 40-character (SHA-1) or 64-character (SHA-256)
/// hexadecimal string.
///
/// Values are validated at construction and normalized to lower case. A
/// complete object name is required: an abbreviation, a reference name and a
/// revision expression are all refused, so a value taken from outside is
/// never handed to git unvalidated.
/// {@category Getting started}
class GitOid {
  static final RegExp _hexadecimal = RegExp(r'^[0-9a-fA-F]+$');

  /// Normalized (lower case) hexadecimal form of the object name.
  final String value;

  GitOid._(this.value);

  /// Parses [hex] into a [GitOid].
  ///
  /// Throws [FormatException] when [hex] is not exactly 40 or 64 hexadecimal
  /// characters.
  factory GitOid.parse(String hex) {
    final String? error = validateHex(hex);
    if (error != null) {
      throw FormatException('Invalid git object id: $error', hex);
    }
    return GitOid._(hex.toLowerCase());
  }

  /// Parses [hex] into a [GitOid], returning null instead of throwing when
  /// [hex] is not a valid object name.
  static GitOid? tryParse(String hex) {
    if (validateHex(hex) != null) {
      return null;
    }
    return GitOid._(hex.toLowerCase());
  }

  /// Returns null when [hex] is a valid object name, otherwise a short
  /// description of the problem.
  static String? validateHex(String hex) {
    if (hex.length != 40 && hex.length != 64) {
      return 'expected 40 or 64 characters, got ${hex.length}';
    }
    if (!_hexadecimal.hasMatch(hex)) {
      return 'expected hexadecimal characters only';
    }
    return null;
  }

  /// Whether this object name belongs to a SHA-256 repository.
  bool get isSha256 => value.length == 64;

  /// Short (abbreviated) form used in human-facing output; git's own default
  /// abbreviation is 7 characters.
  String short([int length = 7]) {
    if (length < 1) {
      throw RangeError.range(length, 1, null, 'length');
    }
    if (length >= value.length) {
      return value;
    }
    return value.substring(0, length);
  }

  @override
  bool operator ==(Object other) => other is GitOid && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
