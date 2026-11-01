import '../support/test_repository.dart';

export '../support/process_backend_types.dart';

/// Opens the repository — or the sandbox subdirectory [directory] — through
/// the same runner the test state was prepared with.
Future<ProcessGitRepository> openAt(
  TestRepository repo, {
  String? directory,
}) async {
  final ProcessGitEngine engine = ProcessGitEngine(runner: repo.runner);
  return await engine.open(directory ?? repo.directory.path)
      as ProcessGitRepository;
}

/// Writes [content] to [path], stages it and commits it as [message];
/// returns the new commit's object name.
Future<String> commitFile(
  TestRepository repo,
  String path,
  String content,
  String message,
) async {
  repo.writeFile(path, content);
  await repo.runGit(<String>['add', '--', path]);
  await repo.runGit(<String>['commit', '-m', message]);
  return headOid(repo);
}

/// Object name `HEAD` currently resolves to.
Future<String> headOid(TestRepository repo) async {
  return (await repo.runGit(<String>['rev-parse', 'HEAD'])).stdout.trim();
}

/// Object name of [rev].
Future<String> oidOf(TestRepository repo, String rev) async {
  return (await repo.runGit(<String>['rev-parse', rev])).stdout.trim();
}

/// Clones the repository into a bare repository named [name] at the sandbox
/// root; returns its path.
Future<String> createBareClone(TestRepository repo, String name) async {
  final String path = TestRepository.join(repo.sandbox.path, name);
  await repo.runGit(
    <String>['clone', '--bare', '--', repo.directory.path, path],
    workingDirectory: repo.sandbox.path,
  );
  return path;
}

/// Clones the repository into a work tree named [name] at the sandbox root;
/// returns its path.
Future<String> createClone(TestRepository repo, String name) async {
  final String path = TestRepository.join(repo.sandbox.path, name);
  await repo.runGit(
    <String>['clone', '--', repo.directory.path, path],
    workingDirectory: repo.sandbox.path,
  );
  return path;
}
