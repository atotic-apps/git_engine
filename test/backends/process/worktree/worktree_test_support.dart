import 'dart:io';

import 'package:git_engine/git_engine.dart';

import '../support/test_repository.dart';

export '../support/process_backend_types.dart';

/// Opens the repository — or the sandbox subdirectory [directory] — through
/// the same runner the test state was prepared with.
Future<ProcessGitWorkingRepository> openAt(
  TestRepository repo, {
  String? directory,
}) async {
  final ProcessGitEngine engine = ProcessGitEngine(runner: repo.runner);
  final ProcessGitWorkingRepository repository =
      await engine.openWorking(directory ?? repo.directory.path)
          as ProcessGitWorkingRepository;
  return repository;
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

/// Short name of the checked-out branch, or `HEAD` when it is detached.
Future<String> currentBranch(TestRepository repo) async {
  final String name =
      (await repo.runGit(<String>['rev-parse', '--abbrev-ref', 'HEAD']))
          .stdout
          .trim();
  return name;
}

/// Content of [path] inside the repository, decoded as UTF-8.
String readRepoFile(TestRepository repo, String path) {
  return File(TestRepository.join(repo.directory.path, path))
      .readAsStringSync();
}

/// File at [path] inside the repository.
File repoFile(TestRepository repo, String path) {
  return File(TestRepository.join(repo.directory.path, path));
}

/// The single status entry of [path].
GitStatusEntry entryFor(List<GitStatusEntry> entries, String path) {
  return entries.singleWhere((GitStatusEntry entry) => entry.path == path);
}

/// Whether [path] exists inside the repository.
bool repoFileExists(TestRepository repo, String path) {
  return repoFile(repo, path).existsSync();
}
