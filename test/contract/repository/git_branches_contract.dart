import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the `GitBranches` contract against [factory].
///
/// Branch administration works the same on a working repository and on a
/// bare one, so every group checks at least one of each.
void defineGitBranchesContract(BackendFactory factory) {
  const List<ScenarioCommit> scenario = <ScenarioCommit>[
    ScenarioCommit(
      message: 'First',
      files: <String, String>{'a.txt': 'one\n'},
    ),
    ScenarioCommit(
      message: 'Second',
      files: <String, String>{'a.txt': 'two\n'},
    ),
  ];

  group('GitBranches.list contract', () {
    test('lists local branches sorted by name, bare ones included', () async {
      final ScenarioRepository built =
          await factory.createBareRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;

      await repository.branches.create('topic');
      await repository.branches.create('feature');

      final List<GitBranch> branches = await repository.branches.list();

      expect(branches.map((GitBranch branch) => branch.name).toList(),
          <String>['feature', 'main', 'topic']);
      expect(
        branches.map((GitBranch branch) => branch.oid).toList(),
        <GitOid>[
          built.commits.last,
          built.commits.last,
          built.commits.last,
        ],
      );
      expect(
        branches.singleWhere((GitBranch branch) => branch.isCurrent).name,
        'main',
      );
      expect(
        branches
            .where((GitBranch branch) => branch.name != 'main')
            .every((GitBranch branch) => !branch.isCurrent),
        isTrue,
      );
      expect(
        branches.every((GitBranch branch) => branch.upstream == null),
        isTrue,
      );
    });

    test('marks the branch HEAD points at as current', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;

      await repository.worktree.checkoutNewBranch('topic');

      final List<GitBranch> branches = await repository.branches.list();
      expect(
        branches.singleWhere((GitBranch branch) => branch.isCurrent).name,
        'topic',
      );
    });

    test('carries the upstream a clone set up', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository clone = await factory.cloneRepository(
        built.repository as GitFileRepository,
      );

      final List<GitBranch> branches = await clone.branches.list();

      expect(branches.single.name, 'main');
      expect(branches.single.upstream, 'origin/main');
    });
  });

  group('GitBranches.listRemote contract', () {
    test('lists the remote-tracking branches without the HEAD symbol',
        () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitFileRepository origin = built.repository as GitFileRepository;
      await origin.branches.create('topic');
      final GitWorkingRepository clone = await factory.cloneRepository(origin);

      final List<GitRef> remotes = await clone.branches.listRemote();

      expect(remotes.map((GitRef ref) => ref.name).toList(), <String>[
        'refs/remotes/origin/main',
        'refs/remotes/origin/topic',
      ]);
      expect(
        remotes.map((GitRef ref) => ref.name),
        everyElement(isNot(endsWith('/HEAD'))),
      );
      expect(
        remotes.map((GitRef ref) => ref.oid),
        everyElement(built.commits.last),
      );

      expect(
        (await clone.branches.listRemote(remote: 'origin'))
            .map((GitRef ref) => ref.name),
        <String>['refs/remotes/origin/main', 'refs/remotes/origin/topic'],
      );
      expect(
        await clone.branches.listRemote(remote: 'elsewhere'),
        isEmpty,
      );
    });
  });

  group('GitBranches.current contract', () {
    test('reads the branch a working repository is on', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;

      expect(await repository.branches.current(), 'main');

      await repository.worktree.checkoutNewBranch('topic');
      expect(await repository.branches.current(), 'topic');
    });

    test('reads the branch a bare repository points at', () async {
      final ScenarioRepository built =
          await factory.createBareRepositoryFromScenario(scenario);
      final GitFileBareRepository repository =
          built.repository as GitFileBareRepository;

      expect(await repository.branches.current(), 'main');
    });

    test('returns null while HEAD is detached', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;

      await repository.worktree.checkoutDetached(built.commits[0].value);

      expect(await repository.branches.current(), isNull);
    });

    test('names the branch HEAD will create in a repository without commits',
        () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();

      expect(await repository.branches.current(), 'main');
    });
  });

  group('GitBranches.create contract', () {
    test('creates a branch at HEAD without switching to it', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;

      await repository.branches.create('topic');

      expect(
        await repository.refs.resolveRef('refs/heads/topic'),
        built.commits.last,
      );
      expect(await repository.branches.current(), 'main');
    });

    test('creates a branch at the given start point', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;

      await repository.branches.create(
        'topic',
        startPoint: built.commits[0].value,
      );

      expect(
        await repository.refs.resolveRef('refs/heads/topic'),
        built.commits[0],
      );
    });

    test('refuses a taken name unless forced, then moves the branch', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;
      await repository.branches.create('topic');

      await expectLater(
        repository.branches.create('topic'),
        throwsA(isA<GitRefExistsException>().having(
          (GitRefExistsException error) => error.name,
          'name',
          'topic',
        )),
      );
      expect(
        await repository.refs.resolveRef('refs/heads/topic'),
        built.commits.last,
      );

      await repository.branches.create(
        'topic',
        startPoint: built.commits[0].value,
        force: true,
      );
      expect(
        await repository.refs.resolveRef('refs/heads/topic'),
        built.commits[0],
      );
    });

    test('refuses a start point that names nothing', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;

      await expectLater(
        repository.branches.create('topic', startPoint: 'no-such-start'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'no-such-start',
          ),
        ),
      );
      expect(await repository.refs.exists('refs/heads/topic'), isFalse);
    });

    test('refuses to start from an unborn HEAD', () async {
      final GitWorkingRepository repository =
          await factory.createWorkingRepository();

      await expectLater(
        repository.branches.create('topic'),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(await repository.branches.list(), isEmpty);
    });
  });

  group('GitBranches.rename contract', () {
    test('renames a branch and updates HEAD when it is the current one',
        () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;

      await repository.branches.rename('main', 'trunk');

      expect(await repository.branches.current(), 'trunk');
      expect(await repository.refs.exists('refs/heads/main'), isFalse);
      expect(
        await repository.refs.resolveRef('refs/heads/trunk'),
        built.commits.last,
      );
    });

    test('refuses an unknown branch', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;

      await expectLater(
        repository.branches.rename('no-such-branch', 'renamed'),
        throwsA(isA<GitRefNotFoundException>().having(
          (GitRefNotFoundException error) => error.name,
          'name',
          'no-such-branch',
        )),
      );
    });

    test('refuses a taken new name unless forced', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;
      await repository.branches.create('topic');
      await repository.branches.create('taken');

      await expectLater(
        repository.branches.rename('topic', 'taken'),
        throwsA(
          isA<GitRefExistsException>().having(
            (GitRefExistsException error) => error.name,
            'name',
            'taken',
          ),
        ),
      );
      expect(await repository.refs.exists('refs/heads/topic'), isTrue);

      await repository.branches.rename('topic', 'taken', force: true);
      expect(await repository.refs.exists('refs/heads/topic'), isFalse);
      expect(
        await repository.refs.resolveRef('refs/heads/taken'),
        built.commits.last,
      );
    });

    test('works in a bare repository', () async {
      final ScenarioRepository built =
          await factory.createBareRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;
      await repository.branches.create('topic');

      await repository.branches.rename('topic', 'feature');

      expect(await repository.refs.exists('refs/heads/topic'), isFalse);
      expect(await repository.refs.exists('refs/heads/feature'), isTrue);
    });
  });

  group('GitBranches.delete contract', () {
    test('deletes a fully merged branch', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;
      await repository.branches.create('topic');

      await repository.branches.delete('topic');

      expect(await repository.refs.exists('refs/heads/topic'), isFalse);
    });

    test('refuses an unmerged branch unless forced', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;

      await repository.worktree.checkoutNewBranch(
        'topic',
        startPoint: built.commits[0].value,
      );
      await factory.commitScenario(
        repository,
        const ScenarioCommit(
          message: 'Topic work',
          files: <String, String>{'topic.txt': 't\n'},
        ),
      );
      await repository.worktree.checkout('main');

      await expectLater(
        repository.branches.delete('topic'),
        throwsA(
          isA<GitBranchNotMergedException>().having(
            (GitBranchNotMergedException error) => error.branch,
            'branch',
            'topic',
          ),
        ),
      );
      expect(await repository.refs.exists('refs/heads/topic'), isTrue);

      await repository.branches.delete('topic', force: true);
      expect(await repository.refs.exists('refs/heads/topic'), isFalse);
    });

    test('refuses an unknown branch', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;

      await expectLater(
        repository.branches.delete('no-such-branch'),
        throwsA(
          isA<GitRefNotFoundException>().having(
            (GitRefNotFoundException error) => error.name,
            'name',
            'no-such-branch',
          ),
        ),
      );
    });

    test('refuses the branch HEAD points at, in a work tree and bare',
        () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository repository =
          built.repository as GitWorkingRepository;

      await expectLater(
        repository.branches.delete('main', force: true),
        throwsA(isA<GitException>()),
      );
      expect(await repository.refs.exists('refs/heads/main'), isTrue);

      final ScenarioRepository bareBuilt =
          await factory.createBareRepositoryFromScenario(scenario);
      await expectLater(
        bareBuilt.repository.branches.delete('main', force: true),
        throwsA(isA<GitException>()),
      );
      expect(await bareBuilt.repository.refs.exists('refs/heads/main'), isTrue);
    });

    test('deletes another branch of a bare repository', () async {
      final ScenarioRepository built =
          await factory.createBareRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;
      await repository.branches.create('topic');

      await repository.branches.delete('topic');

      expect(await repository.refs.exists('refs/heads/topic'), isFalse);
    });
  });

  group('GitBranches.setUpstream contract', () {
    test('makes a branch track an upstream the listing reads back', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository clone = await factory.cloneRepository(
        built.repository as GitFileRepository,
      );

      await clone.branches.setUpstream('main', 'origin/main');

      final GitBranch branch = (await clone.branches.list())
          .singleWhere((GitBranch branch) => branch.name == 'main');
      expect(branch.upstream, 'origin/main');
      expect(
        await clone.revisions.resolveRevision('main@{upstream}'),
        built.commits.last,
      );
    });

    test('refuses an unknown branch', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository clone = await factory.cloneRepository(
        built.repository as GitFileRepository,
      );

      await expectLater(
        clone.branches.setUpstream('no-such-branch', 'origin/main'),
        throwsA(
          isA<GitRefNotFoundException>().having(
            (GitRefNotFoundException error) => error.name,
            'name',
            'no-such-branch',
          ),
        ),
      );
    });

    test('refuses an upstream that names nothing', () async {
      final ScenarioRepository built =
          await factory.createRepositoryFromScenario(scenario);
      final GitWorkingRepository clone = await factory.cloneRepository(
        built.repository as GitFileRepository,
      );

      await expectLater(
        clone.branches.setUpstream('main', 'origin/no-such'),
        throwsA(
          isA<GitUnknownRevisionException>().having(
            (GitUnknownRevisionException error) => error.expression,
            'expression',
            'origin/no-such',
          ),
        ),
      );
    });

    test('works in a bare repository with a local upstream', () async {
      final ScenarioRepository built =
          await factory.createBareRepositoryFromScenario(scenario);
      final GitRepository repository = built.repository;
      await repository.branches.create('other');

      await repository.branches.setUpstream('main', 'other');

      final GitBranch branch = (await repository.branches.list())
          .singleWhere((GitBranch branch) => branch.name == 'main');
      expect(branch.upstream, 'other');
    });
  });
}
