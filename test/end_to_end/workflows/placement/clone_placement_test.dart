@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import '../../../backends/process/support/process_backend_types.dart'
    show GitCommandException;
import 'package:test/test.dart';

import '../../../support/directory_identity.dart';
import 'placement_support.dart';

/// Where a clone may be placed: a folder that exists and is empty is used
/// as it stands, a folder that already holds anything is refused with its
/// content untouched, and a refused placement leaves the origin and every
/// other folder alone.
void main() {
  test('a clone settles into a folder that exists and is empty', () async {
    final PlacementSandbox sandbox = await PlacementSandbox.create();
    final String barePath = await sandbox.seedBare(
      'origin.git',
      <String, String>{'readme.md': '# project\n'},
    );
    final String target = sandbox.path('settled');
    await Directory(target).create(recursive: true);

    final GitWorkingRepository clone = await sandbox.engine.clone(
      barePath,
      target,
    );

    // The clone lives in the very folder that was given, at the tip of the
    // branch the origin carries, with a clean work tree.
    expect(await clone.branches.current(), 'main');
    expect(
      await clone.revisions.resolveRevision('HEAD'),
      await resolveTip(sandbox, barePath),
    );
    expect(readFile(target, 'readme.md'), '# project\n');
    expect(
      Directory(sandboxPath(target, '.git')).existsSync(),
      isTrue,
      reason: 'the git directory is inside the folder the clone settled in',
    );
    expect(await clone.worktree.isClean(), isTrue);
    // Git may resolve symbolic links in the top-level path.
    expect(
      sameDirectory(await clone.toplevel(), target),
      isTrue,
    );
  });

  test('a clone refuses a folder that already holds anything', () async {
    final PlacementSandbox sandbox = await PlacementSandbox.create();
    final String barePath = await sandbox.seedBare(
      'origin.git',
      <String, String>{'readme.md': '# project\n'},
    );
    final String target = sandbox.path('occupied');
    await Directory(target).create(recursive: true);
    final File marker = File(sandboxPath(target, 'notes.txt'));
    await marker.writeAsString('kept\n');

    await expectLater(
      sandbox.engine.clone(barePath, target),
      throwsA(isA<GitCommandException>()),
    );

    // The refusal touched nothing: the content of the folder is intact, no
    // git directory appeared, and the origin carries no new branch.
    expect(await marker.readAsString(), 'kept\n');
    expect(Directory(sandboxPath(target, '.git')).existsSync(), isFalse);
    final GitFileBareRepository origin =
        await sandbox.engine.openBare(barePath);
    final List<GitRef> branches = await origin.refs.listRefs(
      prefix: 'refs/heads/',
    );
    expect(branches, hasLength(1));
    expect(branches.single.name, 'refs/heads/main');
  });
}

/// The commit `main` of the bare repository at [barePath] names.
Future<GitOid> resolveTip(PlacementSandbox sandbox, String barePath) async {
  final GitFileBareRepository origin = await sandbox.engine.openBare(barePath);
  final GitOid? tip = await origin.revisions.resolveRevision(
    'refs/heads/main',
  );
  if (tip == null) {
    fail('the seeded bare repository holds no tip on main');
  }
  return tip;
}
