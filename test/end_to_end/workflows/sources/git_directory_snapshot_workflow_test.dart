@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'sources_support.dart';

/// Reading the git directory of a clone as raw files, the way a caller
/// captures config and hooks to fingerprint a clone.
void main() {
  late SourcesSandbox sandbox;

  setUp(() async {
    sandbox = await createSourcesSandbox();
  });

  test('the git directory of a clone is readable file by file', () async {
    final String originPath = sandbox.path('origin.git');
    await sandbox.engine.initBare(originPath, initialBranch: 'main');
    await sandbox.pushTip(
      originPath,
      branch: 'main',
      files: <String, String>{'readme.md': '# project\n'},
      message: 'seed the origin',
    );
    final GitWorkingRepository clone =
        await sandbox.engine.clone(originPath, sandbox.path('clone'));

    final String gitDir = await clone.gitDir();

    final String config = File(join(gitDir, 'config')).readAsStringSync();
    // git spells path separators doubled inside the configuration file; the
    // value itself reads back through the configuration API.
    final String url = await clone.config.get('remote.origin.url') ?? '';
    expect(config.replaceAll('\\', ''), contains(url.replaceAll('\\', '')));

    // A fresh clone carries the hook templates git installs; each one is
    // readable verbatim, path and content together.
    final List<File> hookTemplates = Directory(join(gitDir, 'hooks'))
        .listSync()
        .whereType<File>()
        .where((File file) => file.path.endsWith('.sample'))
        .toList()
      ..sort((File first, File second) => first.path.compareTo(second.path));
    expect(hookTemplates, isNotEmpty);
    for (final File hook in hookTemplates) {
      expect(hook.readAsStringSync(), isNotEmpty,
          reason: '${hook.path} must be readable');
    }
  });

  test('drift of the captured git-directory files is reported per file',
      () async {
    final String originPath = sandbox.path('origin.git');
    await sandbox.engine.initBare(originPath, initialBranch: 'main');
    await sandbox.pushTip(
      originPath,
      branch: 'main',
      files: <String, String>{'readme.md': '# project\n'},
      message: 'seed the origin',
    );
    final GitWorkingRepository clone =
        await sandbox.engine.clone(originPath, sandbox.path('clone'));
    final String gitDir = await clone.gitDir();
    final GitDirectorySnapshot capture =
        await clone.gitDirectoryFiles.capture();

    // One captured file is modified through the configuration API, one file
    // is added to the git directory, and one captured hook template is
    // deleted; the drift report names each of them in its own list.
    await clone.config.set('user.name', 'Snapshot Keeper');
    final File added = File(join(gitDir, 'captured.fingerprint'));
    added.writeAsStringSync('a fingerprint file\n');
    final File hookTemplate = Directory(join(gitDir, 'hooks'))
        .listSync()
        .whereType<File>()
        .firstWhere((File file) => file.path.endsWith('.sample'));
    final String hookContent = hookTemplate.readAsStringSync();
    hookTemplate.deleteSync();

    final GitDirectoryDrift drift = await clone.gitDirectoryFiles.drift(
      capture,
    );

    expect(
      drift.modified,
      contains('config'),
      reason: 'the captured configuration changed behind the capture',
    );
    expect(drift.added, <String>['captured.fingerprint']);
    expect(
      drift.deleted,
      contains(
        hookTemplate.path.substring(gitDir.length + 1).replaceAll('\\', '/'),
      ),
      reason: 'the deleted hook template is reported with its '
          'git-directory relative path',
    );
    expect(hookContent, isNotEmpty,
        reason: 'the deleted file was part of the capture');
  });

  test('captured git-directory files are restored verbatim', () async {
    final String originPath = sandbox.path('origin.git');
    await sandbox.engine.initBare(originPath, initialBranch: 'main');
    await sandbox.pushTip(
      originPath,
      branch: 'main',
      files: <String, String>{'readme.md': '# project\n'},
      message: 'seed the origin',
    );
    final GitWorkingRepository clone =
        await sandbox.engine.clone(originPath, sandbox.path('clone'));
    final String gitDir = await clone.gitDir();
    final GitDirectorySnapshot capture =
        await clone.gitDirectoryFiles.capture();
    final String hookSampleName = Directory(join(gitDir, 'hooks'))
        .listSync()
        .whereType<File>()
        .firstWhere((File file) => file.path.endsWith('.sample'))
        .path
        .substring(gitDir.length + 1)
        .replaceAll('\\', '/');

    // The git directory drifts in every way a capture can miss: the
    // configuration is rewritten, a hook template is deleted, and a new file
    // appears.
    await clone.config.set('user.name', 'Snapshot Keeper');
    File(join(gitDir, hookSampleName)).deleteSync();
    File(join(gitDir, 'arrived.later')).writeAsStringSync('not captured\n');

    final List<String> restored = await clone.gitDirectoryFiles.restore(
      capture,
    );

    expect(restored, containsAll(<String>['config', hookSampleName]));
    expect(
      File(join(gitDir, 'config')).readAsStringSync(),
      String.fromCharCodes(capture.files['config']!),
      reason: 'the captured configuration is written back verbatim',
    );
    expect(
      File(join(gitDir, hookSampleName)).readAsStringSync(),
      String.fromCharCodes(capture.files[hookSampleName]!),
      reason: 'the deleted hook template is written back verbatim',
    );
    expect(
      File(join(gitDir, 'arrived.later')).existsSync(),
      isTrue,
      reason: 'restoring writes the capture back; it removes nothing',
    );
  });
}
