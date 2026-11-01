import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';

import 'git_command_exception.dart';
import 'git_file_system.dart';
import 'git_platform.dart';
import 'git_process_launcher.dart';
import 'git_remote_failure.dart';
import 'git_remote_location.dart';
import 'git_repository_context.dart';
import 'git_runner.dart';
import 'git_version.dart';
import 'process_git_file_bare_repository.dart';
import 'process_git_file_system.dart';
import 'process_git_platform.dart';
import 'process_git_process_launcher.dart';
import 'process_git_repository.dart';
import 'process_git_runner.dart';
import 'process_git_working_repository.dart';

part 'process_git_engine_client.dart';
part 'process_git_engine_transport.dart';

/// [GitRepositoryManager], [GitFileClient] and [GitEngineRuntime] that talk to
/// the real git executable through a [ProcessGitRunner] (or any [GitRunner]
/// handed to the constructor).
///
/// It opens and creates repositories, clones them, and answers the neutral
/// [GitEngineRuntime] with [engineVersion] and [ensureMinimumVersion], which
/// delegate to [gitVersion] and [ensureGitVersion]. Its repository creation,
/// cloning and opening methods return the contracts of
/// [GitRepositoryManager] and [GitFileClient], so a caller depends on the
/// interfaces alone.
///
/// Clone, fetch, pull and push run with the bounding transport environment of
/// [transportEnvironment] and the prompt defaults described by `GitFileClient`.
///
/// The backend assumes git 2.28 or newer. `mergeTree` of the merge facade
/// needs git 2.38 or newer (`merge-tree --write-tree`); on an older installed
/// git it raises `GitFeatureUnavailableException`.
///
/// ## Running git on Windows
///
/// Git is started directly, never through a shell (`runInShell: false`), with
/// its arguments handed over as a list. Every command gets
/// `-c core.quotepath=false` so non-ASCII paths stay verbatim, and Windows
/// commands get `-c core.longpaths=true` unless the constructor is given
/// `windowsLongPaths: false`. The default environment sets
/// `GIT_TERMINAL_PROMPT=0`, `GCM_INTERACTIVE=never` and `LC_ALL=C`; supplied
/// environment variables may override these defaults. Output is decoded as
/// UTF-8.
/// {@category Getting started}
class ProcessGitEngine
    with _ProcessGitTransport, _ProcessGitFileClient
    implements GitRepositoryManager, GitFileClient, GitEngineRuntime {
  /// Runner every command of this engine goes through.
  final GitRunner _runner;

  /// File system the creation guards of this engine inspect; the `dart:io`
  /// one by default, an in-memory one in tests.
  final GitFileSystem _fileSystem;

  /// Platform facts — operating system, path style, environment — this
  /// engine and the repositories it opens adapt to.
  final GitPlatform _platform;

  /// Launcher of the streaming processes of the repositories this engine
  /// opens, such as archive output; built on [_runner] when it is a
  /// [ProcessGitRunner].
  late final GitProcessLauncher _launcher;

  /// Builds the process engine: the git program it launches, the environment
  /// it layers over every command, its Windows long-path setting and the
  /// delay of a command that names none.
  ///
  /// [executable] is the git program — a name resolved on the `PATH` or a
  /// path. [globalEnvironment] is layered over the inherited environment of
  /// every command, [windowsLongPaths] adds `-c core.longpaths=true` to
  /// Windows commands, and [defaultTimeout] is the delay applied to a command
  /// that carries none; a null [defaultTimeout] means no limit, and the
  /// five-minute default matches [ProcessGitRunner.defaultTimeout].
  /// [defaultMaxOutputBytes] bounds the standard output of a command that
  /// carries no limit of its own; null, the default, means no limit. A value
  /// that is not positive raises an [ArgumentError]. [platform] supplies the
  /// operating system, path style and environment the engine and its
  /// repositories adapt to.
  ///
  /// [runner], [fileSystem] and [launcher] are injection points for tests and
  /// for applications that bring their own execution; their types live in
  /// `package:git_engine/testing.dart`. A [runner] already carries its
  /// executable, environment, long-path setting, timeout and output limit, so
  /// giving one together with [executable], [globalEnvironment],
  /// [windowsLongPaths], [defaultTimeout] or [defaultMaxOutputBytes] raises an
  /// [ArgumentError] naming the extra parameter.
  ProcessGitEngine({
    GitRunner? runner,
    GitFileSystem? fileSystem,
    GitPlatform? platform,
    GitProcessLauncher? launcher,
    String executable = 'git',
    Map<String, String>? globalEnvironment,
    bool windowsLongPaths = true,
    Duration? defaultTimeout = const Duration(minutes: 5),
    int? defaultMaxOutputBytes,
  }) : this._(
          providedRunner: runner,
          providedFileSystem: fileSystem,
          providedPlatform: platform,
          providedLauncher: launcher,
          executable: executable,
          globalEnvironment: globalEnvironment,
          windowsLongPaths: windowsLongPaths,
          defaultTimeout: defaultTimeout,
          defaultMaxOutputBytes: defaultMaxOutputBytes,
        );

  ProcessGitEngine._({
    required GitRunner? providedRunner,
    required GitFileSystem? providedFileSystem,
    required GitPlatform? providedPlatform,
    required GitProcessLauncher? providedLauncher,
    required String executable,
    required Map<String, String>? globalEnvironment,
    required bool windowsLongPaths,
    required Duration? defaultTimeout,
    required int? defaultMaxOutputBytes,
  })  : _runner = providedRunner ??
            ProcessGitRunner(
              executable: executable,
              globalEnvironment: globalEnvironment,
              windowsLongPaths: windowsLongPaths,
              defaultTimeout: defaultTimeout,
              defaultMaxOutputBytes: defaultMaxOutputBytes,
              platform: providedPlatform,
            ),
        _fileSystem = providedFileSystem ?? const ProcessGitFileSystem(),
        _platform = providedPlatform ?? hostGitPlatform {
    if (providedRunner != null) {
      _refuseConfigurationWithRunner(
        executable: executable,
        globalEnvironment: globalEnvironment,
        windowsLongPaths: windowsLongPaths,
        defaultTimeout: defaultTimeout,
        defaultMaxOutputBytes: defaultMaxOutputBytes,
      );
    }
    final GitRunner configuredRunner = _runner;
    _launcher = providedLauncher ??
        ProcessGitProcessLauncher(
          runner:
              configuredRunner is ProcessGitRunner ? configuredRunner : null,
        );
  }

  /// Refuses an engine configuration option that a provided runner already
  /// carries.
  static void _refuseConfigurationWithRunner({
    required String executable,
    required Map<String, String>? globalEnvironment,
    required bool windowsLongPaths,
    required Duration? defaultTimeout,
    required int? defaultMaxOutputBytes,
  }) {
    if (executable != 'git') {
      throw ArgumentError.value(
        executable,
        'executable',
        'cannot be given with a runner, which carries its own executable',
      );
    }
    if (globalEnvironment != null) {
      throw ArgumentError.value(
        globalEnvironment,
        'globalEnvironment',
        'cannot be given with a runner, which carries its own environment',
      );
    }
    if (!windowsLongPaths) {
      throw ArgumentError.value(
        windowsLongPaths,
        'windowsLongPaths',
        'cannot be given with a runner, which carries its own long-path '
            'setting',
      );
    }
    if (defaultTimeout != const Duration(minutes: 5)) {
      throw ArgumentError.value(
        defaultTimeout,
        'defaultTimeout',
        'cannot be given with a runner, which carries its own timeout',
      );
    }
    if (defaultMaxOutputBytes != null) {
      throw ArgumentError.value(
        defaultMaxOutputBytes,
        'defaultMaxOutputBytes',
        'cannot be given with a runner, which carries its own output limit',
      );
    }
  }

  @override
  List<String> get supportedSchemes => supportedRemoteSchemes;

  /// Version string reported by `git --version`, e.g.
  /// `git version 2.41.0.windows.1`.
  Future<String> gitVersion() async {
    final GitRunResult result = await _runner
        .run(const GitRunRequest(arguments: <String>['--version']));
    return result.stdout.trim();
  }

  /// Ensures the installed git is at least [minimumVersion], written as
  /// `major[.minor[.patch]]`.
  ///
  /// Throws [GitVersionException] when the installed git is older,
  /// [FormatException] when `git --version` cannot be parsed, and
  /// [ArgumentError] when [minimumVersion] itself is malformed.
  Future<void> ensureGitVersion(String minimumVersion) async {
    final String raw = await gitVersion();
    final GitVersionTriple? actual = parseGitVersion(raw);
    if (actual == null) {
      throw FormatException('Cannot parse git version from: "$raw"', raw);
    }
    final GitVersionTriple? required = parseVersionConstraint(minimumVersion);
    if (required == null) {
      throw ArgumentError.value(
        minimumVersion,
        'minimumVersion',
        'expected "major[.minor[.patch]]"',
      );
    }
    if (compareGitVersions(actual, required) < 0) {
      throw GitVersionException(
        requiredVersion: minimumVersion,
        actualVersion: raw,
      );
    }
  }

  @override
  Future<String> engineVersion() => gitVersion();

  @override
  Future<void> ensureMinimumVersion(String minimumVersion) =>
      ensureGitVersion(minimumVersion);

  @override
  Future<GitFileRepository> open(String path) => _open(path);

  /// Opens [path] as the concrete process type its kind selects.
  Future<ProcessGitRepository> _open(String path) async {
    final GitRepositoryContext context = GitRepositoryContext(
      path: path,
      platform: _platform,
    );
    final GitRunResult kind = await _runner.run(GitRunRequest(
      arguments: const <String>['rev-parse', '--is-bare-repository'],
      workingDirectory: context.path,
      environment: context.environment,
    ));
    return kind.stdout.trim() == 'true'
        ? ProcessGitFileBareRepository(
            runner: _runner,
            context: context,
            fileSystem: _fileSystem,
            platform: _platform,
            launcher: _launcher,
          )
        : ProcessGitWorkingRepository(
            runner: _runner,
            context: context,
            fileSystem: _fileSystem,
            platform: _platform,
            launcher: _launcher,
          );
  }

  @override
  Future<GitWorkingRepository> openWorking(String path) async {
    final ProcessGitRepository repository = await _open(path);
    if (repository is ProcessGitWorkingRepository) {
      return repository;
    }
    throw GitNotAWorkingRepositoryException(path);
  }

  @override
  Future<GitFileBareRepository> openBare(String path) async {
    final ProcessGitRepository repository = await _open(path);
    if (repository is ProcessGitFileBareRepository) {
      return repository;
    }
    throw GitNotABareRepositoryException(path);
  }

  @override
  Future<GitWorkingRepository> init(
    String path, {
    String? initialBranch,
    bool allowOccupied = false,
  }) async {
    await _init(path,
        initialBranch: initialBranch, allowOccupied: allowOccupied);
    return openWorking(path);
  }

  @override
  Future<GitFileBareRepository> initBare(
    String path, {
    String? initialBranch,
    bool allowOccupied = false,
  }) async {
    await _init(
      path,
      initialBranch: initialBranch,
      bare: true,
      allowOccupied: allowOccupied,
    );
    return openBare(path);
  }

  /// Runs `git init`; [bare], [initialBranch] and [allowOccupied] refine what
  /// it creates. Unless [allowOccupied], a directory that already holds files
  /// is refused before git runs, its content untouched. The refusal is
  /// decided on the injected [fileSystem], without running git.
  Future<void> _init(
    String path, {
    required String? initialBranch,
    bool bare = false,
    bool allowOccupied = false,
  }) async {
    if (!allowOccupied && await _holdsFiles(path)) {
      throw GitOccupiedDirectoryException(path);
    }
    await _runner.run(GitRunRequest(arguments: <String>[
      'init',
      if (initialBranch != null) '--initial-branch=$initialBranch',
      if (bare) '--bare',
      '--',
      path,
    ]));
  }

  /// Whether a directory already exists at [path] and holds at least one
  /// entry, as seen through the injected [fileSystem]. A path that holds a
  /// file instead of a directory is left to git, which fails on it with its
  /// own answer.
  Future<bool> _holdsFiles(String path) async {
    if (!await _fileSystem.isDirectory(path)) {
      return false;
    }
    return (await _fileSystem.list(path)).isNotEmpty;
  }
}
