import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the cloning and exchange contract of [GitFileClient].
///
/// The suite builds a bare source repository with two commits and a `feature`
/// branch, then clones it in every mode: with and without checkout, on a
/// chosen branch, as a bare repository, into paths carrying spaces and
/// accents, and from the same repository spelled as a `file://` URL. It then
/// fetches from and pushes to that source through the client, by path and by
/// URL, and checks that every remote location outside the accepted forms is
/// refused without an exchange. It only relies on the file client working on
/// paths and URL forms, so its checks read the resulting work tree from disk.
void defineGitFileClientContract(BackendFactory factory) {
  group('GitFileClient', () {
    late EngineSandbox sandbox;
    late GitFileClient client;
    late GitFileBareRepository source;
    late GitOid first;
    late GitOid second;

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
      source = scenario.repository as GitFileBareRepository;
      first = scenario.commits.first;
      second = scenario.commits.last;
      await source.refs.updateRef('refs/heads/feature', first);
    });

    group('clone', () {
      test('checks out the source HEAD', () async {
        final GitWorkingRepository clone = await client.clone(
          source.path,
          sandbox.newPath('clone'),
        );

        expect(clone, isA<GitWorkingRepository>());
        expect(clone, isNot(isA<GitBareRepository>()));
        expect(await clone.branches.current(), 'main');
        expect(await clone.revisions.resolveRevision('HEAD'), second);
        expect(_fileIn(clone, 'first.txt'), isTrue);
        expect(_fileIn(clone, 'second.txt'), isTrue);
        expect(await clone.worktree.isClean(), isTrue);
      });

      test('leaves the work tree empty with noCheckout', () async {
        final GitWorkingRepository clone = await client.clone(
          source.path,
          sandbox.newPath('clone'),
          noCheckout: true,
        );

        expect(await clone.branches.current(), 'main');
        expect(await clone.revisions.resolveRevision('HEAD'), second);
        expect(_fileIn(clone, 'first.txt'), isFalse);
        expect(_fileIn(clone, 'second.txt'), isFalse);
        expect(
          Directory(_join(clone.path, '.git')).existsSync(),
          isTrue,
          reason: 'only the git directory exists in the clone',
        );
      });

      test('checks out the chosen branch', () async {
        final GitWorkingRepository clone = await client.clone(
          source.path,
          sandbox.newPath('clone'),
          branch: 'feature',
        );

        expect(await clone.branches.current(), 'feature');
        expect(await clone.revisions.resolveRevision('HEAD'), first);
        expect(_fileIn(clone, 'first.txt'), isTrue);
        expect(
          _fileIn(clone, 'second.txt'),
          isFalse,
          reason: 'only the chosen branch is checked out',
        );
      });

      test('supports a path with spaces and accents', () async {
        final GitWorkingRepository clone = await client.clone(
          source.path,
          sandbox.newPath('clone éàç with spaces'),
        );

        expect(await clone.revisions.resolveRevision('HEAD'), second);
        expect(_fileIn(clone, 'second.txt'), isTrue);
      });

      test('clones a file:// source', () async {
        final GitWorkingRepository clone = await client.clone(
          Uri.file(source.path).toString(),
          sandbox.newPath('clone-from-url'),
        );

        expect(await clone.branches.current(), 'main');
        expect(await clone.revisions.resolveRevision('HEAD'), second);
        expect(_fileIn(clone, 'second.txt'), isTrue);
        expect(await clone.worktree.isClean(), isTrue);
      });
    });

    group('cloneBare', () {
      test('returns a file bare repository holding the source refs', () async {
        final GitFileBareRepository clone = await client.cloneBare(
          source.path,
          sandbox.newPath('clone.git'),
        );

        expect(clone, isA<GitFileBareRepository>());
        expect(clone, isNot(isA<GitWorkingRepository>()));
        expect(await clone.revisions.resolveRevision('HEAD'), second);
        expect(await clone.revisions.resolveRevision('feature'), first);
      });

      test('supports a path with spaces and accents', () async {
        final GitFileBareRepository clone = await client.cloneBare(
          source.path,
          sandbox.newPath('bare éàç with spaces.git'),
        );

        expect(await clone.revisions.resolveRevision('HEAD'), second);
      });

      test('clones a bare repository from a file:// source', () async {
        final GitFileBareRepository clone = await client.cloneBare(
          Uri.file(source.path).toString(),
          sandbox.newPath('bare-from-url.git'),
        );

        expect(clone, isA<GitFileBareRepository>());
        expect(await clone.revisions.resolveRevision('HEAD'), second);
        expect(await clone.revisions.resolveRevision('feature'), first);
      });
    });

    group('fetch', () {
      test('fetches an empty bare repository without error', () async {
        final GitFileBareRepository empty =
            await factory.createBareRepository();
        final GitWorkingRepository target = await client.clone(
          source.path,
          sandbox.newPath('fetch-empty'),
        );
        await target.remotes.add('empty', empty.path);

        await client.fetch(target, remote: 'empty');

        expect(await target.refs.exists('refs/remotes/empty/main'), isFalse);
      });

      test('prune drops the refs the remote no longer has', () async {
        await source.refs.updateRef('refs/heads/gone', first);
        final GitWorkingRepository target = await client.clone(
          source.path,
          sandbox.newPath('fetch-prune'),
        );
        await client.fetch(target, remote: 'origin');
        expect(await target.refs.exists('refs/remotes/origin/gone'), isTrue);

        await source.refs.deleteRef('refs/heads/gone');
        await client.fetch(target, remote: 'origin');
        expect(
          await target.refs.exists('refs/remotes/origin/gone'),
          isTrue,
          reason: 'without prune the stale remote-tracking ref stays',
        );

        await client.fetch(target, remote: 'origin', prune: true);
        expect(await target.refs.exists('refs/remotes/origin/gone'), isFalse);
      });

      test('fetches a remote declared with a file:// URL', () async {
        await source.refs.updateRef('refs/heads/by-url', first);
        final GitWorkingRepository target = await client.clone(
          source.path,
          sandbox.newPath('fetch-url'),
        );
        await target.remotes.add('by-url', Uri.file(source.path).toString());

        await client.fetch(target, remote: 'by-url');

        expect(
          await target.refs.exists('refs/remotes/by-url/by-url'),
          isTrue,
        );
      });

      test('a ref the remote does not have is typed', () async {
        final GitWorkingRepository target = await client.clone(
          source.path,
          sandbox.newPath('fetch-typed'),
        );

        await expectLater(
          client.fetch(
            target,
            remote: 'origin',
            refspecs: <String>['refs/heads/absent-branch'],
          ),
          throwsA(isA<GitRemoteRefNotFoundException>()),
        );
      });

      test('refspecs without a remote are refused', () async {
        final GitWorkingRepository target = await client.clone(
          source.path,
          sandbox.newPath('fetch-refspecs'),
        );

        await expectLater(
          client.fetch(target, refspecs: <String>['main']),
          throwsArgumentError,
        );
      });
    });

    group('push', () {
      test('pushes a fast-forward', () async {
        final GitWorkingRepository pusher = await client.clone(
          source.path,
          sandbox.newPath('push-fast-forward'),
        );
        await _setIdentity(pusher);
        final GitOid pushed = await factory.commitScenario(
          pusher,
          const ScenarioCommit(
            message: 'Pusher work',
            files: <String, String>{'pusher.txt': 'pusher\n'},
          ),
        );

        await client.push(
          pusher,
          remote: 'origin',
          refspecs: <String>['main'],
        );

        expect(await source.revisions.resolveRevision('main'), pushed);
      });

      test('pushes to a remote declared with a file:// URL', () async {
        final GitFileBareRepository target =
            await factory.createBareRepository();
        final GitWorkingRepository pusher = await client.clone(
          source.path,
          sandbox.newPath('push-url'),
        );
        await _setIdentity(pusher);
        await pusher.remotes.add('by-url', Uri.file(target.path).toString());
        final GitOid pushed = await factory.commitScenario(
          pusher,
          const ScenarioCommit(
            message: 'Pushed by URL',
            files: <String, String>{'by-url.txt': 'by url\n'},
          ),
        );

        await client.push(
          pusher,
          remote: 'by-url',
          refspecs: <String>['main'],
        );

        expect(await target.revisions.resolveRevision('main'), pushed);
      });

      test('a push that is not a fast-forward is typed', () async {
        final GitWorkingRepository rival = await client.clone(
          source.path,
          sandbox.newPath('push-rival'),
        );
        final GitWorkingRepository pusher = await client.clone(
          source.path,
          sandbox.newPath('push-pusher'),
        );
        await _setIdentity(rival);
        await _setIdentity(pusher);

        await factory.commitScenario(
          rival,
          const ScenarioCommit(
            message: 'Rival work',
            files: <String, String>{'rival.txt': 'rival\n'},
          ),
        );
        await client.push(
          rival,
          remote: 'origin',
          refspecs: <String>['main'],
        );

        await factory.commitScenario(
          pusher,
          const ScenarioCommit(
            message: 'Pusher work',
            files: <String, String>{'pusher.txt': 'pusher\n'},
          ),
        );
        await expectLater(
          client.push(
            pusher,
            remote: 'origin',
            refspecs: <String>['main'],
          ),
          throwsA(isA<GitPushRejectedException>()),
        );
      });

      test('refspecs without a remote are refused', () async {
        final GitWorkingRepository pusher = await client.clone(
          source.path,
          sandbox.newPath('push-refspecs'),
        );

        await expectLater(
          client.push(pusher, refspecs: <String>['main']),
          throwsArgumentError,
        );
      });

      test(
          'force moves the remote branch onto a history that does not '
          'descend from its tip', () async {
        final GitWorkingRepository rival = await client.clone(
          source.path,
          sandbox.newPath('force-rival'),
        );
        final GitWorkingRepository pusher = await client.clone(
          source.path,
          sandbox.newPath('force-pusher'),
        );
        await _setIdentity(rival);
        await _setIdentity(pusher);

        final GitOid rivalTip = await factory.commitScenario(
          rival,
          const ScenarioCommit(
            message: 'Rival work',
            files: <String, String>{'rival.txt': 'rival\n'},
          ),
        );
        await client.push(
          rival,
          remote: 'origin',
          refspecs: <String>['main'],
        );

        final GitOid rewritten = await factory.commitScenario(
          pusher,
          const ScenarioCommit(
            message: 'Rewritten work',
            files: <String, String>{'rewritten.txt': 'rewritten\n'},
          ),
        );
        await expectLater(
          client.push(
            pusher,
            remote: 'origin',
            refspecs: <String>['main'],
          ),
          throwsA(isA<GitPushRejectedException>()),
        );

        await client.push(
          pusher,
          remote: 'origin',
          refspecs: <String>['main'],
          force: true,
        );

        expect(await source.revisions.resolveRevision('main'), rewritten);
        expect(
          await source.history.isAncestor(rivalTip, rewritten),
          isFalse,
          reason: 'the remote branch moved onto a history that does not '
              'descend from the tip it leaves behind',
        );
      });
    });

    group('accepted remote location forms', () {
      test('supportedSchemes names the accepted schemes', () {
        expect(
          client.supportedSchemes,
          containsAll(<String>['file', 'http', 'https', 'ssh']),
        );
      });
    });

    group('refused remote locations', () {
      test('a remote helper source is refused as a clone source', () async {
        await expectLater(
          client.clone(
            'ext::git upload-pack /nowhere',
            sandbox.newPath('refused-ext'),
          ),
          throwsA(isA<GitUnsupportedUrlException>().having(
            (GitUnsupportedUrlException error) => error.url,
            'url',
            'ext::git upload-pack /nowhere',
          )),
        );
      });

      test('a remote helper is refused as a cloneBare source', () async {
        await expectLater(
          client.cloneBare('fd::3', sandbox.newPath('refused-fd.git')),
          throwsA(isA<GitUnsupportedUrlException>()),
        );
      });

      test('a scheme outside supportedSchemes is refused', () async {
        await expectLater(
          client.clone(
            'git://example.com/repo.git',
            sandbox.newPath('refused-scheme'),
          ),
          throwsA(isA<GitUnsupportedUrlException>()),
        );
      });

      test('a value spelled like an option is refused', () async {
        await expectLater(
          client.clone(
            '--upload-pack=touch /nowhere',
            sandbox.newPath('refused-option'),
          ),
          throwsA(isA<GitUnsupportedUrlException>()),
        );
      });

      test('a remote helper is refused as a fetch remote', () async {
        final GitWorkingRepository target = await client.clone(
          source.path,
          sandbox.newPath('fetch-refused'),
        );

        await expectLater(
          client.fetch(target, remote: 'ext::git upload-pack /nowhere'),
          throwsA(isA<GitUnsupportedUrlException>()),
        );
      });

      test('a value spelled like an option is refused as a push remote',
          () async {
        final GitWorkingRepository target = await client.clone(
          source.path,
          sandbox.newPath('push-refused'),
        );

        await expectLater(
          client.push(target, remote: '--receive-pack=touch /nowhere'),
          throwsA(isA<GitUnsupportedUrlException>()),
        );
      });
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
