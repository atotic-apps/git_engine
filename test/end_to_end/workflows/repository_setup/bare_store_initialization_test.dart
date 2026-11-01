@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'repository_setup_support.dart';

/// Creating a bare store and seeding its first commit, the way a caller
/// stands a canonical repository up before anything lands on it.
void main() {
  late SetupArea area;

  setUp(() async {
    area = await SetupArea.create();
  });

  test('init accepts a directory that already exists and stays empty',
      () async {
    final String target = area.path('preset');
    await Directory(target).create(recursive: true);

    final GitFileBareRepository store =
        await area.engine.initBare(target, initialBranch: 'main');

    expect(Directory(target).existsSync(), isTrue);
    expect(
      sameDirectory(await store.gitDir(), target),
      isTrue,
      reason: 'the git directory of a bare store is its own directory',
    );
  });

  test('init points HEAD at the branch it was asked to create', () async {
    final GitFileBareRepository store =
        await area.engine.initBare(area.path('named'), initialBranch: 'trunk');

    expect(await store.refs.symbolicTarget('HEAD'), 'refs/heads/trunk');
    expect(await store.branches.current(), 'trunk');
    expect(
      await store.refs.resolveRef('refs/heads/trunk'),
      isNull,
      reason: 'the branch is still unborn: no commit was made',
    );
    expect(await store.refs.listRefs(prefix: 'refs/heads/'), isEmpty);
  });

  test('init without a branch follows the configured default', () async {
    final GitFileBareRepository store =
        await area.engine.initBare(area.path('default'));

    expect(
      await store.refs.symbolicTarget('HEAD'),
      'refs/heads/main',
      reason: 'the area configuration sets the default branch',
    );
  });

  test('the store is seeded with an initial empty commit on its branch',
      () async {
    final GitFileBareRepository store =
        await area.engine.initBare(area.path('store'), initialBranch: 'main');

    // The empty tree hashes to its well-known name without being stored;
    // the root commit stores it as the tree of the first commit.
    final GitOid emptyTree = await store.objects.hashObject(
      const <int>[],
      type: GitObjectType.tree,
    );
    final GitOid commit = await store.objects.commitTree(
      emptyTree,
      const <GitOid>[],
      'first commit',
      author: GitIdentity(name: setupUserName, email: setupUserEmail),
      committer: GitIdentity(name: setupUserName, email: setupUserEmail),
    );
    await store.refs.updateRef('refs/heads/main', commit);

    expect(
      await store.refs.resolveRef('HEAD'),
      commit,
      reason: 'HEAD sits on the branch the commit landed on',
    );
    expect(
      (await store.refs.listRefs(prefix: 'refs/heads/'))
          .map((GitRef ref) => ref.name),
      <String>['refs/heads/main'],
      reason: 'exactly one branch holds exactly one commit',
    );
    final GitCommit record = await store.objects.readCommit(commit);
    expect(record.parents, isEmpty);
    expect(record.tree, emptyTree);
    expect(
      (await store.objects.readTree(record.tree)).entries,
      isEmpty,
      reason: 'the first commit carries an empty tree',
    );
  });
}
