import 'package:git_engine/backend.dart';
import 'package:git_engine/git_engine.dart';

/// A git command that ran out of time, with the output captured before it was
/// stopped.
///
/// It is attached as the cause of a `GitTimeoutException`; callers that need
/// the command details read them from that cause. The message masks the
/// userinfo of every URL it names and the value of every HTTP extra-header
/// argument; the raw fields keep the values as git produced them. [diagnostic]
/// adds the full command, its working directory and the complete output, with
/// URL userinfo and HTTP extra-header values masked.
class GitCommandTimeoutException extends GitException {
  /// The git arguments of the command that ran out of time, without the
  /// executable.
  ///
  /// The raw values may contain the userinfo of a remote URL; do not log them
  /// as they are; use [diagnostic].
  final List<String> arguments;

  /// Directory the command ran in, or null when it inherited the current one.
  final String? workingDirectory;

  /// Standard output captured before the command was stopped.
  ///
  /// The raw text may contain the userinfo of a remote URL; do not log it as
  /// it is; use [diagnostic].
  final String stdout;

  /// Standard error captured before the command was stopped.
  ///
  /// The raw text may contain the userinfo of a remote URL; do not log it as
  /// it is; use [diagnostic].
  final String stderr;

  /// Creates the failure of a command run with [arguments] in
  /// [workingDirectory], which produced [stdout] and [stderr] before it was
  /// stopped.
  GitCommandTimeoutException({
    required this.arguments,
    this.workingDirectory,
    this.stdout = '',
    this.stderr = '',
  }) : super(_message(arguments, workingDirectory, stderr));

  @override
  String get diagnostic => diagnosticAtDepth(0);

  @override
  String diagnosticAtDepth(int depth) {
    final String where =
        workingDirectory == null ? '' : ' in $workingDirectory';
    final StringBuffer buffer = StringBuffer(message)
      ..write('\ncommand: git$where ')
      ..write(redactGitArguments(arguments));
    if (stdout.isNotEmpty) {
      buffer
        ..write('\nstdout:\n')
        ..write(stdout);
    }
    if (stderr.isNotEmpty) {
      buffer
        ..write('\nstderr:\n')
        ..write(stderr);
    }
    final GitException? next = cause;
    if (next != null && depth + 1 < maxDiagnosticChainLength) {
      buffer
        ..write('\n\n')
        ..write(next.diagnosticAtDepth(depth + 1));
    }
    return redactUrlUserinfo(buffer.toString());
  }

  static String _message(
    List<String> arguments,
    String? workingDirectory,
    String stderr,
  ) {
    final String where =
        workingDirectory == null ? '' : ' in $workingDirectory';
    final String command = redactGitArguments(arguments);
    return 'git$where $command did not finish before it was stopped: '
        '${_firstLine(stderr)}';
  }

  static String _firstLine(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '(no stderr output)';
    }
    return redactUrlUserinfo(trimmed.split('\n').first.trim());
  }
}
