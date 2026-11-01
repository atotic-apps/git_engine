@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'differences_support.dart';

/// What a branch carried since a recorded base of the repository, read from
/// the tree of the branch tip against the tree of the base — and the same
/// reading of the branch the base sits on, which reports nothing while the
/// base is still its tip and the carrying content once it moved ahead.
void main() {
  test('a branch reads what it carried since the recorded base', () async {
    final DifferenceSandbox sandbox = await DifferenceSandbox.create();
    final GitOid base =
        await sandbox.seedBranch('origin.git', 'main', <String, String>{
      'readme.md': 'base\n',
    });
    final GitOid arrived =
        await sandbox.seedBranch('origin.git', 'side', <String, String>{
      'report.txt': 'carried by the branch\n',
    });

    final GitFileBareRepository origin =
        await sandbox.engine.openBare(sandbox.path('origin.git'));
    final GitOid baseTree = (await origin.objects.readCommit(base)).tree;
    final GitOid arrivedTree = (await origin.objects.readCommit(arrived)).tree;

    final List<String> carried =
        await origin.patches.changedPaths(baseTree, arrivedTree);
    expect(carried, <String>['report.txt']);
    final String text = await origin.patches.textDiff(baseTree, arrivedTree);
    expect(text, contains('diff --git '));
    expect(text, contains('carried by the branch'));
    // The carry is readable byte for byte too, ready for a reapplication.
    expect(
      await origin.patches.binaryDiff(baseTree, arrivedTree),
      isNotEmpty,
    );
  });

  test('a branch that has not moved since the base carries nothing', () async {
    final DifferenceSandbox sandbox = await DifferenceSandbox.create();
    final GitOid base =
        await sandbox.seedBranch('origin.git', 'main', <String, String>{
      'readme.md': 'base\n',
    });

    final GitFileBareRepository origin =
        await sandbox.engine.openBare(sandbox.path('origin.git'));
    final GitOid baseTree = (await origin.objects.readCommit(base)).tree;

    // The base still is the tip of the branch it came from: the reading has
    // nothing to list, no text and no binary carry.
    expect(await origin.patches.changedPaths(baseTree, baseTree), isEmpty);
    expect(await origin.patches.textDiff(baseTree, baseTree), isEmpty);
  });

  test(
      'a base the branch left behind reads the content the branch carried '
      'over', () async {
    final DifferenceSandbox sandbox = await DifferenceSandbox.create();
    final GitOid base =
        await sandbox.seedBranch('origin.git', 'main', <String, String>{
      'readme.md': 'base\n',
    });
    final GitOid moved =
        await sandbox.seedBranch('origin.git', 'main', <String, String>{
      'added.md': 'carried over the base\n',
    });

    final GitFileBareRepository origin =
        await sandbox.engine.openBare(sandbox.path('origin.git'));
    final GitOid baseTree = (await origin.objects.readCommit(base)).tree;
    final GitOid movedTree = (await origin.objects.readCommit(moved)).tree;

    expect(
      await origin.patches.changedPaths(baseTree, movedTree),
      <String>['added.md'],
    );
    expect(
      await origin.patches.textDiff(baseTree, movedTree),
      contains('+carried over the base'),
    );
    expect(await resolve(origin, 'refs/heads/main'), moved);
  });
}
