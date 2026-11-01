import 'dart:async';

/// Everything needed to launch one streaming process.
/// {@category Testing}
final class GitProcessLaunchRequest {
  /// Program arguments, without the executable.
  final List<String> arguments;

  /// Directory the process runs in; null inherits the current directory.
  final String? workingDirectory;

  /// Environment variables layered on top of the launcher's global
  /// environment for this process only.
  final Map<String, String> environment;

  /// Creates a request launching [arguments] in [workingDirectory], with
  /// [environment] applied to this process only.
  const GitProcessLaunchRequest({
    required this.arguments,
    this.workingDirectory,
    this.environment = const <String, String>{},
  });
}

/// A launched process, with the streams and controls a streaming exchange
/// needs.
///
/// Unlike a gathered command result, the streams here live as long as the
/// process does: the consumer reads standard output at its own pace, and
/// [writeStdin] applies backpressure, completing only when the process has
/// taken the bytes.
/// {@category Testing}
abstract interface class GitLaunchedProcess {
  /// Standard output of the process, as bytes.
  Stream<List<int>> get stdout;

  /// Standard error of the process, as bytes.
  Stream<List<int>> get stderr;

  /// Exit code of the process; completes when the process is gone.
  Future<int> get exitCode;

  /// Writes [bytes] to the standard input and completes once the process
  /// has taken them. A broken pipe fails the future.
  Future<void> writeStdin(List<int> bytes);

  /// Closes the standard input; the process then reads an end of stream.
  /// Completes even when the process already exited.
  Future<void> closeStdin();

  /// Stops the process and completes when it is gone. On Windows,
  /// `taskkill /T /F` is attempted on the process and its tree while it is
  /// alive; on other systems it receives SIGTERM, then SIGKILL after a grace
  /// period. Descendants that outlive it, or that detach from it, may keep
  /// running; killing an already exited process is allowed.
  Future<void> kill();
}

/// Launches the streaming processes of the process backend.
///
/// The injection point beside `GitRunner` for exchanges whose bytes cross
/// in both directions while the process runs. A test supplies its own
/// launcher to observe or simulate the process; production code uses the
/// implementation over the installed git executable.
/// {@category Testing}
abstract interface class GitProcessLauncher {
  /// Starts a process for [request] and returns it once it is running.
  Future<GitLaunchedProcess> start(GitProcessLaunchRequest request);
}
