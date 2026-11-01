import 'dart:io';

import 'package:test/test.dart';

/// Directory names that are test-only: they group suites or helpers instead
/// of mirroring a source directory.
const Set<String> _testOnlyDirectories = <String>{
  'architecture',
  'contract',
  'end_to_end',
  'support',
};

const String _testRoot = 'test';
const String _sourceRoot = 'lib/src';

void main() {
  group('test layout mirrors lib/src', () {
    test('every test directory has a lib/src counterpart', () {
      expect(
        _unmatchedDirectories(),
        isEmpty,
        reason: 'each test directory must mirror the source directory of the '
            'code it tests',
      );
    });
  });
}

/// Test directories, relative to `test/`, that have no counterpart under
/// `lib/src/`, sorted by path.
List<String> _unmatchedDirectories() {
  final List<String> unmatched = <String>[];
  for (final Directory directory in Directory(_testRoot)
      .listSync(recursive: true)
      .whereType<Directory>()) {
    final String relative = _relativeToTest(directory.path);
    if (relative.isEmpty) {
      continue;
    }
    final List<String> segments = relative.split('/');
    if (segments.any(_testOnlyDirectories.contains)) {
      continue;
    }
    if (!Directory('$_sourceRoot/$relative').existsSync()) {
      unmatched.add(relative);
    }
  }
  unmatched.sort();
  return unmatched;
}

/// [path] relative to `test/`, with forward slashes.
String _relativeToTest(String path) {
  final String normalized = path.replaceAll('\\', '/');
  const String prefix = '$_testRoot/';
  return normalized.startsWith(prefix)
      ? normalized.substring(prefix.length)
      : normalized;
}
