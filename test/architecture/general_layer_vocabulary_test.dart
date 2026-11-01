import 'dart:io';

import 'package:test/test.dart';

/// Directories whose documentation must not name a process-backend type.
const List<String> _generalLayerRoots = <String>[
  'lib/src/core',
  'lib/src/models',
  'lib/src/repository',
  'lib/src/client',
];

const String _backendRoot = 'lib/src/backends';

/// A public type declaration at the start of a line.
final RegExp _publicTypePattern = RegExp(
  r'^(?:abstract\s+|base\s+|final\s+|sealed\s+|interface\s+|mixin\s+)*'
  r'(?:class|enum|mixin|typedef|extension\s+type)\s+([A-Za-z]\w*)',
  multiLine: true,
);

void main() {
  group('general layers use no process-backend type name', () {
    final Set<String> backendNames = _publicBackendTypes();

    test('the backend public types are found', () {
      expect(backendNames, contains('GitCommandException'));
      expect(backendNames, contains('ProcessGitRepository'));
    });

    test('no general-layer file mentions one of them', () {
      final List<String> violations = <String>[];
      for (final String path in _generalLayerFiles()) {
        final String contents = File(path).readAsStringSync();
        for (final String name in backendNames) {
          if (RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(contents)) {
            violations.add('$path mentions $name');
          }
        }
      }
      violations.sort();
      expect(violations, isEmpty);
    });
  });
}

/// Public types declared in a file under [backendRoot].
Set<String> _publicBackendTypes() {
  final Set<String> names = <String>{};
  for (final File file
      in Directory(_backendRoot).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) {
      continue;
    }
    for (final RegExpMatch match
        in _publicTypePattern.allMatches(file.readAsStringSync())) {
      final String name = match.group(1)!;
      if (!name.startsWith('_')) {
        names.add(name);
      }
    }
  }
  return names;
}

/// Dart files under the general-layer roots, sorted by path.
List<String> _generalLayerFiles() {
  final List<String> files = <String>[];
  for (final String root in _generalLayerRoots) {
    for (final File file
        in Directory(root).listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.dart')) {
        files.add(file.path.replaceAll('\\', '/'));
      }
    }
  }
  files.sort();
  return files;
}
