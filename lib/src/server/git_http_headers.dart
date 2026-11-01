/// Multi-valued HTTP headers with case-insensitive names.
///
/// A request or a response carries every value it was given: sending the same
/// name twice keeps both values. Name lookups ignore case; names are stored
/// lower-cased. The value is immutable — lists are copied on construction.
/// {@category Server}
final class GitHttpHeaders {
  final Map<String, List<String>> _values;

  /// Creates headers carrying [values], keyed by original name and keeping
  /// every value of every name.
  GitHttpHeaders(Map<String, List<String>> values) : _values = _copy(values);

  /// Headers without any name.
  const GitHttpHeaders.empty() : _values = const <String, List<String>>{};

  static Map<String, List<String>> _copy(Map<String, List<String>> values) {
    final Map<String, List<String>> copied = <String, List<String>>{};
    values.forEach((String name, List<String> headerValues) {
      copied[name.toLowerCase()] = List.unmodifiable(headerValues);
    });
    return Map.unmodifiable(copied);
  }

  /// Every value of [name], in order; empty when the name is absent.
  List<String> values(String name) =>
      _values[name.toLowerCase()] ?? const <String>[];

  /// The first value of [name], or null when the name is absent.
  String? firstValue(String name) {
    final List<String> headerValues = values(name);
    return headerValues.isEmpty ? null : headerValues.first;
  }

  /// Whether [name] carries at least one value.
  bool contains(String name) => _values.containsKey(name.toLowerCase());

  /// The stored names, lower-cased.
  Iterable<String> get names => _values.keys;

  /// A copy of the headers as a map keyed by lower-cased name.
  Map<String, List<String>> toMap() => Map<String, List<String>>.of(_values);

  @override
  String toString() {
    final List<String> rendered = <String>[];
    _values.forEach((String name, List<String> headerValues) {
      for (final String value in headerValues) {
        rendered.add('$name: $value');
      }
    });
    return rendered.join('\n');
  }
}
