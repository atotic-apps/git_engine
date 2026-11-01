@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'support/test_repository.dart';
import 'support/remote_test_support.dart';

void main() {
  late TestRepository repo;
  late ProcessGitRepository repository;

  setUp(() async {
    repo = await createTestRepository();
    repository = await openAt(repo);
  });

  group('fetch', () {
    test('fetches from a remote without any commit', () async {
      final String empty = await initBareByRunner(repo, 'no-commits.git');
      await repository.remotes.add('origin', empty);

      await engineAt(repo).fetch(repository, remote: 'origin');

      // And once more without naming anything, git using its default remote.
      await engineAt(repo).fetch(repository);
    });

    test('updates the remote-tracking refs', () async {
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String bare = await cloneBareByRunner(
        repo,
        repo.directory.path,
        'fetch-origin.git',
      );
      await repository.remotes.add('origin', bare);

      await engineAt(repo).fetch(repository, remote: 'origin');

      expect(
        await oidOf(repo, 'refs/remotes/origin/main'),
        await oidOf(repo, 'refs/heads/main'),
      );
    });

    test('a ref the remote does not have is a typed error', () async {
      final String bare = await cloneBareByRunner(
        repo,
        repo.directory.path,
        'typed-origin.git',
      );
      await repository.remotes.add('origin', bare);

      await expectLater(
        engineAt(repo).fetch(
          repository,
          remote: 'origin',
          refspecs: <String>['refs/heads/absent-branch'],
        ),
        throwsA(isA<GitRemoteRefNotFoundException>()),
      );
    });

    test('refspecs without a remote are refused', () async {
      await expectLater(
        engineAt(repo).fetch(repository, refspecs: <String>['main']),
        throwsArgumentError,
      );
    });

    test('prune drops the refs the remote no longer holds', () async {
      await commitFile(repo, 'a.txt', 'a\n', 'add a');
      final String bare = await cloneBareByRunner(
        repo,
        repo.directory.path,
        'prune-origin.git',
      );
      final String oid = await oidOf(repo, 'HEAD');
      // Prepared by the runner: the bare origin also holds a dead branch.
      await repo.runGit(
        <String>['update-ref', 'refs/heads/gone', oid],
        workingDirectory: bare,
      );
      await repository.remotes.add('origin', bare);
      await engineAt(repo).fetch(repository, remote: 'origin');
      expect(await oidOf(repo, 'refs/remotes/origin/gone'), oid);

      // Prepared by the runner again: the branch dies on the origin.
      await repo.runGit(
        const <String>['update-ref', '-d', 'refs/heads/gone'],
        workingDirectory: bare,
      );

      await engineAt(repo).fetch(repository, remote: 'origin');
      expect(await oidOf(repo, 'refs/remotes/origin/gone'), oid);

      await engineAt(repo).fetch(repository, remote: 'origin', prune: true);
      await expectLater(
        oidOf(repo, 'refs/remotes/origin/gone'),
        throwsA(isA<GitCommandException>()),
      );
    });
  });

  group('push', () {
    late String origin;
    late String pusherPath;
    late String rivalPath;
    late ProcessGitRepository pusher;
    late ProcessGitRepository rival;

    setUp(() async {
      repo = await createTestRepository();
      await commitFile(repo, 'base.txt', 'base\n', 'add base');
      origin = await cloneBareByRunner(
        repo,
        repo.directory.path,
        'push-origin.git',
      );
      pusherPath = await cloneByRunner(repo, origin, 'pusher');
      rivalPath = await cloneByRunner(repo, origin, 'rival');
      pusher = await openAt(repo, directory: pusherPath);
      rival = await openAt(repo, directory: rivalPath);
    });

    test('pushes a fast-forward', () async {
      await commitFileIn(
        repo,
        pusherPath,
        'pusher-file.txt',
        'pusher\n',
        'pusher work',
      );

      await engineAt(repo).push(
        pusher,
        remote: 'origin',
        refspecs: <String>['main'],
      );

      expect(
        await oidAt(repo, origin, 'refs/heads/main'),
        await oidAt(repo, pusherPath, 'refs/heads/main'),
      );
    });

    test('a push without refspecs pushes the checked out branch', () async {
      await commitFileIn(
        repo,
        pusherPath,
        'pusher-file.txt',
        'pusher\n',
        'pusher work',
      );

      await engineAt(repo).push(pusher, remote: 'origin');

      expect(
        await oidAt(repo, origin, 'refs/heads/main'),
        await oidAt(repo, pusherPath, 'refs/heads/main'),
      );
    });

    test('maps the pushed ref onto a fresh branch', () async {
      await commitFileIn(
        repo,
        pusherPath,
        'pusher-file.txt',
        'pusher\n',
        'pusher work',
      );

      await engineAt(repo).push(
        pusher,
        remote: 'origin',
        refspecs: <String>['main:refs/heads/topic'],
      );

      expect(
        await oidAt(repo, origin, 'refs/heads/topic'),
        await oidAt(repo, pusherPath, 'refs/heads/main'),
      );
    });

    test('a push that is not a fast-forward is refused', () async {
      // The rival advances the origin first.
      await commitFileIn(
        repo,
        rivalPath,
        'rival-file.txt',
        'rival\n',
        'rival work',
      );
      await engineAt(repo).push(
        rival,
        remote: 'origin',
        refspecs: <String>['main'],
      );

      // The pusher commits on top of the base and pushes: refused.
      await commitFileIn(
        repo,
        pusherPath,
        'pusher-file.txt',
        'pusher\n',
        'pusher work',
      );
      await expectLater(
        engineAt(repo).push(
          pusher,
          remote: 'origin',
          refspecs: <String>['main'],
        ),
        throwsA(isA<GitPushRejectedException>()),
      );

      // The rival's ref remains untouched on the origin.
      expect(
        await oidAt(repo, origin, 'refs/heads/main'),
        await oidAt(repo, rivalPath, 'refs/heads/main'),
      );
    });

    test('the refusal is the non-fast-forward one', () async {
      await commitFileIn(
        repo,
        rivalPath,
        'rival-file.txt',
        'rival\n',
        'rival work',
      );
      await engineAt(repo).push(
        rival,
        remote: 'origin',
        refspecs: <String>['main'],
      );
      await commitFileIn(
        repo,
        pusherPath,
        'pusher-file.txt',
        'pusher\n',
        'pusher work',
      );

      final ProcessGitEngine pusherClient = engineAt(repo);
      await pusherClient.fetch(pusher, remote: 'origin');
      final GitPushRejectedException error = await captureRefusal(
        pusherClient.push(
          pusher,
          remote: 'origin',
          refspecs: <String>['main'],
        ),
      );

      expect(error.cause, isA<GitCommandException>());
      final GitCommandException cause = error.cause as GitCommandException;
      expect(cause.stderr, contains('non-fast-forward'));
      expect(cause.exitCode, isNonZero);
    });
  });
}

/// Captures the typed refusal [refusal] raises, failing its caller otherwise.
Future<GitPushRejectedException> captureRefusal(Future<void> refusal) async {
  try {
    await refusal;
  } on GitPushRejectedException catch (error) {
    return error;
  }
  fail('the push was not refused');
}
