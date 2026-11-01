import 'dart:convert';
import 'dart:typed_data';

/// Everything needed to launch one git command.
/// {@category Testing}
class GitRunRequest {
  /// Git arguments, without the executable: the subcommand, optionally
  /// preceded by git's own global options (e.g. `-c key=value`, `--git-dir`).
  final List<String> arguments;

  /// Directory the command runs in; null inherits the current directory.
  final String? workingDirectory;

  /// Environment variables layered on top of the runner's global environment
  /// for this call only.
  final Map<String, String> environment;

  /// Bytes written to the command's standard input. When null, stdin is
  /// closed immediately so a git command reading stdin sees EOF instead of
  /// blocking forever.
  final Uint8List? stdin;

  /// Delay after which the command is stopped. Descendants that outlive its
  /// main process may keep running. When null, the runner's default delay
  /// applies.
  final Duration? timeout;

  /// Maximum number of bytes of standard output this command may produce.
  /// When null, the runner's default applies. A value that is not positive is
  /// refused with an [ArgumentError]. Standard error does not count toward it
  /// and keeps its own bound.
  ///
  /// A command that produces more is stopped and the run fails with a
  /// [GitOutputLimitException]; the output captured so far is discarded.
  final int? maxOutputBytes;

  /// Creates a request running [arguments] in [workingDirectory], with
  /// [environment], [stdin], [timeout] and [maxOutputBytes] applied to this
  /// call only.
  const GitRunRequest({
    required this.arguments,
    this.workingDirectory,
    this.environment = const <String, String>{},
    this.stdin,
    this.timeout,
    this.maxOutputBytes,
  });
}

/// Output of a git command that exited successfully.
///
/// Bytes are kept raw; the [stdout] and [stderr] getters decode on demand as
/// UTF-8 with malformed bytes tolerated.
/// {@category Testing}
class GitRunResult {
  /// Raw standard output of the command.
  final Uint8List stdoutBytes;

  /// Raw standard error of the command.
  final Uint8List stderrBytes;

  /// Process exit code; always 0 for results returned by [GitRunner.run],
  /// which reports a non-zero exit as a failure instead.
  final int exitCode;

  /// Creates a result from the raw [stdoutBytes] and [stderrBytes] of a
  /// command that exited with [exitCode].
  GitRunResult({
    required this.stdoutBytes,
    required this.stderrBytes,
    this.exitCode = 0,
  });

  /// Builds a result from decoded strings, for fake runners and tests.
  factory GitRunResult.fromStrings(
    String stdout, {
    String stderr = '',
    int exitCode = 0,
  }) {
    return GitRunResult(
      stdoutBytes: Uint8List.fromList(utf8.encode(stdout)),
      stderrBytes: Uint8List.fromList(utf8.encode(stderr)),
      exitCode: exitCode,
    );
  }

  /// Standard output decoded as UTF-8, malformed bytes replaced.
  String get stdout => utf8.decode(stdoutBytes, allowMalformed: true);

  /// Standard error decoded as UTF-8, malformed bytes replaced.
  String get stderr => utf8.decode(stderrBytes, allowMalformed: true);
}

/// Launches git commands.
///
/// An interface so another engine — a pure-Dart implementation, a test fake —
/// can replace the process-based one without touching callers.
///
/// Implementations only return for a zero exit code; a non-zero exit is
/// reported as a failure (or a typed subclass such as
/// [GitNotARepositoryException]), a spawn failure as a
/// [GitExecutableNotFoundException], an exceeded delay as a
/// [GitTimeoutException], and an exceeded output limit as a
/// [GitOutputLimitException]. On an exceeded delay or output limit the runner
/// stops the main process it started; descendants that outlive it or detach
/// from it may keep running.
/// {@category Testing}
abstract interface class GitRunner {
  /// Runs git with [request] and returns its output once the process exits.
  Future<GitRunResult> run(GitRunRequest request);
}
