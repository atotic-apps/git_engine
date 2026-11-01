import 'git_platform.dart';
import 'process_git_platform.dart';

/// Execution context of a repository: the directory its commands run in and
/// the environment variables they receive.
///
/// Paths are resolved and normalized under the [platform] of the engine that
/// opened the repository, so a Windows-spelled repository built with a
/// scripted runner behaves the same on every machine. Every command of a
/// repository goes through its context, so a derived context (an alternate
/// index file, a fixed identity) applies to the whole repository, whatever
/// the domain of the command.
///
/// Every context carries `GIT_LITERAL_PATHSPECS=1` by default — a caller's
/// environment may override it — so pathspecs are taken literally: no path is
/// expanded as a glob and no `:(...)` magic is interpreted.
class GitRepositoryContext {
  /// Variables every context layers on top of the caller's environment.
  static const Map<String, String> _literalPathspecs = <String, String>{
    'GIT_LITERAL_PATHSPECS': '1',
  };

  /// Absolute, normalized path of the repository directory commands run in.
  final String path;

  /// Environment variables layered on top of the runner's global environment
  /// for every command of the owning repository.
  final Map<String, String> environment;

  /// Platform facts the paths of this context resolve under: path spelling
  /// and working directory relative paths hang from.
  final GitPlatform platform;

  /// Creates the context running commands in [path], with [environment]
  /// layered over the runner's global environment and paths resolved under
  /// [platform] — the platform the machine runs on when omitted.
  factory GitRepositoryContext({
    required String path,
    Map<String, String>? environment,
    GitPlatform? platform,
  }) {
    final GitPlatform facts = platform ?? hostGitPlatform;
    return GitRepositoryContext._(
      platform: facts,
      path: _absolute(path, facts),
      environment: environment,
    );
  }

  GitRepositoryContext._({
    required this.platform,
    required this.path,
    Map<String, String>? environment,
  }) : environment = Map.unmodifiable(<String, String>{
          ..._literalPathspecs,
          if (environment != null) ...environment,
        });

  /// A context whose commands work on [indexFilePath] instead of the
  /// repository's own `.git/index` (`GIT_INDEX_FILE`).
  ///
  /// Relative paths are resolved against [path]. The file itself is not
  /// required to exist: git creates an index on first write.
  GitRepositoryContext withIndexFile(String indexFilePath) {
    return withEnvironment(<String, String>{
      'GIT_INDEX_FILE': _resolve(indexFilePath),
    });
  }

  /// A context with [additional] variables merged over the current ones.
  GitRepositoryContext withEnvironment(Map<String, String> additional) {
    return GitRepositoryContext._(
      platform: platform,
      path: path,
      environment: <String, String>{
        ...environment,
        ...additional,
      },
    );
  }

  /// Resolves [filePath] against [path] when it is relative.
  String _resolve(String filePath) {
    if (platform.pathStyle.isAbsolute(filePath)) {
      return filePath;
    }
    return platform.pathStyle.join(path, filePath);
  }

  /// Returns [path] as an absolute path in [platform]'s spelling, with `.` and
  /// `..` segments resolved. Relative paths hang from the platform's current
  /// directory; the host platform supplies it on the machine the process
  /// runs on.
  static String _absolute(String path, GitPlatform platform) {
    final GitPathStyle style = platform.pathStyle;
    if (style.isAbsolute(path)) {
      return style.normalize(path);
    }
    final String? anchor = platform.currentDirectory;
    if (anchor == null) {
      throw ArgumentError.value(
        path,
        'path',
        'is relative, and the platform carries no current directory to '
            'resolve it against',
      );
    }
    return style.normalize(style.join(anchor, path));
  }
}
