@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'integrity_support.dart';

/// A working copy whose git directory lost its head file: opening it is
/// refused as a directory git no longer recognizes, the refusal damages
/// nothing, and writing the head file back restores a copy that reads the
/// very state it was damaged in.
void main() {
  test('a working copy that lost its head file is refused on open', () async {
    final IntegritySandbox sandbox = await IntegritySandbox.create();
    final GitWorkingRepository copy = await sandbox.seedCopy(
      'origin.git',
      'copy',
      <String, String>{'readme.md': 'recorded\n'},
    );
    final String headPath = sandboxPath(sandboxPath(copy.path, '.git'), 'HEAD');
    expect(File(headPath).existsSync(), isTrue);
    final GitOid tip = (await copy.revisions.resolveRevision('HEAD'))!;

    await File(headPath).delete();

    await expectLater(
      sandbox.engine.open(copy.path),
      throwsA(isA<GitNotARepositoryException>()),
    );
    // The refusal is a detection, never a cleanup: the work-tree files and
    // the damaged git directory both stay in place.
    expect(readFile(copy.path, 'readme.md'), 'recorded\n');
    expect(Directory(sandboxPath(copy.path, '.git')).existsSync(), isTrue);
    // The same refusal every time: a damaged copy never heals by being
    // read, whichever way it is asked for.
    await expectLater(
      sandbox.engine.openWorking(copy.path),
      throwsA(isA<GitNotARepositoryException>()),
    );

    // Writing the head file back makes the copy readable again, at the very
    // state it was damaged in.
    await File(headPath).writeAsString('ref: refs/heads/main\n');
    final GitWorkingRepository restored =
        await sandbox.engine.openWorking(copy.path);
    expect(await restored.revisions.resolveRevision('HEAD'), tip);
    expect(await restored.branches.current(), 'main');
    expect(await restored.worktree.isClean(), isTrue);
    expect(readFile(restored.path, 'readme.md'), 'recorded\n');
  });
}
