/// Serves one bare repository read-only over smart HTTP for clone and fetch.
///
/// The repository path is the first positional argument; without it, a demo
/// bare repository is created in a temporary directory. `--port` selects the
/// port (default 8080). Stop with Ctrl+C or Enter (reliable on Windows).
/// Requires git 2.28 or newer.
///
///     dart run example/smart_http_server.dart [--port 8080] [repository.git]
library;

import 'dart:async';
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';
import 'package:git_engine/server_io.dart';

Future<void> main(List<String> arguments) async {
  final (int port, String? repositoryPath) = _parse(arguments);
  final Directory? created = repositoryPath == null
      ? await Directory.systemTemp.createTemp('git_engine_server_example_')
      : null;
  DartIoGitHttpServer? server;
  try {
    Map<String, String>? globalEnvironment;
    if (created != null) {
      final File config = File(_join(created.path, 'gitconfig'));
      await config.writeAsString('');
      globalEnvironment = <String, String>{
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': config.path,
      };
    }
    final ProcessGitEngine engine = ProcessGitEngine(
      globalEnvironment: globalEnvironment,
    );
    final GitFileBareRepository repository = repositoryPath == null
        ? await _createDemo(engine, created!)
        : await engine.openBare(repositoryPath);

    const GitServedRepositoryId servedId = GitServedRepositoryId('demo');
    final ProcessGitUploadPackService uploadPack = ProcessGitUploadPackService(
      resolveRepository: (GitServedRepositoryId id) =>
          id == servedId ? repository : null,
      globalEnvironment: globalEnvironment,
      inactivityTimeout: const Duration(minutes: 2),
      bufferBytes: 64 * 1024,
    );
    final GitSmartHttpHandler handler = GitSmartHttpHandler(
      resolveRepository: (List<String> segments) =>
          segments.length == 1 && segments.single == servedId.value
              ? servedId
              : null,
      authorizationPolicy: const GitReadOnlyAuthorizationPolicy(),
      uploadPack: uploadPack,
      maxBodyBytes: 64 * 1024 * 1024,
      maxConcurrentExchanges: 32,
      maxExchangeDuration: const Duration(minutes: 10),
    );
    server = await DartIoGitHttpServer.bind(
      handler: handler,
      authenticate: (HttpRequest request) => null,
      port: port,
    );

    final String url =
        'http://${server.address.address}:${server.port}/${servedId.value}';
    print('Serving ${repository.path} read-only\nURL: $url');
    if (created != null) print('Temporary directory: ${created.path}');
    print('\nIn another terminal:\n'
        '  git clone $url\n'
        '  cd ${servedId.value}\n'
        '  git fetch\n\n'
        'Press Enter or Ctrl+C to stop.');
    await stdout.flush();
    await _waitForStop();
  } finally {
    await server?.close(force: true);
    if (created != null) {
      await _deleteRecursively(created);
      print('Temporary directory removed.');
    }
  }
  await stdout.flush();
  exit(0);
}

Future<GitFileBareRepository> _createDemo(
  ProcessGitEngine engine,
  Directory root,
) async {
  final String workPath = _join(root.path, 'work');
  final GitWorkingRepository work =
      await engine.init(workPath, initialBranch: 'main');
  await File(_join(workPath, 'README.md'))
      .writeAsString('Served by the git_engine example.\n');
  await work.worktree.addAll();
  await work.worktree.commit(
    'Initial demo commit',
    identity: GitIdentity(
      name: 'git_engine example',
      email: 'example@example.com',
    ),
  );
  return engine.cloneBare(workPath, _join(root.path, 'demo.git'));
}

Future<void> _waitForStop() async {
  final Future<void> entered =
      stdin.first.then<void>((List<int> data) {}).catchError((Object error) {});
  final Future<void> interrupted =
      ProcessSignal.sigint.watch().first.then<void>((ProcessSignal signal) {});
  await Future.any(<Future<void>>[entered, interrupted]);
}

(int, String?) _parse(List<String> arguments) {
  int port = 8080;
  String? repository;
  for (var index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    if (argument == '--port') {
      port = int.parse(arguments[++index]);
    } else if (argument.startsWith('-')) {
      throw FormatException('unknown option: $argument');
    } else if (repository == null) {
      repository = argument;
    } else {
      throw FormatException('unexpected argument: $argument');
    }
  }
  return (port, repository);
}

String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

Future<void> _deleteRecursively(Directory directory) async {
  for (var attempt = 0;; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt >= 4) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
