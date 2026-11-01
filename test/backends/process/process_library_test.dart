import 'dart:io';

import 'package:git_engine/process.dart';
import 'package:test/test.dart';

/// `lib/process.dart` exposes exactly the entry points needed to build the
/// process backend; everything else comes from the contracts of
/// `package:git_engine/git_engine.dart`.
const List<String> _expectedProcessNames = <String>[
  'GitExecutableNotFoundException',
  'ProcessGitEngine',
  'ProcessGitUploadPackService',
];

/// Every name shown by an export directive of [source], in order.
List<String> _exportedNames(String source) {
  final RegExp exportPattern = RegExp(
    r"export\s+'[^']+'\s+show\s+([^;]+);",
    multiLine: true,
  );
  final List<String> names = <String>[];
  for (final RegExpMatch export in exportPattern.allMatches(source)) {
    for (final String part in export.group(1)!.split(',')) {
      final String name = part.trim();
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
  }
  return names;
}

void main() {
  test('process.dart exposes the process backend entry points', () {
    final Object engineConstructor = ProcessGitEngine.new;
    final Object uploadPackConstructor = ProcessGitUploadPackService.new;
    final GitExecutableNotFoundException notFound =
        GitExecutableNotFoundException('git');

    expect(engineConstructor, isA<Function>());
    expect(uploadPackConstructor, isA<Function>());
    expect(notFound.executable, 'git');
  });

  test('process.dart exports exactly its documented entry points', () {
    final String source = File('lib/process.dart').readAsStringSync();

    expect(
      _exportedNames(source),
      unorderedEquals(_expectedProcessNames),
      reason: 'the process entry points are a closed list',
    );
  });
}
