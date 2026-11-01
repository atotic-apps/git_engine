@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'copies_support.dart';

/// A copy drawn to be read is parked wherever the recorded revision asks:
/// its `HEAD` is detached at the recorded commit, reads exactly the content
/// of it and nothing a later tip of the branch carries, and a revision that
/// exists in no repository refuses to be detached onto.
void main() {
  late CopiesSandbox sandbox;

  setUp(() async {
    sandbox = await CopiesSandbox.create();
  });

  test('the copy is detached at the recorded commit and reads its content',
      () async {
    final GitOid base = await sandbox.seedBranch('origin.git', 'main', {
      'readme.md': 'recorded\n',
    });

    final GitWorkingRepository copy = await sandbox.engine.clone(
      sandbox.path('origin.git'),
      sandbox.path('copy'),
    );

    // The branch moves on while the copy was being drawn: the commit the
    // copy will be detached at is behind the tip of the branch.
    await sandbox.seedBranch('origin.git', 'main', {
      'later.md': 'later\n',
    });

    await copy.worktree.checkoutDetached(base.value);

    expect(await copy.branches.current(), isNull);
    expect(await copy.revisions.resolveRevision('HEAD'), base);
    expect(
      await contentAt(copy, 'HEAD', 'readme.md'),
      'recorded\n',
    );
    expect(
      await contentAt(copy, 'HEAD', 'later.md'),
      isNull,
      reason: 'the recorded commit that the branch tip carries nothing of',
    );
  });

  test(
      'a recorded revision that exists in no repository refuses to be '
      'detached onto', () async {
    await sandbox.seedBranch('origin.git', 'main', {
      'readme.md': 'real\n',
    });
    final GitWorkingRepository copy = await sandbox.engine.clone(
      sandbox.path('origin.git'),
      sandbox.path('copy'),
    );
    final GitOid head = (await copy.revisions.resolveRevision('HEAD'))!;
    const String ghost = '0000000000000000000000000000000000000000';

    await expectLater(
      copy.worktree.checkoutDetached(ghost),
      throwsA(isA<GitException>()),
    );

    // Nothing was dereferenced: the copy keeps the head it had, stays clean
    // and opens again from the same place.
    expect(await copy.revisions.resolveRevision('HEAD'), head);
    expect(await copy.worktree.isClean(), isTrue);
    final GitWorkingRepository reopened =
        await sandbox.engine.openWorking(sandbox.path('copy'));
    expect(await reopened.revisions.resolveRevision('HEAD'), head);
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
