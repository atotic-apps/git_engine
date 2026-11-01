import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the pull contract of [GitFileClient].
///
/// Pull is the composition of [GitFileClient.fetch] and the working merge:
/// a fetch of the branch concerned, then the merge of the branch it obtained
/// into the current branch. The suite checks every outcome of that merge â€”
/// up to date, fast-forward, merge commit, conflict â€” and its refusals: a
/// fast-forward-only pull that cannot fast-forward, local changes the merge
/// would overwrite, and a pull with no branch to follow. It closes with the
/// explicit forms: a named remote and branch, a remote alone, and a branch
/// without a remote.
void defineGitFileClientPullContract(BackendFactory factory) {
  group('GitFileClient.pull', () {
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

    /// Advances [worker] with one commit and pushes it to `origin`'s main.
    Future<GitOid> pushToOrigin(
      GitWorkingRepository worker,
      String path,
      String content,
      String message,
    ) async {
      final GitOid pushed = await factory.commitScenario(
        worker,
        ScenarioCommit(
          message: message,
          files: <String, String>{path: content},
        ),
      );
      await client.push(worker, remote: 'origin', refspecs: <String>['main']);
      return pushed;
    }

    test('a branch whose upstream is already merged is up to date', () async {
      final GitWorkingRepository work = await cloneWork('up-to-date');
      final GitOid before = (await work.revisions.resolveRevision('HEAD'))!;

      final GitMergeResult result = await client.pull(work);

      expect(result, isA<GitMergeUpToDate>());
      expect(await work.revisions.resolveRevision('HEAD'), before);
      expect(await work.worktree.isClean(), isTrue);
    });

    test('a pull behind its upstream fast-forwards', () async {
      final GitWorkingRepository updater = await cloneWork('ff-updater');
      final GitWorkingRepository work = await cloneWork('ff-work');
      final GitOid pushed =
          await pushToOrigin(updater, 'later.txt', 'later\n', 'Later work');

      final GitMergeResult result = await client.pull(work);

      expect(
          result,
          isA<GitMergeFastForward>().having(
            (GitMergeFastForward forward) => forward.newHead,
            'newHead',
            pushed,
          ));
      expect(await work.revisions.resolveRevision('HEAD'), pushed);
      expect(_fileIn(work, 'later.txt'), isTrue);
    });

    test('diverged histories fold into a merge commit', () async {
      final GitWorkingRepository updater = await cloneWork('div-updater');
      final GitWorkingRepository work = await cloneWork('div-work');
      final GitOid remoteTip =
          await pushToOrigin(updater, 'theirs.txt', 'theirs\n', 'Their work');
      final GitOid localTip = await factory.commitScenario(
        work,
        const ScenarioCommit(
          message: 'Local work',
          files: <String, String>{'mine.txt': 'mine\n'},
        ),
      );

      final GitMergeResult result = await client.pull(work);

      expect(result, isA<GitMergeCommit>());
      final GitOid mergeCommit = (result as GitMergeCommit).commit;
      expect(await work.history.isAncestor(localTip, mergeCommit), isTrue);
      expect(await work.history.isAncestor(remoteTip, mergeCommit), isTrue);
      expect(_fileIn(work, 'theirs.txt'), isTrue);
      expect(_fileIn(work, 'mine.txt'), isTrue);
      expect(await work.worktree.isClean(), isTrue);
    });

    test('a conflicted merge is a result, not an exception', () async {
      final GitWorkingRepository updater = await cloneWork('conf-updater');
      final GitWorkingRepository work = await cloneWork('conf-work');
      await pushToOrigin(
          updater, 'shared.txt', 'theirs\n', 'Change the shared file');
      await factory.commitScenario(
        work,
        const ScenarioCommit(
          message: 'Change the shared file locally',
          files: <String, String>{'shared.txt': 'mine\n'},
        ),
      );

      final GitMergeResult result = await client.pull(work);

      expect(
          result,
          isA<GitMergeConflicts>().having(
            (GitMergeConflicts conflicts) => conflicts.conflictingFiles,
            'conflictingFiles',
            <String>['shared.txt'],
          ));
      expect(await work.merge.isMerging(), isTrue);
      await work.merge.abort();
      expect(await work.merge.isMerging(), isFalse);
    });

    test('fastForwardOnly refuses a pull it cannot fast-forward', () async {
      final GitWorkingRepository updater = await cloneWork('ffo-updater');
      final GitWorkingRepository work = await cloneWork('ffo-work');
      await pushToOrigin(updater, 'theirs.txt', 'theirs\n', 'Their work');
      await factory.commitScenario(
        work,
        const ScenarioCommit(
          message: 'Local work',
          files: <String, String>{'mine.txt': 'mine\n'},
        ),
      );

      await expectLater(
        client.pull(work, mode: GitMergeMode.fastForwardOnly),
        throwsA(isA<GitMergeNotFastForwardException>()),
      );
      expect(await work.merge.isMerging(), isFalse);
    });

    test('local changes the merge would overwrite are typed', () async {
      final GitWorkingRepository updater = await cloneWork('local-updater');
      final GitWorkingRepository work = await cloneWork('local-work');
      await pushToOrigin(
          updater, 'base.txt', 'changed\n', 'Change the base file');
      await File(_join(work.path, 'base.txt')).writeAsString('local edit\n');

      await expectLater(
        client.pull(work),
        throwsA(isA<GitLocalChangesOverwrittenException>()),
      );
    });

    test('a repository without an upstream is typed', () async {
      final GitWorkingRepository fresh =
          await factory.createWorkingRepository();

      await expectLater(
        client.pull(fresh),
        throwsA(isA<GitNoUpstreamException>()),
      );
    });

    test('a detached HEAD is typed', () async {
      final GitWorkingRepository work = await cloneWork('detached');
      final GitOid head = (await work.revisions.resolveRevision('HEAD'))!;
      await work.worktree.checkoutDetached(head.value);
      expect(await work.branches.current(), isNull);

      await expectLater(
        client.pull(work),
        throwsA(isA<GitNoUpstreamException>()),
      );
    });

    test('an explicit remote and branch integrate that branch', () async {
      final GitWorkingRepository author = await cloneWork('branch-author');
      await author.worktree.checkoutNewBranch('feature');
      final GitOid featureTip = await factory.commitScenario(
        author,
        const ScenarioCommit(
          message: 'Feature work',
          files: <String, String>{'feature.txt': 'feature\n'},
        ),
      );
      await client.push(
        author,
        remote: 'origin',
        refspecs: <String>['feature'],
      );
      final GitWorkingRepository work = await cloneWork('branch-work');

      final GitMergeResult result =
          await client.pull(work, remote: 'origin', branch: 'feature');

      expect(
          result,
          isA<GitMergeFastForward>().having(
            (GitMergeFastForward forward) => forward.newHead,
            'newHead',
            featureTip,
          ));
      expect(await work.branches.current(), 'main');
      expect(_fileIn(work, 'feature.txt'), isTrue);
    });

    test('a remote alone fetches the current branch of that remote', () async {
      final GitWorkingRepository updater = await cloneWork('alone-updater');
      final GitWorkingRepository work = await cloneWork('alone-work');
      final GitOid pushed =
          await pushToOrigin(updater, 'later.txt', 'later\n', 'Later work');

      final GitMergeResult result = await client.pull(work, remote: 'origin');

      expect(
          result,
          isA<GitMergeFastForward>().having(
            (GitMergeFastForward forward) => forward.newHead,
            'newHead',
            pushed,
          ));
    });

    test('a branch without a remote is refused', () async {
      final GitWorkingRepository work = await cloneWork('branch-only');

      await expectLater(
        client.pull(work, branch: 'main'),
        throwsArgumentError,
      );
    });
  });
}

/// Sets the local identity commits made through [repository] use.
Future<void> _setIdentity(GitRepository repository) async {
  await repository.config.set('user.name', 'Client Contract');
  await repository.config.set('user.email', 'client-contract@example.com');
}

/// Whether [repository]'s work tree holds [relativePath].
bool _fileIn(GitWorkingRepository repository, String relativePath) {
  return File(_join(repository.path, relativePath)).existsSync();
}

/// Joins [base] and [relative] with the platform separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}
