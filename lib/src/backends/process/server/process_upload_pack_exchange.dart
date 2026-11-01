import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_process_launcher.dart';

/// The response of one launched upload-pack process.
///
/// The body is the process standard output, subscribed only when the
/// consumer listens to it and delivered only as fast as that listening
/// reads it. The incoming request body, when one is pumped, is written to
/// the process standard input with backpressure, split into pieces of at
/// most the configured buffer so no oversized chunk is ever held. The
/// standard error is read eagerly and kept within the same bound; it never
/// reaches the body.
///
/// Every stop kills the process, stops reading the request body and
/// releases everything: [cancel], the end of the body subscription, the
/// expiry of the inactivity delay — a response never listened to included —
/// a failing request body, a broken pipe. A process that exits with a
/// non-zero code after the body started becomes an error of the body.
final class ProcessUploadPackExchange implements GitServiceResponse {
  final GitLaunchedProcess _process;
  final List<String> _arguments;
  final Duration _inactivityTimeout;
  final int _bufferBytes;

  final StreamController<List<int>> _body = StreamController<List<int>>();
  final BytesBuilder _stderr = BytesBuilder(copy: false);
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  StreamIterator<List<int>>? _requestIterator;
  Timer? _idleTimer;
  bool _listened = false;
  bool _bodyEnded = false;
  bool _tornDown = false;

  /// Creates the exchange over [process], which was launched with
  /// [arguments]; [inactivityTimeout] releases an exchange no byte moves
  /// in, and [bufferBytes] bounds the memory held for it.
  ProcessUploadPackExchange({
    required GitLaunchedProcess process,
    required List<String> arguments,
    required Duration inactivityTimeout,
    required int bufferBytes,
  })  : _process = process,
        _arguments = List<String>.unmodifiable(arguments),
        _inactivityTimeout = inactivityTimeout,
        _bufferBytes = bufferBytes {
    _body
      ..onListen = () {
        _listened = true;
        _readStdout();
      }
      ..onPause = () {
        _stdoutSubscription?.pause();
      }
      ..onResume = () {
        _stdoutSubscription?.resume();
      }
      ..onCancel = () async {
        _listened = false;
        final StreamSubscription<List<int>>? subscription = _stdoutSubscription;
        _stdoutSubscription = null;
        await subscription?.cancel();
        await cancel();
      };
    _readStderr();
    _touch();
  }

  /// The standard output of the process, produced only while a consumer
  /// reads it.
  @override
  Stream<List<int>> get body => _body.stream;

  /// Writes [request] into the process standard input, only as fast as the
  /// process takes the bytes, and closes it at the end of the request.
  ///
  /// A request that fails, or a pipe the process closed early, kills the
  /// process and ends the body with an error — unless the exchange was
  /// already being torn down, in which case the body is being released.
  Future<void> pumpRequest(Stream<List<int>> request) async {
    final StreamIterator<List<int>> iterator = StreamIterator<List<int>>(
      request,
    );
    _requestIterator = iterator;
    try {
      while (await iterator.moveNext()) {
        if (_tornDown) {
          return;
        }
        final List<int> chunk = iterator.current;
        var offset = 0;
        while (offset < chunk.length) {
          final int end = (offset + _bufferBytes) < chunk.length
              ? offset + _bufferBytes
              : chunk.length;
          _touch();
          await _process.writeStdin(chunk.sublist(offset, end));
          if (_tornDown) {
            return;
          }
          offset = end;
        }
      }
      _touch();
      await _process.closeStdin();
    } catch (error) {
      if (!_tornDown) {
        await _teardown();
        _endBodyWithError(
          GitException('the request body of git upload-pack failed: $error'),
        );
      }
    } finally {
      _requestIterator = null;
      await iterator.cancel();
    }
  }

  /// Kills the process and stops the reading of the request body;
  /// completes when the process is gone. Calling it more than once is
  /// allowed.
  @override
  Future<void> cancel() async {
    await _teardown();
    _endBodyQuietly();
  }

  /// Restarts the inactivity delay.
  void _touch() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_inactivityTimeout, _onIdle);
  }

  /// No byte moved in either direction for the whole delay: the process is
  /// dead weight — kill it, and fail the body when a consumer reads it.
  Future<void> _onIdle() async {
    _idleTimer = null;
    await _teardown();
    _endBodyWithError(
      GitException(
        'git upload-pack was idle for '
        '${_inactivityTimeout.inMilliseconds} ms and was killed',
      ),
    );
  }

  /// Subscribes to the standard output — the body is being listened to.
  void _readStdout() {
    if (_stdoutSubscription != null) {
      return;
    }
    _touch();
    _stdoutSubscription = _process.stdout.listen(
      (List<int> chunk) {
        _touch();
        _body.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        _touch();
        unawaited(_teardown().then((_) => _endBodyWithError(error)));
      },
      onDone: () {
        _touch();
        unawaited(_finishAfterStdout());
      },
    );
  }

  /// The standard output reached its end: a clean end of body for a zero
  /// exit, an error carrying what git explained on standard error
  /// otherwise.
  Future<void> _finishAfterStdout() async {
    final int exitCode = await _process.exitCode;
    if (exitCode == 0) {
      _endBodyQuietly();
      return;
    }
    await _teardown();
    _endBodyWithError(GitCommandException(
      arguments: _arguments,
      exitCode: exitCode,
      stderr: utf8.decode(_stderr.takeBytes(), allowMalformed: true),
    ));
  }

  /// Drains the standard error eagerly so git never blocks writing it,
  /// keeping at most the configured buffer of it.
  void _readStderr() {
    _stderrSubscription = _process.stderr.listen(
      (List<int> chunk) {
        _touch();
        if (_stderr.length < _bufferBytes) {
          final int room = _bufferBytes - _stderr.length;
          _stderr.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
        }
      },
      onError: (Object error) {
        _touch();
        unawaited(_teardown().then((_) => _endBodyWithError(error)));
      },
      onDone: _touch,
    );
  }

  /// Kills the process and stops every reading. Idempotent; completes when
  /// the process is gone.
  Future<void> _teardown() async {
    if (_tornDown) {
      return;
    }
    _tornDown = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    await _requestIterator?.cancel();
    _requestIterator = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    await _process.kill();
  }

  /// Ends the body without an error, once, when a consumer reads it.
  void _endBodyQuietly() {
    if (_bodyEnded || !_listened) {
      return;
    }
    _bodyEnded = true;
    _body.close();
  }

  /// Ends the body with [error], once, when a consumer reads it.
  void _endBodyWithError(Object error) {
    if (_bodyEnded || !_listened) {
      return;
    }
    _bodyEnded = true;
    _body.addError(error, StackTrace.current);
    _body.close();
  }
}
