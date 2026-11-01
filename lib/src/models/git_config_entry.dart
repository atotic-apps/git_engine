/// One key/value pair of a git configuration.
/// {@category Getting started}
class GitConfigEntry {
  /// Configuration key, e.g. `remote.origin.url`.
  final String key;

  /// Value recorded for [key].
  final String value;

  /// Creates a pair of [key] and [value].
  const GitConfigEntry({required this.key, required this.value});

  @override
  bool operator ==(Object other) =>
      other is GitConfigEntry && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(key, value);

  @override
  String toString() => '$key = $value';
}
