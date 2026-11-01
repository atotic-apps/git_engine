@Tags(['git'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';

/// A Windows junction inside the git directory is confined like a symbolic
/// link: restoring a path that crosses it is refused, and the target outside
/// the repository keeps its content.
///
/// Junctions are a Windows feature, so this process-specific check lives here
/// rather than in the backend-independent contract suite.
void main() {
  late TestRepository testRepository;
  late GitWorkingRepository repository;
  late String gitDirectory;

  setUp(() async {
    testRepository = await createTestRepository();
    repository = await ProcessGitEngine(runner: testRepository.runner)
        .openWorking(testRepository.directory.path);
    gitDirectory = await repository.gitDir();
  });

  test(
    'restore refuses a junction that leads outside',
    () async {
      final Directory outside =
          Directory(_join(testRepository.sandbox.path, 'outside'))
            ..createSync(recursive: true);
      final File external = File(_join(outside.path, 'escaped.txt'))
        ..writeAsStringSync('pre-existing outside content\n');
      final String linkPath = _join(gitDirectory, 'junctioned');
      if (!_createJunction(linkPath, outside.path)) {
        markTestSkipped('the platform cannot create a junction');
        return;
      }
      _deleteLinkOnTearDown(linkPath);

      final GitDirectorySnapshot snapshot = GitDirectorySnapshot(
        <String, Uint8List>{
          'junctioned/escaped.txt': Uint8List.fromList(
            utf8.encode('content chosen by the snapshot\n'),
          ),
        },
      );

      await expectLater(
        repository.gitDirectoryFiles.restore(snapshot),
        throwsA(
          isA<GitException>().having(
            (GitException error) => error.message,
            'message',
            contains('junctioned/escaped.txt'),
          ),
        ),
      );
      expect(
        external.readAsStringSync(),
        'pre-existing outside content\n',
        reason: 'the target of the junction is never written',
      );
    },
    skip: Platform.isWindows ? false : 'junctions exist only on Windows',
  );
}

/// [base] joined with [relative] on the host separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

/// Creates a Windows junction at [linkPath] to [targetPath], or returns false
/// when the platform refuses it.
bool _createJunction(String linkPath, String targetPath) {
  final ProcessResult result = Process.runSync(
    'cmd',
    <String>['/c', 'mklink', '/J', linkPath, targetPath],
  );
  return result.exitCode == 0;
}

/// Deletes the link at [linkPath] with the test, so the sandbox cleanup never
/// walks through it.
void _deleteLinkOnTearDown(String linkPath) {
  addTearDown(() {
    final Link link = Link(linkPath);
    if (link.existsSync()) {
      link.deleteSync();
    }
  });
}
