import 'package:git_engine/src/backends/process/git_command_exception.dart'
    show GitCommandException;
import 'package:git_engine/testing.dart';

export 'process_backend_types.dart';

/// A [GitRunner] that returns pre-scripted replies and records every request.
///
/// It follows the [GitRunner] contract: a command that exits non-zero is
/// scripted as an error with [failWith], never as a result carrying a non-zero
/// [GitRunResult.exitCode]. A request whose arguments match no reply fails the
/// test with a [StateError].
final class ScriptedGitRunner implements GitRunner {
  final List<GitRunRequest> _requests = <GitRunRequest>[];
  final List<_ScriptedReply> _replies = <_ScriptedReply>[];

  /// Every request this runner received, in call order.
  List<GitRunRequest> get requests =>
      List<GitRunRequest>.unmodifiable(_requests);

  /// Answers the command with exactly [arguments] by returning [result].
  void replyTo(List<String> arguments, GitRunResult result) {
    _replies.add(_ScriptedReply(
      arguments: List<String>.unmodifiable(arguments),
      result: result,
    ));
  }

  /// Answers the command with exactly [arguments] by throwing [error].
  void failWith(List<String> arguments, Object error) {
    _replies.add(_ScriptedReply(
      arguments: List<String>.unmodifiable(arguments),
      error: error,
    ));
  }

  /// Makes `symbolic-ref HEAD` fail the way git does on a detached `HEAD`,
  /// so an operation that reads the checked-out branch first finds none.
  void detachHead() {
    const List<String> command = <String>[
      'symbolic-ref',
      '--quiet',
      'HEAD',
    ];
    failWith(
      command,
      GitCommandException(arguments: command, exitCode: 1, stderr: ''),
    );
  }

  @override
  Future<GitRunResult> run(GitRunRequest request) async {
    _requests.add(request);
    for (final _ScriptedReply reply in _replies) {
      if (_sameArguments(reply.arguments, request.arguments)) {
        final Object? error = reply.error;
        if (error != null) {
          throw error;
        }
        return reply.result!;
      }
    }
    throw StateError(
      'No scripted reply for: git ${request.arguments.join(' ')}',
    );
  }

  /// Whether [first] and [second] hold the same arguments in the same order.
  static bool _sameArguments(List<String> first, List<String> second) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }
}

/// One scripted answer, either a result or an error.
final class _ScriptedReply {
  const _ScriptedReply({
    required this.arguments,
    this.result,
    this.error,
  });

  final List<String> arguments;
  final GitRunResult? result;
  final Object? error;
}
