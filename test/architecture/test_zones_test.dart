import 'dart:io';

import 'package:test/test.dart';

/// The generic test zones: they mirror the general layers and must stay
/// independent of the process backend.
const List<String> _genericRoots = <String>[
  'test/models',
  'test/server',
  'test/contract',
  'test/support',
];

/// The backend zone: the only one allowed to import the internal files of the
/// process backend.
const String _backendRoot = 'test/backends/process';

/// The shared test support an integration suite may use.
const String _backendSupportRoot = 'test/backends/process/support/';

/// The integration zone: it drives the public entries only.
const String _integrationRoot = 'test/end_to_end';

const String _backendSourceRoot = 'lib/src/backends/';
const String _processEntry = 'lib/process.dart';
const String _testingEntry = 'lib/testing.dart';

/// The general layers a backend test reads through the public entries.
const List<String> _coreSourceRoots = <String>[
  'lib/src/core/',
  'lib/src/models/',
  'lib/src/repository/',
  'lib/src/client/',
  'lib/src/server/',
];

/// Import, export and part directives, with their URI on a separate line.
final RegExp _directivePattern = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Constructor calls that always start the installed git.
final RegExp _realProcessCreation = RegExp(
  r'ProcessGitRunner\s*\(|ProcessBackendFactory\s*\(|ProcessGitEngine\s*\(\s*\)',
);

/// Sources that declare the `git` tag.
final RegExp _gitTag = RegExp(r'''@Tags\(\s*\[\s*['"]git['"]\s*\]\s*\)''');

void main() {
  group('test zones', () {
    test('the generic zones stay off the process backend', () {
      final List<String> violations = <String>[];
      for (final File file in _dartFilesUnder(_genericRoots)) {
        final String source = _normalize(file.path);
        final String contents = file.readAsStringSync();
        for (final String target in _targetsOf(source, contents)) {
          if (target.startsWith(_backendSourceRoot)) {
            violations.add('$source -> $target reaches the process backend');
          } else if (target == _processEntry || target == _testingEntry) {
            violations.add('$source -> $target imports a backend entry');
          } else if (target.startsWith('test/backends/')) {
            violations.add('$source -> $target imports the backend test zone');
          }
        }
        if (_realProcessCreation.hasMatch(contents) ||
            _gitTag.hasMatch(contents)) {
          violations.add('$source runs the installed git');
        }
      }
      violations.sort();
      expect(
        violations,
        isEmpty,
        reason: 'the generic zones describe behaviour every backend shares; '
            'anything touching the process backend belongs in '
            'test/backends/process/',
      );
    });

    test('the backend zone reaches the core only through the public entries',
        () {
      final List<String> violations = <String>[];
      for (final File file in _dartFilesUnder(<String>[_backendRoot])) {
        final String source = _normalize(file.path);
        for (final String target
            in _targetsOf(source, file.readAsStringSync())) {
          if (_coreSourceRoots.any(target.startsWith)) {
            violations.add('$source -> $target');
          }
        }
      }
      violations.sort();
      expect(
        violations,
        isEmpty,
        reason: 'a backend test reads the core through '
            'package:git_engine/git_engine.dart and '
            'package:git_engine/backend.dart',
      );
    });

    test('the integration zone imports no library implementation', () {
      final List<String> violations = <String>[];
      for (final File file in _dartFilesUnder(<String>[_integrationRoot])) {
        final String source = _normalize(file.path);
        for (final String target
            in _targetsOf(source, file.readAsStringSync())) {
          if (target.startsWith('lib/src/')) {
            violations.add('$source -> $target');
          } else if (target.startsWith('test/backends/') &&
              !target.startsWith(_backendSupportRoot)) {
            violations.add('$source -> $target');
          }
        }
      }
      violations.sort();
      expect(
        violations,
        isEmpty,
        reason: 'an integration suite uses the public entries and the backend '
            'test support, never a library implementation',
      );
    });
  });
}

/// Dart files under [roots], sorted by path.
List<File> _dartFilesUnder(List<String> roots) {
  final List<File> files = <File>[];
  for (final String root in roots) {
    for (final File file
        in Directory(root).listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.dart')) {
        files.add(file);
      }
    }
  }
  files.sort((File first, File second) => first.path.compareTo(second.path));
  return files;
}

/// The package-relative targets of the directives in [contents] at [source].
List<String> _targetsOf(String source, String contents) {
  final List<String> targets = <String>[];
  for (final RegExpMatch match in _directivePattern.allMatches(contents)) {
    final String? target = _resolveUri(source, match.group(1)!);
    if (target != null) {
      targets.add(target);
    }
  }
  return targets;
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
