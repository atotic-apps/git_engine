@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'restoring_support.dart';

/// The uncommitted work of a copy travels across a branch move: it is
/// captured as a patch of the tree against the work tree, the copy is moved
/// onto the latest tip of the branch it tracks, and applying the patch
/// there brings the work back on top of everything the move brought in.
void main() {
  test('captured work is reapplied after the copy moved onto a newer tip',
      () async {
    final RestoreSandbox sandbox = await RestoreSandbox.create();
    final GitFileBareRepository origin = await sandbox.seedBare(
      'origin.git',
      <String, String>{'readme.md': 'origin base\n'},
    );
    final GitWorkingRepository copy = await sandbox.clone(origin.path, 'copy');

    // Uncommitted work: an edit of a tracked file and a new file recorded
    // so the patch captures both.
    writeFile(copy.path, 'readme.md', 'origin base altered\n');
    writeFile(copy.path, 'arriving.md', 'fresh work\n');
    await copy.worktree.intentToAdd(<String>['arriving.md']);
    expect(await copy.worktree.isClean(), isFalse);
    final List<int> patch = await copy.patches.binaryDiffAgainstWorkTree();
    expect(patch, isNotEmpty);
    expect(
      await copy.patches.changedPathsFromTree(
        (await copy.objects.readCommit(
          (await copy.revisions.resolveRevision('HEAD'))!,
        ))
            .tree,
      ),
      containsAll(<String>['readme.md', 'arriving.md']),
    );

    // The branch moves on while the work is kept aside: the copy is moved
    // onto the newer tip, and the patch is applied on top.
    await (await AdvanceWriter.create(sandbox, origin.path)).commitOnFile(
      'aside.md',
      'moved in\n',
      'the branch moved on',
    );
    await sandbox.engine.fetch(copy, remote: 'origin');
    final GitOid movedTip = await resolve(copy, 'refs/remotes/origin/main');
    await copy.worktree.reset(
      mode: GitResetMode.hard,
      target: 'refs/remotes/origin/main',
    );
    expect(await copy.worktree.isClean(), isTrue);
    expect(await resolve(copy, 'HEAD'), movedTip);

    final GitApplyResult applied = await copy.patches.apply(patch);
    expect(applied, isA<GitApplyApplied>());

    // The work came back over the moved tip nothing of the move was lost
    // and the head is still the tip of the moved branch.
    expect(readFile(copy.path, 'readme.md'), 'origin base altered\n');
    expect(readFile(copy.path, 'arriving.md'), 'fresh work\n');
    expect(readFile(copy.path, 'aside.md'), 'moved in\n');
    expect(await resolve(copy, 'HEAD'), movedTip);
    final List<GitStatusEntry> status = await copy.worktree.status();
    final Set<String> changed =
        status.map((GitStatusEntry entry) => entry.path).toSet();
    expect(changed, <String>{'readme.md', 'arriving.md'});
    // The captured patch was not yet carried anywhere: the branch did not
    // gain the work.
    expect(
      await contentAt(origin, 'refs/heads/main', 'arriving.md'),
      isNull,
    );
  });

  test('stray content dropped and the reapplied patch still lands', () async {
    final RestoreSandbox sandbox = await RestoreSandbox.create();
    final GitFileBareRepository origin = await sandbox.seedBare(
      'origin.git',
      <String, String>{'readme.md': 'origin base\n'},
    );
    final GitWorkingRepository copy = await sandbox.clone(origin.path, 'copy');

    // A stray file stands in the way of nothing; it is dropped before the
    // copy is moved onto the branch tip.
    writeFile(copy.path, 'stray.md', 'not work\n');
    await copy.worktree.clean(directories: true);
    expect(await copy.worktree.isClean(), isTrue);
    writeFile(copy.path, 'kept.md', 'kept work\n');
    await copy.worktree.intentToAdd(<String>['kept.md']);
    final List<int> patch = await copy.patches.binaryDiffAgainstWorkTree();

    await (await AdvanceWriter.create(sandbox, origin.path)).commitOnFile(
      'aside.md',
      'moved in\n',
      'the branch moved on',
    );
    await sandbox.engine.fetch(copy, remote: 'origin');
    await copy.worktree.reset(
      mode: GitResetMode.hard,
      target: 'refs/remotes/origin/main',
    );
    // The clean call removed the stray file, never a tracked or ignored
    // piece of content.
    expect(
      File('${copy.path}${Platform.pathSeparator}stray.md').existsSync(),
      isFalse,
    );

    final GitApplyResult applied = await copy.patches.apply(patch);
    expect(applied, isA<GitApplyApplied>());
    expect(readFile(copy.path, 'kept.md'), 'kept work\n');
    expect(readFile(copy.path, 'aside.md'), 'moved in\n');
  });
}

/// Content of [path] as [repository] resolves the revision expression
/// [rev], or null when the path does not exist there.
Future<String?> contentAt(
  GitRepository repository,
  String rev,
  String path,
) async {
  final GitOid? blob = await repository.revisions.resolveRevision('$rev:$path');
  if (blob == null) {
    return null;
  }
  return String.fromCharCodes(await repository.objects.readBlob(blob));
}
