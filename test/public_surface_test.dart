import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';
import 'package:test/test.dart';

/// The process backend is reachable only through `process.dart`: importing
/// the contracts and the process entry point together builds the engine, and
/// `git_engine.dart` exports no process-backend name.
void main() {
  test('the contracts and process.dart build the engine', () {
    final ProcessGitEngine engine = ProcessGitEngine(executable: 'git');

    expect(engine, isA<GitRepositoryManager>());
    expect(engine, isA<GitFileClient>());
    expect(engine, isA<GitEngineRuntime>());
  });

  test('git_engine.dart exports no process backend name', () {
    final String source = File('lib/git_engine.dart').readAsStringSync();

    expect(source, isNot(contains('ProcessGit')));
    expect(source, isNot(contains('GitCommandException')));
    expect(source, isNot(contains('runCommand')));
    expect(source, isNot(contains('withIndexFile')));
  });
}
