@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'copies_support.dart';

/// Where a copy drawn for inspection sits: on the branch it was told to
/// carry, tracking the matching branch of the bare it was drawn from, and
/// with an origin of its own — a copy of another repository keeps another
/// origin.
void main() {
  test(
      'a copy drawn on a named branch carries that branch and the origin '
      'it was drawn from', () async {
    final CopiesSandbox sandbox = await CopiesSandbox.create();
    final GitOid tip = await sandbox.seedBranch('origin.git', 'side', {
      'readme.md': '# project\n',
    });

    final GitWorkingRepository copy = await sandbox.engine.clone(
      sandbox.path('origin.git'),
      sandbox.path('copy'),
      branch: 'side',
    );

    expect(await copy.branches.current(), 'side');
    expect(await copy.revisions.resolveRevision('HEAD'), tip);
    expect(
      await contentAt(copy, 'HEAD', 'readme.md'),
      '# project\n',
    );
    // The named branch does not guess its upstream: it is spelled on the
    // matching remote-tracking branch right away.
    expect(
      await copy.revisions.symbolicFullName(
        '@{upstream}',
        abbreviated: true,
      ),
      'origin/side',
    );
    // The origin is the bare the copy was drawn from.
    expect(await copy.remotes.list(), <String>['origin']);
    expect(await copy.remotes.getUrl('origin'), sandbox.path('origin.git'));
    expect(
      await copy.refs.resolveRef('refs/remotes/origin/side'),
      tip,
    );
  });

  test(
      'a copy of another repository keeps its own origin, never a shared '
      'one', () async {
    final CopiesSandbox sandbox = await CopiesSandbox.create();
    await sandbox.seedBranch('first.git', 'main', {
      'first.md': 'first\n',
    });
    await sandbox.seedBranch('second.git', 'main', {
      'second.md': 'second\n',
    });

    final GitWorkingRepository first = await sandbox.engine.clone(
      sandbox.path('first.git'),
      sandbox.path('first-copy'),
    );
    final GitWorkingRepository second = await sandbox.engine.clone(
      sandbox.path('second.git'),
      sandbox.path('second-copy'),
    );

    expect(await first.remotes.getUrl('origin'), sandbox.path('first.git'));
    expect(await second.remotes.getUrl('origin'), sandbox.path('second.git'));
    expect(
      await first.remotes.getUrl('origin'),
      isNot(await second.remotes.getUrl('origin')),
    );
    // The origins are not conflated: the second copy reads the second
    // repository's content through its tracking branch.
    expect(
      await contentAt(second, 'refs/remotes/origin/main', 'second.md'),
      'second\n',
    );
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
