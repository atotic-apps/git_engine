import 'dart:io';

import 'package:git_engine/git_engine.dart';

/// One commit of a scenario built by a [BackendFactory].
///
/// [files] are written over the state left by the previous commit, then the
/// result is committed with [message]. Commits are applied in order, each one
/// on top of the previous one.
final class ScenarioCommit {
  /// Creates a scenario commit.
  const ScenarioCommit({
    required this.message,
    this.files = const <String, String>{},
  });

  /// Message of the commit.
  final String message;

  /// Files written before committing, keyed by work tree relative path.
  final Map<String, String> files;
}

/// A repository built from a scenario, with the object names of its commits.
final class ScenarioRepository {
  /// Creates a scenario repository.
  const ScenarioRepository({
    required this.repository,
    required this.commits,
  });

  /// Repository holding the scenario.
  final GitRepository repository;

  /// Object names of the scenario commits, in scenario order.
  final List<GitOid> commits;
}

/// A [GitRepositoryManager] and a [GitFileClient] together with the directory
/// their paths live in.
///
/// The repository manager and client contract suites open, initialize and
/// clone repositories, so they need both a backend entry point and somewhere
/// to create them. Every sandbox is isolated and removed with the test that
/// created it.
final class EngineSandbox {
  /// Creates a sandbox around [manager] and [client], whose paths live under
  /// [directory].
  const EngineSandbox({
    required this.manager,
    required this.client,
    required this.directory,
  });

  /// Repository manager under test.
  final GitRepositoryManager manager;

  /// Client under test, which clones repositories into [directory].
  final GitFileClient client;

  /// Directory under which repository paths are allocated.
  final String directory;

  /// A path named [name] under [directory], not created yet.
  String newPath(String name) => '$directory${Platform.pathSeparator}$name';
}

/// The storage shapes the index contract runs on.
enum IndexedRepositoryKind {
  /// A repository with a work tree and an explicit index view.
  working('working repository'),

  /// A bare repository with an explicit index view.
  bare('bare repository');

  const IndexedRepositoryKind(this.label);

  /// Human-readable name used in the test group.
  final String label;
}

/// Creates the repositories a contract suite runs against.
///
/// Contract suites only know this interface, so the same suite can run
/// unchanged on any backend. The process implementation lives in
/// `test/backends/process/process_backend_factory.dart`.
abstract interface class BackendFactory {
  /// Creates an isolated engine and the sandbox its paths live in.
  Future<EngineSandbox> createEngineSandbox();

  /// Creates an empty repository with a work tree and an active index.
  Future<GitWorkingRepository> createWorkingRepository();

  /// Creates an empty bare repository.
  Future<GitFileBareRepository> createBareRepository();

  /// Creates a repository with a work tree whose history is [scenario].
  Future<ScenarioRepository> createRepositoryFromScenario(
    List<ScenarioCommit> scenario,
  );

  /// Writes [commit]'s files into [repository]'s work tree and commits them.
  ///
  /// It lets a contract suite grow a history branch by branch without knowing
  /// how the backend stores work-tree files.
  Future<GitOid> commitScenario(
    GitWorkingRepository repository,
    ScenarioCommit commit,
  );

  /// Creates a bare repository whose history is [scenario].
  Future<ScenarioRepository> createBareRepositoryFromScenario(
    List<ScenarioCommit> scenario,
  );

  /// Clones [source] into a new repository with a work tree.
  Future<GitWorkingRepository> cloneRepository(GitFileRepository source);

  /// Creates a repository of [kind] with an explicit index view whose index
  /// holds [files], as if read from a commit.
  Future<GitIndexedRepository> createIndexedRepository(
    IndexedRepositoryKind kind, {
    required Map<String, String> files,
  });

  /// Creates a repository of [kind] with an explicit index view holding an
  /// unmerged entry for [path], with its three stages.
  Future<GitIndexedRepository> createConflictedIndexedRepository(
    IndexedRepositoryKind kind, {
    required String path,
  });
}
