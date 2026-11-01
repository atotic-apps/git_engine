import 'dart:io';

import 'package:test/test.dart';

const String _contractRoot = 'test/contract';

/// Targets that bind a contract suite to one backend: the process backend's
/// own sources, its entries, and its test support.
const List<String> _forbiddenTargets = <String>[
  'lib/src/backends/',
  'lib/process.dart',
  'lib/testing.dart',
  'test/backends/',
];

/// Import and export directives, including their URI on a separate line.
final RegExp _directivePattern = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

void main() {
  group('contract suites stay backend independent', () {
    test('no contract file reaches a backend', () {
      expect(
        _violations(),
        isEmpty,
        reason: 'a contract suite runs against every backend through '
            'BackendFactory; anything specific to the process backend belongs '
            'in test/backends/',
      );
    });
  });
}

/// Backend dependencies of the contract files, sorted by key.
List<String> _violations() {
  final List<String> violations = <String>[];
  for (final File file in _contractFiles()) {
    final String source = _normalize(file.path);
    for (final RegExpMatch match
        in _directivePattern.allMatches(file.readAsStringSync())) {
      final String? target = _resolveUri(source, match.group(1)!);
      if (target != null && _isForbidden(target)) {
        violations.add('$source -> $target');
      }
    }
  }
  violations.sort();
  return violations;
}

/// The Dart files under `test/contract`, as normalized paths.
List<File> _contractFiles() {
  final List<File> files = Directory(_contractRoot)
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'))
      .toList();
  files.sort((File first, File second) => first.path.compareTo(second.path));
  return files;
}

/// Whether [target] is a backend source, entry or test support file.
bool _isForbidden(String target) {
  return _forbiddenTargets.any(
    (String forbidden) => forbidden.endsWith('/')
        ? target.startsWith(forbidden)
        : target == forbidden,
  );
}

/// The package-relative file [uri] points at, or null for an external
/// library.
String? _resolveUri(String source, String uri) {
  if (uri.startsWith('dart:')) {
    return null;
  }
  if (uri.startsWith('package:git_engine/')) {
    return _normalize('lib/${uri.substring('package:git_engine/'.length)}');
  }
  if (uri.contains(':')) {
    return null;
  }
  final int slash = source.lastIndexOf('/');
  final String directory = slash < 0 ? '' : source.substring(0, slash);
  return _normalize('$directory/$uri');
}

/// [path] with forward slashes and no `.` or `..` segment.
String _normalize(String path) {
  final List<String> parts = path.replaceAll('\\', '/').split('/');
  final List<String> normalized = <String>[];
  for (final String part in parts) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (normalized.isNotEmpty) {
        normalized.removeLast();
      }
      continue;
    }
    normalized.add(part);
  }
  return normalized.join('/');
}
