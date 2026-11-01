@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'canonical_copy_support.dart';

/// Copying an existing repository into a canonical bare store: the local
/// branches and tags come along, the remote-tracking world and the inherited
/// remote do not, the source is never touched, and the store head can be
/// re-pointed at the branch future clones will start from.
void main() {
  late CopyArea area;

  setUp(() async {
    area = await CopyArea.create();
  });

  test('a working source is copied as a store of its own history', () async {
    final GitWorkingRepository upstream = await area.seedWorking(
      'upstream',
      <String, String>{'readme.md': '# upstream\n'},
      sideBranch: 'upstream-side',
      tag: 'v1',
    );
    final GitWorkingRepository source = await area.seedClone(
      upstream.path,
      'source',
      localBranch: 'side',
    );

    final List<GitRef> refsBefore = await source.refs.listRefs();
    final String? headBefore = await source.refs.symbolicTarget('HEAD');
    final String? originBefore = await source.remotes.getUrl('origin');
    final List<GitStatusEntry> statusBefore = await source.worktree.status();

    final GitFileBareRepository store =
        await area.engine.cloneBare(source.path, area.path('store'));

    expect(store, isNot(isA<GitWorkingRepository>()));
    // A bare copy records the source as its origin; dropping that remote
    // leaves the store canonical, pointing at nobody.
    expect(await store.remotes.list(), <String>['origin']);
    expect(await store.remotes.getUrl('origin'), source.path);
    await store.remotes.remove('origin');
    expect(await store.remotes.list(), isEmpty);

    final List<String> copied =
        (await store.refs.listRefs()).map((GitRef ref) => ref.name).toList();
    expect(
      copied,
      containsAll(<String>[
        'refs/heads/main',
        'refs/heads/side',
        'refs/tags/v1',
      ]),
    );
    expect(
      copied,
      isNot(contains('refs/heads/upstream-side')),
      reason: 'a branch the source only knows through its upstream is never '
          'copied',
    );
    expect(
      copied.where((String name) => name.startsWith('refs/remotes/')),
      isEmpty,
      reason: 'no remote-tracking reference is copied',
    );
    expect(await store.refs.symbolicTarget('HEAD'), 'refs/heads/main');
    expect(
      await store.refs.resolveRef('refs/heads/main'),
      await source.refs.resolveRef('refs/heads/main'),
      reason: 'the history is the one of the source',
    );

    expect(await source.refs.listRefs(), refsBefore,
        reason: 'no reference of the source moved');
    expect(await source.refs.symbolicTarget('HEAD'), headBefore);
    expect(
      await source.worktree.status(),
      statusBefore,
      reason: 'no file was added to or removed from the source',
    );
    expect(
      await source.remotes.getUrl('origin'),
      originBefore,
      reason: 'the remote of the source is neither re-pointed nor removed',
    );
  });

  test('a bare source is copied and keeps its own remotes', () async {
    final GitWorkingRepository seed = await area.seedWorking(
      'seed',
      <String, String>{'readme.md': '# seed\n'},
      branch: 'master',
      sideBranch: 'feature',
    );
    final GitFileBareRepository bareSource =
        await area.seedBare(seed.path, 'bare-source');

    final List<GitRef> refsBefore = await bareSource.refs.listRefs();
    final String? headBefore = await bareSource.refs.symbolicTarget('HEAD');
    final GitOid? headTipBefore = await bareSource.refs.resolveRef('HEAD');
    final List<String> remotesBefore = await bareSource.remotes.list();
    final Map<String, String?> urlsBefore = <String, String?>{
      for (final String name in remotesBefore)
        name: await bareSource.remotes.getUrl(name),
    };

    final GitFileBareRepository store =
        await area.engine.cloneBare(bareSource.path, area.path('copied'));

    expect(store, isNot(isA<GitWorkingRepository>()));
    final List<String> copied =
        (await store.refs.listRefs()).map((GitRef ref) => ref.name).toList();
    expect(
      copied,
      containsAll(<String>['refs/heads/master', 'refs/heads/feature']),
    );
    expect(
      await store.refs.symbolicTarget('HEAD'),
      'refs/heads/master',
      reason: 'the head follows the head of the source, not a guessed branch',
    );
    expect(await store.refs.resolveRef('HEAD'), headTipBefore);

    // The bare source keeps everything it had, remote and bare state
    // included.
    expect(await bareSource.refs.listRefs(), refsBefore);
    expect(await bareSource.refs.symbolicTarget('HEAD'), headBefore);
    expect(await bareSource.refs.resolveRef('HEAD'), headTipBefore);
    expect(await bareSource.remotes.list(), remotesBefore);
    for (final MapEntry<String, String?> url in urlsBefore.entries) {
      expect(await bareSource.remotes.getUrl(url.key), url.value);
    }
  });

  test('a copy accepts a pre-existing empty target directory', () async {
    final GitWorkingRepository source = await area.seedWorking(
      'source',
      <String, String>{'readme.md': '# source\n'},
    );
    final String target = area.path('preset');
    await Directory(target).create(recursive: true);

    final GitFileBareRepository store =
        await area.engine.cloneBare(source.path, target);

    expect(
      Directory(target).existsSync(),
      isTrue,
      reason: 'the pre-existing directory is kept, not moved or replaced',
    );
    expect(store, isNot(isA<GitWorkingRepository>()));
    expect(await store.refs.symbolicTarget('HEAD'), 'refs/heads/main');
    expect(
      await store.refs.resolveRef('HEAD'),
      await source.refs.resolveRef('refs/heads/main'),
    );
  });

  test('the store head is re-pointed at the designated branch', () async {
    final GitWorkingRepository upstream = await area.seedWorking(
      'upstream',
      <String, String>{'readme.md': '# upstream\n'},
    );
    final GitWorkingRepository source = await area.seedClone(
      upstream.path,
      'source',
      localBranch: 'side',
    );
    // The source is left checked out on its side branch: the head the copy
    // inherits is not the one future clones must start from.
    await source.worktree.checkout('side');
    final GitFileBareRepository store =
        await area.engine.cloneBare(source.path, area.path('store'));
    expect(await store.refs.symbolicTarget('HEAD'), 'refs/heads/side');

    await store.refs.setHead('main');

    expect(await store.refs.symbolicTarget('HEAD'), 'refs/heads/main');
    expect(
      await store.refs.resolveRef('HEAD'),
      await store.refs.resolveRef('refs/heads/main'),
    );
    expect(
      File(join(store.path, 'readme.md')).existsSync(),
      isFalse,
      reason: 'a bare store is read through its objects, never through a '
          'work tree',
    );
  });
}
