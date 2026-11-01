import 'dart:io';

import 'git_executable_not_found_exception.dart';
import 'git_platform.dart';
import 'git_process_launcher.dart';
import 'git_process_tree.dart';
import 'git_runner.dart';
import 'process_git_runner.dart';

/// [GitProcessLauncher] that starts the real `git` executable.
///
/// The command line and environment defaults come from [ProcessGitRunner]:
/// git runs without a shell, and Git terminal prompts and Git Credential
/// Manager interaction are disabled by default. Supplied environment
/// variables may override those defaults; custom helper programs retain
/// their own behavior. A launched process uses the same runner configuration
/// as the other commands of the backend.
class ProcessGitProcessLauncher implements GitProcessLauncher {
  /// Runner whose hardened command line and environment every launch goes
  /// through.
  final ProcessGitRunner runner;

  /// Builds the launcher on [runner]; defaults to a process runner with the
  /// standard hardening.
  ProcessGitProcessLauncher({ProcessGitRunner? runner})
      : runner = runner ?? ProcessGitRunner();

  @override
  Future<GitLaunchedProcess> start(GitProcessLaunchRequest request) async {
    final GitRunRequest hardened = GitRunRequest(
      arguments: request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment,
    );
    final Process process;
    try {
      process = await Process.start(
        runner.executable,
        runner.argumentsFor(hardened),
        workingDirectory: request.workingDirectory,
        environment: runner.environmentFor(hardened),
      );
    } on ProcessException catch (error) {
      if (error.errorCode == processExecutableNotFoundErrorCode) {
        throw GitExecutableNotFoundException(runner.executable, cause: error);
      }
      rethrow;
    }
    return ProcessGitLaunchedProcess._(
      process,
      runner.platform.operatingSystem,
    );
  }
}

/// [GitLaunchedProcess] over a `dart:io` [Process].
final class ProcessGitLaunchedProcess implements GitLaunchedProcess {
  final Process _process;

  /// Operating system the kill of this process is shaped for.
  final GitOperatingSystem _operatingSystem;

  ProcessGitLaunchedProcess._(this._process, this._operatingSystem);

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> writeStdin(List<int> bytes) {
    _process.stdin.add(bytes);
    return _process.stdin.flush();
  }

  @override
  Future<void> closeStdin() async {
    try {
      await _process.stdin.close();
    } catch (_) {
      // The process may already be gone; nothing left to close then.
    }
  }

  @override
  Future<void> kill() => killProcessTree(
        _process,
        operatingSystem: _operatingSystem,
      );
}
