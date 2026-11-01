import 'dart:convert';
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the [GitDirectoryFiles] contract tests for [factory].
///
/// The suite captures the git directory of a working repository, drifts it
/// through configuration writes and git-directory files created and removed,
/// and restores the capture back into place.
void defineGitDirectoryFilesContract(BackendFactory factory) {
  group('GitDirectoryFiles', () {
    late GitWorkingRepository repository;
    late String gitDirectoryPath;

    setUp(() async {
      repository = await factory.createWorkingRepository();
      gitDirectoryPath = await repository.gitDir();
    });

    /// The bytes [relative] holds in the git directory now, or null when it
    /// is gone.
    List<int>? currentBytes(String relative) {
      final File file = _join(gitDirectoryPath, relative);
      return file.existsSync() ? file.readAsBytesSync() : null;
    }

    test('captures the files of the git directory by relative path', () async {
      final GitDirectorySnapshot snapshot =
          await repository.gitDirectoryFiles.capture();

      expect(snapshot.files, isNotEmpty);
      expect(snapshot.files.keys, containsAll(<String>['HEAD', 'config']));
      for (final String path in snapshot.files.keys) {
        expect(
          path,
          isNot(contains('\\')),
          reason: '$path must be spelled with forward slashes',
        );
        expect(
          path,
          isNot(startsWith('/')),
          reason: '$path must be relative to the git directory',
        );
      }
    });

    test('reports no drift for a git directory left untouched', () async {
      final GitDirectorySnapshot snapshot =
          await repository.gitDirectoryFiles.capture();

      final GitDirectoryDrift drift =
          await repository.gitDirectoryFiles.drift(snapshot);

      expect(drift.isEmpty, isTrue);
      expect(drift.modified, isEmpty);
      expect(drift.added, isEmpty);
      expect(drift.deleted, isEmpty);
    });

    test('reports modified, added and deleted files one by one', () async {
      final GitDirectorySnapshot before =
          await repository.gitDirectoryFiles.capture();
      final String capturedName = before.files.keys
          .firstWhere((String path) => path == 'description', orElse: () {
        return before.files.keys.first;
      });
      await repository.config.set('user.name', 'Drift Keeper');
      final File added = _join(gitDirectoryPath, 'contract-capture.file');
      added.writeAsStringSync('created after the capture\n');
      _join(gitDirectoryPath, capturedName).deleteSync();

      GitDirectoryDrift drift =
          await repository.gitDirectoryFiles.drift(before);

      expect(drift.modified, <String>['config']);
      expect(drift.added, <String>['contract-capture.file']);
      expect(drift.deleted, <String>[capturedName]);

      added.deleteSync();
      drift = await repository.gitDirectoryFiles.drift(before);

      expect(drift.modified, <String>['config']);
      expect(drift.added, isEmpty,
          reason: 'a file created after the capture and deleted again '
              'carries no drift');
      expect(drift.deleted, <String>[capturedName]);
    });

    test('restores captured files verbatim and reports each of them', () async {
      final String? nameBefore = await repository.config.get('user.name');
      final GitDirectorySnapshot snapshot =
          await repository.gitDirectoryFiles.capture();
      final List<int> configBefore = snapshot.files['config']!;
      final List<int> headBefore = snapshot.files['HEAD']!;
      final File kept = _join(gitDirectoryPath, 'contract-kept.file');
      kept.writeAsStringSync('created after the capture\n');
      await repository.config.set('user.name', 'Restore Keeper');
      _join(gitDirectoryPath, 'HEAD').writeAsStringSync('drifted\n');

      final List<String> restored =
          await repository.gitDirectoryFiles.restore(snapshot);

      expect(restored, containsAll(<String>['config', 'HEAD']));
      expect(
        await repository.config.get('user.name'),
        nameBefore,
        reason: 'the captured configuration is written back',
      );
      expect(
        currentBytes('config'),
        configBefore,
        reason: 'the capture is restored verbatim',
      );
      expect(currentBytes('HEAD'), headBefore);

      // Restoring repairs what was deleted; it never removes what it does
      // not hold.
      final File repaired = _join(gitDirectoryPath, 'contract-repaired.file');
      repaired.writeAsStringSync('captured\n');
      await repository.gitDirectoryFiles.restore(snapshot);
      expect(
        currentBytes('contract-repaired.file'),
        utf8.encode('captured\n'),
        reason: 'a deleted captured file is written back',
      );
      expect(
        kept.existsSync(),
        isTrue,
        reason: 'a file the capture does not hold is kept',
      );
    });
  });
}

/// A file of the git directory at [relative].
File _join(String gitDirectoryPath, String relative) {
  final String separator = Platform.pathSeparator;
  final String joined = gitDirectoryPath.endsWith(separator)
      ? '$gitDirectoryPath$relative'
      : '$gitDirectoryPath$separator$relative';
  return File(joined);
}
