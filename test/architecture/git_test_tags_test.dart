import 'dart:io';

import 'package:test/test.dart';

const String _testRoot = 'test';

/// This checker names the markers it looks for, so it never flags itself.
const String _checkerPath = 'test/architecture/git_test_tags_test.dart';

/// Import directives, including the URI on a separate line.
final RegExp _importPattern = RegExp(
  r'''^\s*import\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Constructor calls that always start the installed git: the real runner,
/// the real factory, and an engine left on its default runner.
final RegExp _realProcessCreation = RegExp(
  r'ProcessGitRunner\s*\(|ProcessBackendFactory\s*\(|ProcessGitEngine\s*\(\s*\)',
);

/// Calls that touch the real machine instead of a seam: temporary
/// directories, external processes, loopback or remote sockets, and the
/// ambient environment. Reading the package sources with `File` stays
/// allowed, so architecture and documentation checks need no tag.
final RegExp _realMachineUse = RegExp(
  r'Directory\s*\.\s*systemTemp'
  r'|Process\s*\.\s*(?:run|runSync|start)\s*\('
  r'|Platform\s*\.\s*environment\b'
  r'|(?:HttpServer|ServerSocket|SecureServerSocket|RawServerSocket'
  r'|RawSecureServerSocket|DartIoGitHttpServer)\s*\.\s*bind\s*\('
  r'|(?:Socket|RawSocket|SecureSocket|WebSocket)\s*\.\s*connect\s*\('
  r'|HttpClient\s*\(',
);

/// Sources that declare the `git` tag.
final RegExp _gitTag = RegExp(r'''@Tags\(\s*\[\s*['"]git['"]\s*\]\s*\)''');

/// Sources that declare either tag making `dart test` skip them.
final RegExp _skipTag = RegExp(
  r'''@Tags\(\s*\[[^\]]*['"](?:git|machine)['"][^\]]*\]\s*\)''',
);

/// The zone whose checkers read the sources and never touch the machine.
const String _architectureRoot = 'test/architecture/';

void main() {
  group('tests that need the installed git', () {
    test('declare the git tag', () {
      final List<String> untagged = <String>[];
      for (final File file in _testEntrypoints()) {
        if (_isExcluded(file.path)) {
          continue;
        }
        final String source = file.readAsStringSync();
        if (_needsInstalledGit(file.path, source) &&
            !_gitTag.hasMatch(source)) {
          untagged.add(_normalize(file.path));
        }
      }
      untagged.sort();
      expect(
        untagged,
        isEmpty,
        reason: 'a test that runs the installed git '
            'must carry @Tags([\'git\']) so `dart test` skips it and '
            '`dart test --run-skipped` runs it',
      );
    });

    test('are skipped by default', () {
      final String config = File('dart_test.yaml').readAsStringSync();
      expect(config, contains('git:'));
      expect(config, contains('skip:'));
      expect(config, contains('--run-skipped'));
    });
  });

  group('tests that need the real machine without git', () {
    test('declare the machine tag', () {
      final List<String> untagged = <String>[];
      for (final File file in _testEntrypoints()) {
        if (_isExcluded(file.path)) {
          continue;
        }
        final String source = file.readAsStringSync();
        if (_needsRealMachine(file.path, source) &&
            !_skipTag.hasMatch(source)) {
          untagged.add(_normalize(file.path));
        }
      }
      untagged.sort();
      expect(
        untagged,
        isEmpty,
        reason: 'a test that creates temporary directories, runs an external '
            'process, opens a real socket or reads Platform.environment '
            'needs the real machine: it must carry @Tags([\'git\']) or '
            '@Tags([\'machine\']) so `dart test` skips it and '
            '`dart test --run-skipped` runs it',
      );
    });

    test('are skipped by default', () {
      final String config = File('dart_test.yaml').readAsStringSync();
      expect(config, contains('machine:'));
      expect(config, contains('skip:'));
      expect(config, contains('--run-skipped'));
    });
  });
}

/// Whether [path] belongs to a zone the checker leaves alone.
bool _isExcluded(String path) {
  final String normalized = _normalize(path);
  return normalized == _checkerPath || normalized.startsWith(_architectureRoot);
}

/// Test entrypoints: every `*_test.dart` file under `test/`.
List<File> _testEntrypoints() {
  final List<File> files = Directory(_testRoot)
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('_test.dart'))
      .toList();
  files.sort((File first, File second) => first.path.compareTo(second.path));
  return files;
}

/// Whether the test [source] at [path] depends on the installed git.
///
/// A test needs git when it, or one of its relative imports followed
/// transitively, creates the real runner, the real factory, or an engine left
/// on its default runner. A helper built on the runner seam of
/// `package:git_engine/testing.dart` needs no installed git.
bool _needsInstalledGit(String path, String source) {
  return _needsFrom(_normalize(path), source, _realProcessCreation, <String>{});
}

/// Whether the test [source] at [path] needs the real machine without git.
///
/// A test needs the machine when it, or one of its relative imports followed
/// transitively, creates a real temporary directory, runs an external process,
/// opens a real socket or reads the ambient environment. A helper built on the
/// file-system, launcher or platform seam of
/// `package:git_engine/testing.dart` needs no real machine.
bool _needsRealMachine(String path, String source) {
  return _needsFrom(_normalize(path), source, _realMachineUse, <String>{});
}

/// Whether [path] with [source] contains [marker], following relative imports
/// without visiting a file twice.
bool _needsFrom(
  String path,
  String source,
  RegExp marker,
  Set<String> visited,
) {
  if (!visited.add(path)) {
    return false;
  }
  if (marker.hasMatch(source)) {
    return true;
  }
  for (final RegExpMatch match in _importPattern.allMatches(source)) {
    final String? imported = _resolveImport(path, match.group(1)!);
    if (imported == null) {
      continue;
    }
    final File file = File(imported);
    if (!file.existsSync()) {
      continue;
    }
    if (_needsFrom(imported, file.readAsStringSync(), marker, visited)) {
      return true;
    }
  }
  return false;
}

/// The package-relative file [uri] points at, or null for an external
/// library.
String? _resolveImport(String source, String uri) {
  if (uri.startsWith('dart:') ||
      uri.startsWith('package:') ||
      uri.contains(':')) {
    return null;
  }
  final String normalized = _normalize(source);
  final int slash = normalized.lastIndexOf('/');
  final String directory = slash < 0 ? '' : normalized.substring(0, slash);
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
