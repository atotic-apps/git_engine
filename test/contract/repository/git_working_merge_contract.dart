import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the [GitWorkingMerge] contract against [factory].
///
/// The suite only goes through the public capabilities of the repositories
/// the factory builds, so the same cases run unchanged on every backend. Each
/// case starts from a fresh working repository and grows the branches it needs
/// through the factory.
void defineGitWorkingMergeContract(BackendFactory factory) {
  group('GitWorkingMerge contract', () {
    test('fast-forwards the head without creating a commit', () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();
      await _commit(repository, factory, 'add a', <String, String>{
        'a.txt': 'a\n',
      });
      await repository.worktree.checkoutNewBranch('topic');
      final GitOid topic = await _commit(
        repository,
        factory,
        'topic work',
        <String, String>{'topic.txt': 't\n'},
      );
      final GitOid topicTip = await _commit(
        repository,
        factory,
        'more work',
        <String, String>{'more.txt': 'm\n'},
      );
      await repository.worktree.checkout('main');
      expect(topic, isNot(topicTip));
      final GitWorkingMerge merge = repository.merge;

      final GitMergeResult result = await merge.merge('topic');

      expect(result, isA<GitMergeFastForward>());
      expect((result as GitMergeFastForward).newHead, topicTip);
      expect(await _head(repository), topicTip);
      expect(await merge.isMerging(), isFalse);
      expect(await repository.worktree.isClean(), isTrue);
    });

    test('fast-forward-only folds an ancestor line without refusal', () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();
      await _commit(repository, factory, 'add a', <String, String>{
        'a.txt': 'a\n',
      });
      await repository.worktree.checkoutNewBranch('topic');
      final GitOid topicTip = await _commit(
        repository,
        factory,
        'topic work',
        <String, String>{'topic.txt': 't\n'},
      );
      await repository.worktree.checkout('main');

      final GitMergeResult result = await repository.merge.merge(
        'topic',
        mode: GitMergeMode.fastForwardOnly,
      );

      expect(result, isA<GitMergeFastForward>());
      expect((result as GitMergeFastForward).newHead, topicTip);
      expect(await _head(repository), topicTip);
    });

    test('a contained revision changes nothing', () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();
      final GitOid base = await _commit(
        repository,
        factory,
        'add a',
        <String, String>{'a.txt': 'a\n'},
      );
      final GitOid tip = await _commit(
        repository,
        factory,
        'add b',
        <String, String>{'b.txt': 'b\n'},
      );
      final GitWorkingMerge merge = repository.merge;

      expect(await merge.merge(base.value), isA<GitMergeUpToDate>());
      expect(await merge.merge(tip.value), isA<GitMergeUpToDate>());
      expect(await _head(repository), tip);
      expect(await merge.isMerging(), isFalse);
    });

    test('diverged histories are refused with a typed exception', () async {
      final _DivergedRepository diverged = await _diverged(factory);
      final GitWorkingMerge merge = diverged.repository.merge;

      await expectLater(
        merge.merge('topic', mode: GitMergeMode.fastForwardOnly),
        throwsA(isA<GitMergeNotFastForwardException>()),
      );

      expect(await _head(diverged.repository), diverged.mainTip);
      expect(await merge.isMerging(), isFalse);
      expect(await diverged.repository.worktree.isClean(), isTrue);

      // Already contained revisions stay legal under fast-forward-only.
      final GitMergeResult result = await merge.merge(
        diverged.base.value,
        mode: GitMergeMode.fastForwardOnly,
      );
      expect(result, isA<GitMergeUpToDate>());
      expect(await _head(diverged.repository), diverged.mainTip);
    });

    test('--no-ff folds both parents and leaves no merge state', () async {
      final _DivergedRepository diverged = await _diverged(factory);
      final GitWorkingMerge merge = diverged.repository.merge;

      final GitMergeResult result = await merge.merge(
        'topic',
        mode: GitMergeMode.noFastForward,
        message: 'custom merge note',
      );

      final GitMergeCommit mergeCommit = result as GitMergeCommit;
      expect(mergeCommit.commit, await _head(diverged.repository));
      final GitCommit commit =
          await diverged.repository.objects.readCommit(mergeCommit.commit);
      expect(
        commit.parents,
        <GitOid>[diverged.mainTip, diverged.topicTip],
      );
      expect(commit.message, 'custom merge note');
      expect(await merge.isMerging(), isFalse);
      expect(await diverged.repository.worktree.isClean(), isTrue);
    });

    test('without a message the default one is used', () async {
      final _DivergedRepository diverged = await _diverged(factory);

      final GitMergeResult result = await diverged.repository.merge.merge(
        'topic',
        mode: GitMergeMode.noFastForward,
      );

      final GitMergeCommit mergeCommit = result as GitMergeCommit;
      final GitCommit commit =
          await diverged.repository.objects.readCommit(mergeCommit.commit);
      expect(commit.message, "Merge branch 'topic'");
      expect(await diverged.repository.merge.isMerging(), isFalse);
    });

    test('an unknown revision is a domain refusal, not a result', () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();
      await _commit(repository, factory, 'add a', <String, String>{
        'a.txt': 'a\n',
      });

      await expectLater(
        repository.merge.merge('no-such-branch'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'no-such-branch',
          ),
        ),
      );
      expect(await repository.worktree.isClean(), isTrue);
    });

    test('leaves a --no-commit merge staged with MERGE_HEAD behind', () async {
      final _DivergedRepository diverged = await _diverged(factory);
      final GitWorkingMerge merge = diverged.repository.merge;

      final GitMergeResult result = await merge.merge(
        'topic',
        mode: GitMergeMode.noFastForward,
        noCommit: true,
      );

      expect(result, isA<GitMergeStopped>());
      expect(await _head(diverged.repository), diverged.mainTip);
      expect(await merge.isMerging(), isTrue);
      expect(
        await diverged.repository.worktree.status(),
        isNotEmpty,
      );
    });

    test('still fast-forwards when --no-commit is set', () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();
      await _commit(repository, factory, 'add a', <String, String>{
        'a.txt': 'a\n',
      });
      await repository.worktree.checkoutNewBranch('topic');
      final GitOid topicTip = await _commit(
        repository,
        factory,
        'topic work',
        <String, String>{'topic.txt': 't\n'},
      );
      await repository.worktree.checkout('main');
      final GitWorkingMerge merge = repository.merge;

      final GitMergeResult result = await merge.merge(
        'topic',
        noCommit: true,
      );

      expect(result, isA<GitMergeFastForward>());
      expect((result as GitMergeFastForward).newHead, topicTip);
      expect(await _head(repository), topicTip);
      expect(await merge.isMerging(), isFalse);
    });

    test('conflicts are a result, and abort restores the pre-merge state',
        () async {
      final _ConflictRepository conflict = await _conflict(factory);
      final GitWorkingMerge merge = conflict.repository.merge;
      final List<GitStatusEntry> before =
          await conflict.repository.worktree.status();

      final GitMergeResult result = await merge.merge('topic');

      final GitMergeConflicts conflicts = result as GitMergeConflicts;
      expect(conflicts.conflictingFiles, <String>['a.txt']);
      expect(await merge.isMerging(), isTrue);
      final List<GitStatusEntry> conflicted =
          await conflict.repository.worktree.status();
      expect(
        conflicted
            .singleWhere((GitStatusEntry entry) => entry.path == 'a.txt')
            .isConflicted,
        isTrue,
      );

      await merge.abort();

      expect(await merge.isMerging(), isFalse);
      expect(await _head(conflict.repository), conflict.mainTip);
      expect(
        await conflict.repository.worktree.status(),
        before,
      );
    });

    test('aborts raise the domain exception when no merge is in progress',
        () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();
      await _commit(repository, factory, 'add a', <String, String>{
        'a.txt': 'a\n',
      });
      final GitWorkingMerge merge = repository.merge;
      expect(await merge.isMerging(), isFalse);

      await expectLater(
        merge.abort(),
        throwsA(isA<GitNoMergeInProgressException>()),
      );
      expect(await merge.isMerging(), isFalse);
      expect(await repository.worktree.isClean(), isTrue);
    });

    test('no common ancestor is refused unless allowed', () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();
      final GitOid base = await _commit(
        repository,
        factory,
        'add a',
        <String, String>{'a.txt': 'a\n'},
      );
      final GitOid root = await _unrelatedRoot(repository);
      await repository.refs.updateRef('refs/heads/separate', root);
      final GitWorkingMerge merge = repository.merge;

      await expectLater(
        merge.merge('separate'),
        throwsA(isA<GitUnrelatedHistoriesException>()),
      );
      expect(await _head(repository), base);
      expect(await merge.isMerging(), isFalse);
      expect(await repository.worktree.isClean(), isTrue);

      final GitMergeResult result = await merge.merge(
        'separate',
        allowUnrelatedHistories: true,
      );

      final GitMergeCommit mergeCommit = result as GitMergeCommit;
      final GitCommit commit =
          await repository.objects.readCommit(mergeCommit.commit);
      expect(commit.parents, unorderedEquals(<GitOid>[base, root]));
      expect(await _head(repository), mergeCommit.commit);
      expect(await merge.isMerging(), isFalse);
    });

    test('unrelated histories are still refused under fast-forward-only',
        () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();
      final GitOid base = await _commit(
        repository,
        factory,
        'add a',
        <String, String>{'a.txt': 'a\n'},
      );
      final GitOid root = await _unrelatedRoot(repository);
      await repository.refs.updateRef('refs/heads/separate', root);
      final GitWorkingMerge merge = repository.merge;

      await expectLater(
        merge.merge(
          'separate',
          mode: GitMergeMode.fastForwardOnly,
          allowUnrelatedHistories: true,
        ),
        throwsA(isA<GitMergeNotFastForwardException>()),
      );
      expect(await _head(repository), base);
      expect(await repository.worktree.isClean(), isTrue);
    });
  });
}

/// A repository with two diverged branches and the object names of interest.
final class _DivergedRepository {
  const _DivergedRepository({
    required this.repository,
    required this.base,
    required this.topicTip,
    required this.mainTip,
  });

  final GitWorkingRepository repository;
  final GitOid base;
  final GitOid topicTip;
  final GitOid mainTip;
}

/// A repository whose two branches edit the same line of `a.txt`.
final class _ConflictRepository {
  const _ConflictRepository({required this.repository, required this.mainTip});

  final GitWorkingRepository repository;
  final GitOid mainTip;
}

/// Builds a base commit on `main`, a commit on `topic`, then a commit on
/// `main`, so the two histories have diverged.
Future<_DivergedRepository> _diverged(BackendFactory factory) async {
  final GitWorkingRepository repository =
      await factory.createWorkingRepository();
  final GitOid base =
      await _commit(repository, factory, 'add a', <String, String>{
    'a.txt': 'a\n',
  });
  await repository.worktree.checkoutNewBranch('topic');
  final GitOid topicTip = await _commit(
    repository,
    factory,
    'topic work',
    <String, String>{'topic.txt': 't\n'},
  );
  await repository.worktree.checkout('main');
  final GitOid mainTip = await _commit(
    repository,
    factory,
    'main work',
    <String, String>{'main.txt': 'm\n'},
  );
  return _DivergedRepository(
    repository: repository,
    base: base,
    topicTip: topicTip,
    mainTip: mainTip,
  );
}

/// Builds a base commit then two branches editing the same file and line.
Future<_ConflictRepository> _conflict(BackendFactory factory) async {
  final GitWorkingRepository repository =
      await factory.createWorkingRepository();
  await _commit(repository, factory, 'base line', <String, String>{
    'a.txt': 'base line\n',
  });
  await repository.worktree.checkoutNewBranch('topic');
  await _commit(repository, factory, 'topic edit', <String, String>{
    'a.txt': 'topic line\n',
  });
  await repository.worktree.checkout('main');
  final GitOid mainTip = await _commit(
    repository,
    factory,
    'main edit',
    <String, String>{'a.txt': 'main line\n'},
  );
  return _ConflictRepository(repository: repository, mainTip: mainTip);
}

/// Writes [files] and commits them as [message] through the factory.
Future<GitOid> _commit(
  GitWorkingRepository repository,
  BackendFactory factory,
  String message,
  Map<String, String> files,
) {
  return factory.commitScenario(
    repository,
    ScenarioCommit(message: message, files: files),
  );
}

/// Fabricates a root commit with no parent, unrelated to the current history.
Future<GitOid> _unrelatedRoot(GitWorkingRepository repository) async {
  final GitOid tree = await repository.objects.writeObject(
    GitObjectType.tree,
    const <int>[],
  );
  final GitIdentity identity = GitIdentity(
    name: 'Contract Merge',
    email: 'contract-merge@example.com',
  );
  return repository.objects.commitTree(
    tree,
    const <GitOid>[],
    'unrelated root',
    author: identity,
    committer: identity,
  );
}

/// Object name `HEAD` currently resolves to.
Future<GitOid> _head(GitWorkingRepository repository) async {
  return (await repository.revisions.resolveRevision('HEAD'))!;
}
