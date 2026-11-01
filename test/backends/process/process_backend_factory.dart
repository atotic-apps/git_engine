import 'dart:io';

import 'package:git_engine/git_engine.dart';

import '../../contract/backend_factory.dart';
import 'support/test_repository.dart';

/// [BackendFactory] creating real repositories through the installed git.
///
/// Every repository lives in its own isolated sandbox and is deleted with the
/// test that created it.
final class ProcessBackendFactory implements BackendFactory {
  /// Creates a factory that isolates every repository it creates.
  const ProcessBackendFactory();

  @override
  Future<EngineSandbox> createEngineSandbox() async {
    final TestRepository testRepository = await createTestRepository();
    final ProcessGitEngine engine = _engine(testRepository);
    return EngineSandbox(
      manager: engine,
      client: engine,
      directory: testRepository.sandbox.path,
    );
  }

  @override
  Future<GitWorkingRepository> createWorkingRepository() async {
    final TestRepository testRepository = await createTestRepository();
    return _engine(testRepository).openWorking(testRepository.directory.path);
  }

  @override
  Future<GitFileBareRepository> createBareRepository() async {
    final TestRepository testRepository = await createTestRepository();
    return _engine(testRepository).initBare(
      TestRepository.join(testRepository.sandbox.path, 'bare.git'),
      initialBranch: 'main',
    );
  }

  @override
  Future<ScenarioRepository> createRepositoryFromScenario(
    List<ScenarioCommit> scenario,
  ) async {
    final TestRepository testRepository = await createTestRepository();
    final ProcessGitWorkingRepository repository =
        (await _engine(testRepository)
                .openWorking(testRepository.directory.path))
            as ProcessGitWorkingRepository;
    final List<GitOid> commits = await _commitScenario(repository, scenario);
    return ScenarioRepository(
      repository: repository,
      commits: List<GitOid>.unmodifiable(commits),
    );
  }

  @override
  Future<ScenarioRepository> createBareRepositoryFromScenario(
    List<ScenarioCommit> scenario,
  ) async {
    final TestRepository testRepository = await createTestRepository();
    final ProcessGitEngine engine = _engine(testRepository);
    final ProcessGitWorkingRepository source =
        (await engine.openWorking(testRepository.directory.path))
            as ProcessGitWorkingRepository;
    final List<GitOid> commits = await _commitScenario(source, scenario);
    final ProcessGitFileBareRepository bare = (await engine.cloneBare(
      source.path,
      TestRepository.join(testRepository.sandbox.path, 'bare.git'),
    )) as ProcessGitFileBareRepository;
    return ScenarioRepository(
      repository: bare,
      commits: List<GitOid>.unmodifiable(commits),
    );
  }

  @override
  Future<GitIndexedRepository> createIndexedRepository(
    IndexedRepositoryKind kind, {
    required Map<String, String> files,
  }) async {
    final TestRepository testRepository = await createTestRepository();
    final ProcessGitEngine engine = _engine(testRepository);
    final ProcessGitRepository opened = (await engine
        .open(testRepository.directory.path)) as ProcessGitRepository;
    final ProcessGitWorkingRepository source =
        opened as ProcessGitWorkingRepository;
    await _commitScenario(
      source,
      <ScenarioCommit>[
        ScenarioCommit(message: 'Index fixture', files: files),
      ],
    );
    final ProcessGitRepository target;
    switch (kind) {
      case IndexedRepositoryKind.working:
        target = source;
      case IndexedRepositoryKind.bare:
        target = (await engine.cloneBare(
          source.path,
          TestRepository.join(testRepository.sandbox.path, 'bare.git'),
        )) as ProcessGitRepository;
    }
    final ProcessGitIndexedRepository indexed =
        target.withIndexFile(await _contractIndexFile(target));
    final GitOid head = (await indexed.revisions.resolveRevision('HEAD'))!;
    final GitOid tree = (await indexed.objects.readCommit(head)).tree;
    await indexed.index.readTree(tree);
    return indexed;
  }

  @override
  Future<GitIndexedRepository> createConflictedIndexedRepository(
    IndexedRepositoryKind kind, {
    required String path,
  }) async {
    final TestRepository testRepository = await createTestRepository();
    final ProcessGitEngine engine = _engine(testRepository);
    final ProcessGitRepository opened = (await engine
        .open(testRepository.directory.path)) as ProcessGitRepository;
    final ProcessGitWorkingRepository source =
        opened as ProcessGitWorkingRepository;

    final GitOid base = await _commitFixture(source, path, 'base\n', 'base');
    await testRepository
        .runGit(<String>['checkout', '-b', 'other', base.value]);
    await _commitFixture(source, path, 'other\n', 'other');
    await testRepository.runGit(const <String>['checkout', 'main']);
    await _commitFixture(source, path, 'main\n', 'main');

    ProcessGitFileBareRepository? bare;
    if (kind == IndexedRepositoryKind.bare) {
      bare = (await engine.cloneBare(
        source.path,
        TestRepository.join(testRepository.sandbox.path, 'bare.git'),
      )) as ProcessGitFileBareRepository;
    }

    var refused = false;
    try {
      await testRepository.runGit(const <String>['merge', 'other']);
    } on GitCommandException {
      refused = true;
    }
    if (!refused) {
      throw StateError('the fixture merge must leave $path conflicted');
    }

    if (kind == IndexedRepositoryKind.working) {
      return source;
    }
    final String indexFile = await _contractIndexFile(bare!);
    final File workingIndex = File(
      TestRepository.join(
        TestRepository.join(testRepository.directory.path, '.git'),
        'index',
      ),
    );
    File(indexFile).writeAsBytesSync(workingIndex.readAsBytesSync());
    return bare.withIndexFile(indexFile);
  }

  @override
  Future<GitOid> commitScenario(
    GitWorkingRepository repository,
    ScenarioCommit commit,
  ) async {
    for (final MapEntry<String, String> file in commit.files.entries) {
      final File target = File(TestRepository.join(repository.path, file.key));
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(file.value);
    }
    await repository.worktree.addAll();
    return repository.worktree.commit(commit.message, allowEmpty: true);
  }

  /// Writes and commits [scenario] through [repository]; returns the object
  /// names of the commits in scenario order.
  Future<List<GitOid>> _commitScenario(
    GitWorkingRepository repository,
    List<ScenarioCommit> scenario,
  ) async {
    final List<GitOid> commits = <GitOid>[];
    for (final ScenarioCommit commit in scenario) {
      commits.add(await commitScenario(repository, commit));
    }
    return commits;
  }

  @override
  Future<GitWorkingRepository> cloneRepository(GitFileRepository source) async {
    final TestRepository testRepository = await createTestRepository();
    return _engine(testRepository).clone(
      source.path,
      TestRepository.join(testRepository.sandbox.path, 'clone'),
    );
  }

  /// Commits one file through [repository] and returns the new commit.
  Future<GitOid> _commitFixture(
    GitWorkingRepository repository,
    String path,
    String content,
    String message,
  ) async {
    final List<GitOid> commits = await _commitScenario(
      repository,
      <ScenarioCommit>[
        ScenarioCommit(
          message: message,
          files: <String, String>{path: content},
        ),
      ],
    );
    return commits.single;
  }

  /// Path of the explicit index the index contract prepares for [repository].
  Future<String> _contractIndexFile(ProcessGitRepository repository) async {
    return TestRepository.join(
      await repository.gitDir(),
      'contract.index',
    );
  }

  ProcessGitEngine _engine(TestRepository testRepository) {
    return ProcessGitEngine(runner: testRepository.runner);
  }
}
