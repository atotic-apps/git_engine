import 'dart:io';

import 'test_repository.dart';

export 'process_backend_types.dart';

export '../../../support/directory_identity.dart' show sameDirectory;

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

/// An engine on the same isolated runner the test state is prepared with.
ProcessGitEngine engineAt(TestRepository repo) =>
    ProcessGitEngine(runner: repo.runner);

/// Writes [content] to [path], stages it and commits it as [message];
/// returns the new commit's object name.
Future<String> commitFile(
  TestRepository repo,
  String path,
  String content,
  String message,
) {
  return commitFileIn(repo, repo.directory.path, path, content, message);
}

/// Commits [content] written to [path] inside [workingDirectory] — any
/// repository directory of the sandbox — as [message]; returns the commit's
/// object name.
Future<String> commitFileIn(
  TestRepository repo,
  String workingDirectory,
  String path,
  String content,
  String message,
) async {
  final File file = File(TestRepository.join(workingDirectory, path));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  await repo.runGit(
    <String>['add', '--', path],
    workingDirectory: workingDirectory,
  );
  await repo.runGit(
    <String>[
      '-c',
      'user.name=$testUserName',
      '-c',
      'user.email=$testUserEmail',
      'commit',
      '-m',
      message,
    ],
    workingDirectory: workingDirectory,
  );
  return oidAt(repo, workingDirectory, 'HEAD');
}

/// Object name `HEAD` resolves to in the repository directory.
Future<String> headOid(TestRepository repo) {
  return oidAt(repo, repo.directory.path, 'HEAD');
}

/// Object name of [rev] in the repository directory.
Future<String> oidOf(TestRepository repo, String rev) {
  return oidAt(repo, repo.directory.path, rev);
}

/// Object name of [rev] with the commands run in [workingDirectory].
Future<String> oidAt(
  TestRepository repo,
  String workingDirectory,
  String rev,
) async {
  return _short(repo, workingDirectory, <String>['rev-parse', rev]);
}

/// Branch name `HEAD` points at in [workingDirectory], unread when detached.
Future<String> branchAt(TestRepository repo, String workingDirectory) {
  return _short(repo, workingDirectory, headArguments);
}

const List<String> headArguments = <String>[
  'symbolic-ref',
  '--short',
  'HEAD',
];

/// Whether the file [relativePath] exists inside [workingDirectory].
bool fileExistsIn(String workingDirectory, String relativePath) {
  final String path = TestRepository.join(workingDirectory, relativePath);
  return File(path).existsSync();
}

/// Absolute path of a fresh sandbox subdirectory [name], pre-created so the
/// engine under test proves nothing about directory creation.
Future<String> sandboxDirectory(TestRepository repo, String name) async {
  final Directory directory =
      Directory(TestRepository.join(repo.sandbox.path, name));
  await directory.create(recursive: true);
  return directory.path;
}

/// Absolute path of a sandbox subdirectory [name] that does not exist yet;
/// the engine under test has to create it.
Future<String> missingDirectory(TestRepository repo, String name) {
  return Future<String>.value(TestRepository.join(repo.sandbox.path, name));
}

/// Initializes a bare repository [name] at the sandbox root by the runner.
Future<String> initBareByRunner(TestRepository repo, String name) async {
  final String path = TestRepository.join(repo.sandbox.path, name);
  await repo.runGit(
    <String>['init', '--bare', '--', path],
    workingDirectory: repo.sandbox.path,
  );
  return path;
}

/// Clones [source] into a bare clone named [name] at the sandbox root by the
/// runner.
Future<String> cloneBareByRunner(
  TestRepository repo,
  String source,
  String name,
) async {
  final String path = TestRepository.join(repo.sandbox.path, name);
  await repo.runGit(
    <String>['clone', '--bare', '--', source, path],
    workingDirectory: repo.sandbox.path,
  );
  return path;
}

/// Clones [source] into a work tree clone named [name] at the sandbox root
/// by the runner.
Future<String> cloneByRunner(
  TestRepository repo,
  String source,
  String name,
) async {
  final String path = TestRepository.join(repo.sandbox.path, name);
  await repo.runGit(
    <String>['clone', '--', source, path],
    workingDirectory: repo.sandbox.path,
  );
  return path;
}

/// Runs [arguments] in [workingDirectory] and returns git's output trimmed
/// empty when the command fails; the plain trimmed output otherwise.
Future<String> _short(
  TestRepository repo,
  String workingDirectory,
  List<String> arguments,
) async {
  final result = await repo.runGit(
    arguments,
    workingDirectory: workingDirectory,
  );
  return result.stdout.trim();
}
