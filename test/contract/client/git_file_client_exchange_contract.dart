import 'dart:convert';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the tag and upstream contract of [GitFileClient] exchanges.
///
/// The fetch half checks every `GitTagFetch`: the default follows the tags
/// that designate retrieved commits, `all` brings every tag of the remote,
/// `none` brings no tag, and a tag sitting on a commit the fetch does not
/// retrieve follows that rule. The push half checks `tags`, `setUpstream`
/// read back through the branches and `@{upstream}`, the `ArgumentError`
/// refusals of `setUpstream`, and the typed refusal of a tag the remote
/// already holds with another value.
void defineGitFileClientExchangeContract(BackendFactory factory) {
  group('GitFileClient.fetch tags', () {
    late EngineSandbox sandbox;
    late GitFileClient client;
    late GitFileBareRepository origin;

    setUp(() async {
      sandbox = await factory.createEngineSandbox();
      client = sandbox.client;
      final ScenarioRepository scenario =
          await factory.createBareRepositoryFromScenario(
        <ScenarioCommit>[
          const ScenarioCommit(
            message: 'Add the first file',
            files: <String, String>{'first.txt': 'first\n'},
          ),
          const ScenarioCommit(
            message: 'Add the second file',
            files: <String, String>{'second.txt': 'second\n'},
          ),
        ],
      );
      origin = scenario.repository as GitFileBareRepository;
      final GitIdentity identity = GitIdentity(
        name: 'Contract',
        email: 'contract@example.com',
      );
      // A commit of the `side` branch alone, so a tag can sit on a commit
      // no fetch of `main` retrieves.
      final GitCommit first =
          await origin.objects.readCommit(scenario.commits.first);
      final GitOid sideCommit = await origin.objects.commitTree(
        first.tree,
        <GitOid>[scenario.commits.first],
        'Side work\n',
        author: identity,
        committer: identity,
      );
      await origin.refs.updateRef('refs/heads/side', sideCommit);
      await _createAnnotatedTag(origin, 'annotated', scenario.commits.last);
      await origin.refs.updateRef('refs/tags/light', scenario.commits.last);
      await origin.refs.updateRef('refs/tags/elsewhere', sideCommit);
    });

    /// A fresh repository with a work tree whose `origin` is [origin], so a
    /// fetch starts from a repository holding no tag at all.
    Future<GitWorkingRepository> target() async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();
      await repository.remotes.add('origin', origin.path);
      return repository;
    }

    /// The tag names [repository] holds.
    Future<List<String>> tagNames(GitRepository repository) async {
      final List<GitRef> tags =
          await repository.refs.listRefs(prefix: 'refs/tags/');
      return tags.map((GitRef ref) => ref.name).toList();
    }

    test('the default brings the tags of the retrieved commits', () async {
      final GitWorkingRepository repository = await target();

      await client.fetch(
        repository,
        remote: 'origin',
        refspecs: <String>['refs/heads/main'],
      );

      expect(
        await tagNames(repository),
        containsAllInOrder(<String>['refs/tags/annotated', 'refs/tags/light']),
      );
      expect(
        await tagNames(repository),
        isNot(contains('refs/tags/elsewhere')),
        reason: 'a tag on a commit the fetch does not retrieve is left out',
      );
    });

    test('all brings every tag of the remote', () async {
      final GitWorkingRepository repository = await target();

      await client.fetch(
        repository,
        remote: 'origin',
        refspecs: <String>['refs/heads/main'],
        tags: GitTagFetch.all,
      );

      expect(
        await tagNames(repository),
        containsAll(<String>[
          'refs/tags/annotated',
          'refs/tags/light',
          'refs/tags/elsewhere',
        ]),
      );
    });

    test('none brings no tag at all', () async {
      final GitWorkingRepository repository = await target();

      await client.fetch(
        repository,
        remote: 'origin',
        refspecs: <String>['refs/heads/main'],
        tags: GitTagFetch.none,
      );

      expect(await tagNames(repository), isEmpty);
    });

    test('an annotated tag arrives as a tag object, not a commit', () async {
      final GitWorkingRepository repository = await target();

      await client.fetch(repository, remote: 'origin');

      final GitOid? tag =
          await repository.revisions.resolveRevision('refs/tags/annotated');
      expect(tag, isNotNull);
      expect(
        await repository.objects.objectType(tag!),
        GitObjectType.tag,
      );
    });
  });

  group('GitFileClient.push tags and upstream', () {
    late EngineSandbox sandbox;
    late GitFileClient client;
    late GitFileBareRepository origin;

    setUp(() async {
      sandbox = await factory.createEngineSandbox();
      client = sandbox.client;
      final ScenarioRepository scenario =
          await factory.createBareRepositoryFromScenario(
        <ScenarioCommit>[
          const ScenarioCommit(
            message: 'Add the base file',
            files: <String, String>{'base.txt': 'base\n'},
          ),
        ],
      );
      origin = scenario.repository as GitFileBareRepository;
    });

    /// A clone of [origin] with an identity, ready to commit.
    Future<GitWorkingRepository> cloneWork(String name) async {
      final GitWorkingRepository work =
          await client.clone(origin.path, sandbox.newPath(name));
      await _setIdentity(work);
      return work;
    }

    test('tags pushes every local tag', () async {
      final GitWorkingRepository pusher = await cloneWork('tags-pusher');
      final GitOid commit = await factory.commitScenario(
        pusher,
        const ScenarioCommit(
          message: 'Tagged work',
          files: <String, String>{'tagged.txt': 'tagged\n'},
        ),
      );
      await pusher.refs.updateRef('refs/tags/plain', commit);
      await _createAnnotatedTag(pusher, 'release', commit);

      await client.push(
        pusher,
        remote: 'origin',
        refspecs: <String>['main'],
        tags: true,
      );

      final List<GitRef> remoteTags =
          await origin.refs.listRefs(prefix: 'refs/tags/');
      expect(
        remoteTags.map((GitRef ref) => ref.name),
        containsAll(<String>['refs/tags/plain', 'refs/tags/release']),
      );
    });

    test('a push without tags carries no tag', () async {
      final GitWorkingRepository pusher = await cloneWork('plain-pusher');
      final GitOid commit = await factory.commitScenario(
        pusher,
        const ScenarioCommit(
          message: 'Untagged work',
          files: <String, String>{'plain.txt': 'plain\n'},
        ),
      );
      await pusher.refs.updateRef('refs/tags/plain', commit);

      await client.push(pusher, remote: 'origin', refspecs: <String>['main']);

      expect(await origin.refs.listRefs(prefix: 'refs/tags/'), isEmpty);
    });

    test('setUpstream makes the pushed branch follow its remote branch',
        () async {
      final GitWorkingRepository pusher = await cloneWork('upstream-pusher');
      await pusher.worktree.checkoutNewBranch('topic');
      await factory.commitScenario(
        pusher,
        const ScenarioCommit(
          message: 'Topic work',
          files: <String, String>{'topic.txt': 'topic\n'},
        ),
      );

      await client.push(
        pusher,
        remote: 'origin',
        refspecs: <String>['topic'],
        setUpstream: true,
      );

      expect(
        await pusher.revisions.symbolicFullName('topic@{upstream}'),
        'refs/remotes/origin/topic',
      );
      expect(
        await pusher.config.get('branch.topic.remote'),
        'origin',
      );
      expect(
        await pusher.config.get('branch.topic.merge'),
        'refs/heads/topic',
      );
    });

    test('setUpstream without refspecs follows the checked out branch',
        () async {
      final GitFileBareRepository empty = await factory.createBareRepository();
      final GitWorkingRepository pusher =
          await factory.createWorkingRepository();
      await _setIdentity(pusher);
      await pusher.remotes.add('origin', empty.path);
      final GitOid commit = await factory.commitScenario(
        pusher,
        const ScenarioCommit(
          message: 'First work',
          files: <String, String>{'first.txt': 'first\n'},
        ),
      );

      await client.push(pusher, remote: 'origin', setUpstream: true);

      expect(await empty.revisions.resolveRevision('main'), commit);
      expect(
        await pusher.revisions.symbolicFullName('@{upstream}'),
        'refs/remotes/origin/main',
      );
    });

    test('setUpstream refuses a detached HEAD without refspecs', () async {
      final GitWorkingRepository pusher = await cloneWork('detached-pusher');
      final GitOid head = (await pusher.revisions.resolveRevision('HEAD'))!;
      await pusher.worktree.checkoutDetached(head.value);

      await expectLater(
        client.push(pusher, remote: 'origin', setUpstream: true),
        throwsArgumentError,
      );
    });

    test('setUpstream refuses refspecs that name no single local branch',
        () async {
      final GitWorkingRepository pusher = await cloneWork('refused-pusher');
      await pusher.refs.updateRef(
        'refs/tags/v1',
        (await pusher.revisions.resolveRevision('HEAD'))!,
      );

      for (final List<String> refspecs in <List<String>>[
        const <String>['main', 'topic'],
        const <String>['refs/tags/v1'],
        const <String>['no-such-branch'],
      ]) {
        await expectLater(
          client.push(
            pusher,
            remote: 'origin',
            refspecs: refspecs,
            setUpstream: true,
          ),
          throwsArgumentError,
          reason: 'refspecs $refspecs name no single local branch',
        );
      }
      expect(
        await origin.revisions.resolveRevision('refs/tags/v1'),
        isNull,
        reason: 'the refusal happens before git runs',
      );
    });

    test('a tag the remote holds with another value is typed', () async {
      final GitOid base = (await origin.revisions.resolveRevision('main'))!;
      await origin.refs.updateRef('refs/tags/v1', base);
      final GitWorkingRepository pusher = await cloneWork('conflict-pusher');
      final GitOid commit = await factory.commitScenario(
        pusher,
        const ScenarioCommit(
          message: 'New work',
          files: <String, String>{'new.txt': 'new\n'},
        ),
      );
      await pusher.refs.updateRef('refs/tags/v1', commit);

      await expectLater(
        client.push(
          pusher,
          remote: 'origin',
          refspecs: <String>['main'],
          tags: true,
        ),
        throwsA(isA<GitPushRejectedException>()),
      );
      expect(
        await origin.revisions.resolveRevision('refs/tags/v1'),
        base,
        reason: 'the remote tag keeps the value it already held',
      );
    });
  });
}

/// Sets the local identity commits made through [repository] use.
Future<void> _setIdentity(GitRepository repository) async {
  await repository.config.set('user.name', 'Client Contract');
  await repository.config.set('user.email', 'client-contract@example.com');
}

/// Creates the annotated tag [name] on [target] in [repository] and points
/// `refs/tags/<name>` at it.
Future<GitOid> _createAnnotatedTag(
  GitRepository repository,
  String name,
  GitOid target,
) async {
  final List<int> content = utf8.encode(
    'object ${target.value}\n'
    'type commit\n'
    'tag $name\n'
    'tagger Contract <contract@example.com> 1717000000 +0000\n'
    '\n'
    'Annotated tag $name\n',
  );
  final GitOid tag =
      await repository.objects.writeObject(GitObjectType.tag, content);
  await repository.refs.updateRef('refs/tags/$name', tag);
  return tag;
}
