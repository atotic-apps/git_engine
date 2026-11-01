import 'package:git_engine/backend.dart';
import 'package:git_engine/git_engine.dart';

/// A git command exited with a non-zero code.
///
/// The message masks the userinfo of every URL it names and the value of every
/// HTTP extra-header argument; the raw fields keep the values as git produced
/// them. [diagnostic] adds the full command, its working directory, its exit
/// code and the complete output, with URL userinfo and HTTP extra-header values
/// masked.
class GitCommandException extends GitException {
  /// The git arguments of the failed command, without the executable.
  ///
  /// The raw values may contain the userinfo of a remote URL; do not log them
  /// as they are; use [diagnostic].
  final List<String> arguments;

  /// Directory the command ran in, or null when it inherited the current one.
  final String? workingDirectory;

  /// Process exit code reported by git.
  final int exitCode;

  /// Standard output, decoded as UTF-8 (malformed bytes tolerated).
  ///
  /// The raw text may contain the userinfo of a remote URL; do not log it as
  /// it is; use [diagnostic].
  final String stdout;

  /// Standard error, decoded as UTF-8 (malformed bytes tolerated).
  ///
  /// The raw text may contain the userinfo of a remote URL; do not log it as
  /// it is; use [diagnostic].
  final String stderr;

  /// Creates the failure of a command run with [arguments] in
  /// [workingDirectory], which exited with [exitCode] and produced [stdout]
  /// and [stderr].
  GitCommandException({
    required this.arguments,
    this.workingDirectory,
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  }) : super(_message(arguments, workingDirectory, exitCode, stderr));

  @override
  String get diagnostic => diagnosticAtDepth(0);

  @override
  String diagnosticAtDepth(int depth) {
    final String where =
        workingDirectory == null ? '' : ' in $workingDirectory';
    final StringBuffer buffer = StringBuffer(message)
      ..write('\ncommand: git$where ')
      ..write(redactGitArguments(arguments))
      ..write('\nexit code: ')
      ..write(exitCode);
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
    int exitCode,
    String stderr,
  ) {
    final String where =
        workingDirectory == null ? '' : ' in $workingDirectory';
    final String command = redactGitArguments(arguments);
    return 'git$where $command exited with code $exitCode: '
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
