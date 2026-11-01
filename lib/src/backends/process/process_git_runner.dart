import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'git_command_exception.dart';
import 'git_command_timeout_exception.dart';
import 'git_executable_not_found_exception.dart';
import 'git_platform.dart';
import 'git_process_tree.dart';
import 'git_runner.dart';
import 'process_git_platform.dart';
import 'tail_byte_buffer.dart';

/// Marker handed to [Future.any] when the allowed delay expires.
enum _TimeoutMarker { instance }

/// Marker handed to [Future.any] when the allowed output is exceeded.
enum _OutputLimitMarker { instance }

/// [GitRunner] implementation that launches the real `git` executable.
///
/// Git is never started through a shell: the arguments are handed to
/// [Process.start] as a list. Stdin is closed unless explicit bytes are
/// given. Environment defaults disable Git terminal prompts and Git
/// Credential Manager interaction and select the C locale. Global and
/// per-request environment variables may override those defaults. Custom
/// helper programs retain their own behavior; the client supplies the SSH
/// defaults for remote exchanges.
///
/// A command whose stderr says it did not run inside a repository raises
/// [GitNotARepositoryException], carrying that command's [GitCommandException]
/// as its cause.
///
/// Standard error is retained only up to its most recent 16 MiB, which keeps
/// the final diagnosis of a failing command while an endless stream — such as
/// the `remote:` messages of a hostile remote — cannot grow memory without
/// bound. Truncation never fails or stops the command: a command that succeeds
/// still succeeds.
///
/// Standard output has no bound by default, because reading a large object is
/// legitimate. A positive [defaultMaxOutputBytes] bounds it; a command that
/// produces more is stopped and fails with a [GitOutputLimitException].
/// Standard error keeps its own bound and does not count toward that limit.
class ProcessGitRunner implements GitRunner {
  /// Executable to launch; a name resolved on the PATH, or a path.
  final String executable;

  /// Environment variables layered on top of the inherited process
  /// environment for every command of this runner.
  final Map<String, String> globalEnvironment;

  /// Whether Windows commands get `-c core.longpaths=true`, so paths beyond
  /// the classic MAX_PATH limit work. Other platforms are unaffected.
  final bool windowsLongPaths;

  /// Platform facts — operating system, path style, environment — the
  /// arguments and the process stopping of this runner adapt to.
  final GitPlatform platform;

  /// Delay applied to commands that carry no per-request timeout; null means
  /// no limit.
  final Duration? defaultTimeout;

  /// Maximum number of standard-output bytes applied to commands that carry
  /// no per-request limit; null means no limit. A value that is not positive
  /// is refused with an [ArgumentError].
  final int? defaultMaxOutputBytes;

  /// Creates the runner launching [executable], layering
  /// [globalEnvironment] over the inherited environment; [windowsLongPaths],
  /// [platform], [defaultTimeout] and [defaultMaxOutputBytes] give their
  /// defaults to every command. The platform defaults to the platform the
  /// machine runs on.
  ///
  /// [defaultMaxOutputBytes] must be positive when given; a command's own
  /// [GitRunRequest.maxOutputBytes] takes precedence over it.
  ProcessGitRunner({
    this.executable = 'git',
    Map<String, String>? globalEnvironment,
    this.windowsLongPaths = true,
    GitPlatform? platform,
    this.defaultTimeout = const Duration(minutes: 5),
    this.defaultMaxOutputBytes,
  })  : platform = platform ?? hostGitPlatform,
        globalEnvironment =
            Map.unmodifiable(globalEnvironment ?? const <String, String>{}) {
    final int? limit = defaultMaxOutputBytes;
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(
        limit,
        'defaultMaxOutputBytes',
        'must be positive',
      );
    }
  }

  /// Full argv for [request]: the hardening `-c` options come first, so the
  /// caller's arguments may freely mix global options and a subcommand.
  ///
  /// The options reflect the injected [platform], not the machine the
  /// runner spawns processes on.
  List<String> argumentsFor(GitRunRequest request) => <String>[
        '-c',
        'core.quotepath=false',
        if (windowsLongPaths &&
            platform.operatingSystem == GitOperatingSystem.windows) ...<String>[
          '-c',
          'core.longpaths=true',
        ],
        ...request.arguments,
      ];

  /// Environment for [request]: hardened defaults, then the runner's global
  /// environment, then the per-request variables — each layer overriding the
  /// previous one.
  Map<String, String> environmentFor(GitRunRequest request) => <String, String>{
        'GIT_TERMINAL_PROMPT': '0',
        'GCM_INTERACTIVE': 'never',
        'LC_ALL': 'C',
        ...globalEnvironment,
        ...request.environment,
      };

  @override
  Future<GitRunResult> run(GitRunRequest request) async {
    final List<String> arguments = argumentsFor(request);
    final Map<String, String> environment = environmentFor(request);
    final Duration? timeout = request.timeout ?? defaultTimeout;
    final int? maxOutputBytes = request.maxOutputBytes ?? defaultMaxOutputBytes;
    if (maxOutputBytes != null && maxOutputBytes <= 0) {
      throw ArgumentError.value(
        maxOutputBytes,
        'maxOutputBytes',
        'must be positive',
      );
    }
    final String? workingDirectory = request.workingDirectory;
    if (workingDirectory != null && !Directory(workingDirectory).existsSync()) {
      throw GitException(
        'git working directory does not exist: "$workingDirectory"',
      );
    }

    final Completer<_TimeoutMarker> timedOut = Completer<_TimeoutMarker>();
    Timer? timeoutTimer;
    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        if (!timedOut.isCompleted) {
          timedOut.complete(_TimeoutMarker.instance);
        }
      });
    }

    try {
      final Process process = await _startProcess(
        request: request,
        arguments: arguments,
        environment: environment,
        timeout: timeout,
        timedOut: timedOut,
      );
      _feedStdin(process, request.stdin);

      final BytesBuilder stdoutBuilder = BytesBuilder(copy: false);
      final TailByteBuffer stderrBuffer = TailByteBuffer();
      final _OutputDrain stdoutDrain = _OutputDrain(
        process.stdout,
        stdoutBuilder.add,
        maxBytes: maxOutputBytes,
        onExceeded: stdoutBuilder.clear,
      );
      final _OutputDrain stderrDrain = _OutputDrain(
        process.stderr,
        stderrBuffer.add,
      );
      final List<_OutputDrain> drains = <_OutputDrain>[
        stdoutDrain,
        stderrDrain,
      ];
      final Future<void> outputDone = Future.wait<void>(
        drains.map((_OutputDrain drain) => drain.done),
      ).then((_) {});

      final Object? winner = await Future.any<Object?>(<Future<Object?>>[
        process.exitCode,
        timedOut.future.then((_) => _TimeoutMarker.instance),
        stdoutDrain.exceeded.then((_) => _OutputLimitMarker.instance),
      ]);
      if (winner == _TimeoutMarker.instance) {
        await _killAndSettle(process, outputDone, drains: drains);
        throw GitTimeoutException(
          timeout: timeout!,
          cause: GitCommandTimeoutException(
            arguments: request.arguments,
            workingDirectory: workingDirectory,
            stdout: _decode(stdoutBuilder.takeBytes()),
            stderr: _decode(stderrBuffer.takeBytes()),
          ),
        );
      }
      if (winner == _OutputLimitMarker.instance) {
        await _killAndSettle(process, outputDone, drains: drains);
        throw GitOutputLimitException(limit: maxOutputBytes!);
      }

      final int exitCode = winner as int;
      final Object? drained = await Future.any<Object?>(<Future<Object?>>[
        stdoutDrain.exceeded.then((_) => _OutputLimitMarker.instance),
        outputDone.then<Object?>((_) => exitCode),
        timedOut.future.then((_) => _TimeoutMarker.instance),
      ]);
      if (drained == _OutputLimitMarker.instance) {
        await _killAndSettle(process, outputDone, drains: drains);
        throw GitOutputLimitException(limit: maxOutputBytes!);
      }
      if (drained == _TimeoutMarker.instance) {
        await _killAndSettle(process, outputDone, drains: drains);
        throw GitTimeoutException(
          timeout: timeout!,
          cause: GitCommandTimeoutException(
            arguments: request.arguments,
            workingDirectory: workingDirectory,
            stdout: _decode(stdoutBuilder.takeBytes()),
            stderr: _decode(stderrBuffer.takeBytes()),
          ),
        );
      }
      await outputDone;
      if (stdoutDrain.overflowed) {
        await _killAndSettle(process, outputDone, drains: drains);
        throw GitOutputLimitException(limit: maxOutputBytes!);
      }
      if (exitCode != 0) {
        final String stdout = _decode(stdoutBuilder.takeBytes());
        final String stderr = _decode(stderrBuffer.takeBytes());
        final GitCommandException failure = GitCommandException(
          arguments: request.arguments,
          workingDirectory: workingDirectory,
          exitCode: exitCode,
          stdout: stdout,
          stderr: stderr,
        );
        if (_isNotARepository(stderr)) {
          throw GitNotARepositoryException(cause: failure);
        }
        throw failure;
      }
      return GitRunResult(
        stdoutBytes: stdoutBuilder.takeBytes(),
        stderrBytes: stderrBuffer.takeBytes(),
      );
    } finally {
      timeoutTimer?.cancel();
    }
  }

  /// Starts the executable, racing the spawn against the allowed delay so a
  /// command is killed even when git itself takes longer to start than the
  /// delay allows.
  Future<Process> _startProcess({
    required GitRunRequest request,
    required List<String> arguments,
    required Map<String, String> environment,
    required Duration? timeout,
    required Completer<_TimeoutMarker> timedOut,
  }) async {
    final Future<Process> spawn = Process.start(
      executable,
      arguments,
      workingDirectory: request.workingDirectory,
      environment: environment,
    );
    try {
      final Object? winner = await Future.any<Object?>(<Future<Object?>>[
        spawn,
        timedOut.future.then((_) => _TimeoutMarker.instance),
      ]);
      if (winner is Process) {
        return winner;
      }
      // The delay expired while git was still starting: let the spawn
      // settle, stop the process, and report a timeout.
      final Process process = await spawn;
      await killProcessTree(
        process,
        operatingSystem: platform.operatingSystem,
      );
      throw GitTimeoutException(
        timeout: timeout!,
        cause: GitCommandTimeoutException(
          arguments: request.arguments,
          workingDirectory: request.workingDirectory,
        ),
      );
    } on ProcessException catch (error) {
      if (error.errorCode == processExecutableNotFoundErrorCode) {
        throw GitExecutableNotFoundException(executable, cause: error);
      }
      rethrow;
    }
  }

  /// Writes [stdinBytes] to the command, then closes stdin in every case so
  /// a git command reading stdin sees EOF instead of blocking forever.
  void _feedStdin(Process process, Uint8List? stdinBytes) {
    final IOSink sink = process.stdin;
    if (stdinBytes != null) {
      try {
        sink.add(stdinBytes);
      } catch (_) {
        // The process may already be gone; nothing left to feed then.
      }
    }
    unawaited(
      sink.close().catchError((Object error) {
        // Closing may fail when the process already exited; that is fine.
      }),
    );
  }

  /// Stops [process]; descendants that outlive it or detach from it may keep
  /// running. Cancels [drains] when given, then waits at most five seconds
  /// for the output streams to settle.
  Future<void> _killAndSettle(
    Process process,
    Future<void> outputDone, {
    List<_OutputDrain> drains = const <_OutputDrain>[],
  }) async {
    await killProcessTree(
      process,
      operatingSystem: platform.operatingSystem,
    );
    if (drains.isNotEmpty) {
      await Future.wait<void>(
        drains.map((_OutputDrain drain) => drain.cancel()),
      );
    }
    await outputDone.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
  }

  /// Decodes command output as UTF-8, tolerating malformed bytes.
  String _decode(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

  /// Whether git's stderr says the working directory is not a repository.
  bool _isNotARepository(String stderr) {
    return stderr.toLowerCase().contains('not a git repository');
  }
}

/// Collects one output stream through a chunk sink, with a future that
/// completes when the stream closes, fails, or the subscription is cancelled.
///
/// An optional [maxBytes] bound is enforced inside the listener: exceeding it
/// completes [exceeded] and calls `onExceeded` without throwing, so the run
/// stays in control of stopping the process.
class _OutputDrain {
  _OutputDrain(
    Stream<List<int>> stream,
    void Function(List<int>) add, {
    int? maxBytes,
    void Function()? onExceeded,
  })  : _add = add,
        _maxBytes = maxBytes,
        _onExceeded = onExceeded {
    _subscription = stream.listen(
      _collect,
      onError: (Object error, StackTrace stackTrace) {
        if (!_done.isCompleted) {
          _done.completeError(error, stackTrace);
        }
      },
      onDone: _complete,
      cancelOnError: true,
    );
  }

  final void Function(List<int>) _add;
  final int? _maxBytes;
  final void Function()? _onExceeded;
  final Completer<void> _done = Completer<void>();
  final Completer<void> _exceeded = Completer<void>();
  late final StreamSubscription<List<int>> _subscription;
  int _receivedBytes = 0;
  bool _overflowed = false;

  /// Completes when the stream closes, fails, or [cancel] is called.
  Future<void> get done => _done.future;

  /// Completes when the stream produced more than [maxBytes].
  Future<void> get exceeded => _exceeded.future;

  /// Whether the stream produced more than [maxBytes].
  bool get overflowed => _overflowed;

  void _collect(List<int> chunk) {
    if (_overflowed) {
      return;
    }
    _receivedBytes += chunk.length;
    final int? max = _maxBytes;
    if (max != null && _receivedBytes > max) {
      _overflowed = true;
      _onExceeded?.call();
      if (!_exceeded.isCompleted) {
        _exceeded.complete();
      }
      return;
    }
    _add(chunk);
  }

  /// Stops listening and completes [done]; safe once the stream closed.
  Future<void> cancel() async {
    await _subscription.cancel();
    _complete();
  }

  void _complete() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}
