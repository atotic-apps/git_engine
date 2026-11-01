import 'dart:async';

import 'package:git_engine/testing.dart';

/// A [GitProcessLauncher] a test controls: it records every launch request
/// and hands back a [FakeGitProcess] the test drives and observes.
final class FakeGitProcessLauncher implements GitProcessLauncher {
  /// Every launch request, in order.
  final List<GitProcessLaunchRequest> requests = <GitProcessLaunchRequest>[];

  /// Every process the launcher produced, in order.
  final List<FakeGitProcess> processes = <FakeGitProcess>[];

  /// When set, [start] throws this.
  Object? startError;

  @override
  Future<GitLaunchedProcess> start(GitProcessLaunchRequest request) async {
    requests.add(request);
    final Object? error = startError;
    if (error != null) {
      throw error;
    }
    final FakeGitProcess process = FakeGitProcess();
    processes.add(process);
    return process;
  }
}

/// A [GitLaunchedProcess] a test drives and observes.
///
/// The test feeds [stdoutController] and [stderrController], completes
/// [exit], holds writes back through [writeGate], and reads what the
/// service wrote and when it killed the process.
final class FakeGitProcess implements GitLaunchedProcess {
  /// Drives the standard output the service reads.
  final StreamController<List<int>> stdoutController =
      StreamController<List<int>>();

  /// Drives the standard error the service drains.
  final StreamController<List<int>> stderrController =
      StreamController<List<int>>();

  /// Completes the exit code; [kill] completes it when still open.
  final Completer<int> exit = Completer<int>();

  /// Bytes written to the standard input, in order, one entry per write.
  final List<List<int>> written = <List<int>>[];

  /// Whether the standard input was closed.
  bool stdinClosed = false;

  /// How many times the process was killed.
  int killCalls = 0;

  /// When set, every write waits for it, so a test holds the backpressure
  /// of the standard input.
  Completer<void>? writeGate;

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  Future<int> get exitCode => exit.future;

  @override
  Future<void> writeStdin(List<int> bytes) async {
    final Completer<void>? gate = writeGate;
    if (gate != null) {
      await gate.future;
    }
    written.add(List<int>.of(bytes));
  }

  @override
  Future<void> closeStdin() async {
    stdinClosed = true;
  }

  @override
  Future<void> kill() async {
    killCalls++;
    if (!exit.isCompleted) {
      exit.complete(-9);
    }
  }

  /// Closes both stream controllers, for the tests that are done with the
  /// process.
  Future<void> dispose() async {
    await stdoutController.close();
    await stderrController.close();
  }
}
