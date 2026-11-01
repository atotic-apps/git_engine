import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the confinement contract of [GitDirectoryFiles] for [factory].
///
/// Restoring or drifting a path that leaves the git directory through a
/// symbolic link is refused, and files outside the repository are never
/// touched. Capture and restore keep nested files verbatim.
void defineGitDirectoryConfinementContract(BackendFactory factory) {
  group('GitDirectoryFiles confinement', () {
    late GitWorkingRepository repository;
    late String gitDirectory;

    setUp(() async {
      repository = await factory.createWorkingRepository();
      gitDirectory = await repository.gitDir();
    });

    test('restore refuses a directory link that leads outside', () async {
      final Directory outside = Directory(_join(repository.path, 'outside'))
        ..createSync(recursive: true);
      final File external = File(_join(outside.path, 'escaped.txt'))
        ..writeAsStringSync('pre-existing outside content\n');
      final String linkPath = _join(gitDirectory, 'linked');
      if (!_createLink(linkPath, outside.path)) {
        markTestSkipped('the platform cannot create a directory symbolic link');
        return;
      }
      _deleteLinkOnTearDown(linkPath);

      final GitDirectorySnapshot snapshot = GitDirectorySnapshot(
        <String, Uint8List>{
          'linked/escaped.txt': Uint8List.fromList(
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
            contains('linked/escaped.txt'),
          ),
        ),
      );
      expect(
        external.readAsStringSync(),
        'pre-existing outside content\n',
        reason: 'the target of the link is never written',
      );
    });

    test('restore refuses a file link that leads outside', () async {
      final Directory outside = Directory(_join(repository.path, 'outside'))
        ..createSync(recursive: true);
      final File external = File(_join(outside.path, 'escaped.txt'))
        ..writeAsStringSync('pre-existing outside content\n');
      final String linkPath = _join(gitDirectory, 'linked.txt');
      if (!_createLink(linkPath, external.path)) {
        markTestSkipped('the platform cannot create a file symbolic link');
        return;
      }
      _deleteLinkOnTearDown(linkPath);

      final GitDirectorySnapshot snapshot = GitDirectorySnapshot(
        <String, Uint8List>{
          'linked.txt': Uint8List.fromList(
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
            contains('linked.txt'),
          ),
        ),
      );
      expect(
        external.readAsStringSync(),
        'pre-existing outside content\n',
        reason: 'the target of the link is never written',
      );
    });

    test('drift never exposes a file outside the git directory', () async {
      final Directory outside = Directory(_join(repository.path, 'outside'))
        ..createSync(recursive: true);
      final File secret = File(_join(outside.path, 'secret.txt'))
        ..writeAsStringSync('outside secret\n');
      final String linkPath = _join(gitDirectory, 'linked');
      if (!_createLink(linkPath, outside.path)) {
        markTestSkipped('the platform cannot create a directory symbolic link');
        return;
      }
      _deleteLinkOnTearDown(linkPath);

      final GitDirectorySnapshot capture =
          await repository.gitDirectoryFiles.capture();
      expect(
        capture.files.keys,
        isNot(contains('linked/secret.txt')),
        reason: 'a capture never follows a link outside',
      );

      final GitDirectoryDrift drift =
          await repository.gitDirectoryFiles.drift(capture);

      expect(
        drift.added.where((String path) => path.startsWith('linked')),
        isEmpty,
        reason: 'the linked directory contributes no drift',
      );
      expect(drift.added, isNot(contains('linked/secret.txt')));
      expect(secret.readAsStringSync(), 'outside secret\n');

      final GitDirectorySnapshot naming = GitDirectorySnapshot(
        <String, Uint8List>{'linked/secret.txt': Uint8List(0)},
      );
      await expectLater(
        repository.gitDirectoryFiles.drift(naming),
        throwsA(
          isA<GitException>().having(
            (GitException error) => error.message,
            'message',
            contains('linked/secret.txt'),
          ),
        ),
      );
      expect(
        secret.readAsStringSync(),
        'outside secret\n',
        reason: 'the file behind the link is never read into a drift report',
      );
    });

    test('capture and restore keep nested files verbatim', () async {
      final Directory nested =
          Directory(_join(gitDirectory, _join('custom', 'nested')))
            ..createSync(recursive: true);
      final File kept = File(_join(nested.path, 'kept.txt'))
        ..writeAsStringSync('nested content\n');

      final GitDirectorySnapshot capture =
          await repository.gitDirectoryFiles.capture();
      expect(capture.files.keys, contains('custom/nested/kept.txt'));

      kept.writeAsStringSync('tampered\n');
      Directory(_join(gitDirectory, 'custom')).deleteSync(recursive: true);

      final List<String> restored =
          await repository.gitDirectoryFiles.restore(capture);

      expect(restored, contains('custom/nested/kept.txt'));
      expect(
        File(_join(gitDirectory, _join('custom', _join('nested', 'kept.txt'))))
            .readAsStringSync(),
        'nested content\n',
        reason: 'a deleted nested file is written back with its directories',
      );
    });
  });
}

/// [base] joined with [relative] on the host separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

/// Creates a symbolic link at [linkPath] to [targetPath], or returns false
/// when the platform refuses it.
bool _createLink(String linkPath, String targetPath) {
  try {
    Link(linkPath).createSync(targetPath);
    return true;
  } on FileSystemException {
    return false;
  }
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
