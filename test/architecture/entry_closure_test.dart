import 'dart:io';

import 'package:test/test.dart';

/// Import, export and part directives, with their URI on a separate line.
final RegExp _directivePattern = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

const String _backendRoot = 'lib/src/backends/';
const String _dartIoAdapterRoot = 'lib/src/server/dart_io/';

const List<String> _platformLibraries = <String>['dart:io', 'dart:ffi'];

const List<String> _entries = <String>[
  'lib/git_engine.dart',
  'lib/backend.dart',
];

void main() {
  group('entry closure', () {
    for (final String entry in _entries) {
      test('$entry reaches no platform library nor backend implementation', () {
        final _Closure closure = _closureFrom(entry);
        expect(
          closure.libraries.where(_platformLibraries.contains),
          isEmpty,
          reason: '$entry must stay free of dart:io and dart:ffi',
        );
        expect(
          closure.files.where(_isImplementation),
          isEmpty,
          reason: '$entry must not reach the process backend or the dart:io '
              'server adapter',
        );
      });
    }

    test('the closure follows imports, exports and parts', () {
      final _Closure closure = _closureFrom('lib/git_engine.dart');
      expect(
        closure.files,
        containsAll(<String>[
          'lib/src/core/errors/git_exception.dart',
          'lib/src/models/git_oid.dart',
          'lib/src/repository/git_repository.dart',
          'lib/src/server/git_smart_http_handler.dart',
        ]),
      );
      expect(
        closure.files.where(_isImplementation),
        isEmpty,
      );
    });
  });
}

/// The files and `dart:` libraries reachable from [entry] through its import,
/// export and part directives.
_Closure _closureFrom(String entry) {
  final Set<String> visited = <String>{};
  final Set<String> libraries = <String>{};
  final List<String> pending = <String>[entry];
  while (pending.isNotEmpty) {
    final String path = pending.removeLast();
    if (!visited.add(path)) {
      continue;
    }
    for (final RegExpMatch match
        in _directivePattern.allMatches(File(path).readAsStringSync())) {
      final String uri = match.group(1)!;
      if (uri.startsWith('dart:')) {
        libraries.add(uri);
        continue;
      }
      final String? target = _resolveUri(path, uri);
      if (target != null && File(target).existsSync()) {
        pending.add(target);
      }
    }
  }
  return _Closure(visited, libraries);
}

/// The package-relative file [uri] points at, or null for another package.
String? _resolveUri(String source, String uri) {
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

/// Whether [path] is a process backend or dart:io server file.
bool _isImplementation(String path) {
  return path.startsWith(_backendRoot) || path.startsWith(_dartIoAdapterRoot);
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

/// A reachable set: files and `dart:` libraries.
class _Closure {
  const _Closure(this.files, this.libraries);

  final Set<String> files;
  final Set<String> libraries;
}
