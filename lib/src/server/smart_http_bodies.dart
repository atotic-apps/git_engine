part of 'git_smart_http_handler.dart';

/// The smart HTTP framing of a reference advertisement: the pkt-line
/// `# service=git-upload-pack` followed by a flush-pkt. ASCII only, so the
/// UTF-16 code units are the bytes.
final List<int> _advertisementPrefix = <int>[
  ...'001e# service=git-upload-pack\n'.codeUnits,
  ...'0000'.codeUnits,
];

/// Thrown when the request path cannot be decoded unambiguously.
final class _MalformedRequestException implements Exception {
  final String reason;

  _MalformedRequestException(this.reason);

  @override
  String toString() => 'Malformed request: $reason';
}

/// Reported to the service and to the host error callback when the request
/// body grows past the configured limit while it streams.
final class _RequestBodyTooLargeException implements Exception {
  final int limitBytes;

  _RequestBodyTooLargeException(this.limitBytes);

  @override
  String toString() => 'Request body exceeded the limit of $limitBytes bytes.';
}

/// Reported to the service when the HTTP response was cancelled and the
/// handler stopped feeding the request body.
final class _ResponseCancelledException implements Exception {
  @override
  String toString() => 'The HTTP response was cancelled.';
}

/// A body forwarded to a service through a controller the handler controls:
/// [interrupt] stops pulling from the source and reports an error to the
/// consumer, so a cancelled response cuts the whole reading chain even when
/// the consumer keeps listening.
final class _InterruptibleBody extends Stream<List<int>> {
  final Stream<List<int>> _source;
  final StreamController<List<int>> _controller = StreamController<List<int>>();
  StreamSubscription<List<int>>? _subscription;
  bool _interrupted = false;

  _InterruptibleBody(this._source) {
    _controller
      ..onListen = () {
        if (_interrupted) {
          return;
        }
        _subscription = _source.listen(
          _controller.add,
          onError: _controller.addError,
          onDone: _controller.close,
        );
      }
      ..onPause = () {
        _subscription?.pause();
      }
      ..onResume = () {
        _subscription?.resume();
      }
      ..onCancel = () async {
        final StreamSubscription<List<int>>? subscription = _subscription;
        _subscription = null;
        await subscription?.cancel();
      };
  }

  /// Cancels the source and reports [error] to the consumer of this body.
  ///
  /// When the body already ended or was cancelled, the consumer is gone and
  /// the call only makes sure the source is cut.
  void interrupt(Object error, StackTrace stackTrace) {
    _interrupted = true;
    final StreamSubscription<List<int>>? subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      subscription.cancel();
    }
    if (_controller.isClosed) {
      return;
    }
    _controller.addError(error, stackTrace);
    _controller.close();
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

/// A body that fails once more than [maxBytes] bytes have crossed it, so a
/// body is only ever read up to the configured limit.
final class _LimitedBody extends Stream<List<int>> {
  final Stream<List<int>> _source;
  final int maxBytes;
  final StreamController<List<int>> _controller = StreamController<List<int>>();
  StreamSubscription<List<int>>? _subscription;

  _LimitedBody(this._source, this.maxBytes) {
    _controller
      ..onListen = () {
        var total = 0;
        _subscription = _source.listen(
          (List<int> chunk) {
            total += chunk.length;
            if (total > maxBytes) {
              final Object error = _RequestBodyTooLargeException(maxBytes);
              final StackTrace stackTrace = StackTrace.current;
              _subscription?.cancel();
              _subscription = null;
              _controller.addError(error, stackTrace);
              _controller.close();
            } else {
              _controller.add(chunk);
            }
          },
          onError: _controller.addError,
          onDone: _controller.close,
        );
      }
      ..onPause = () {
        _subscription?.pause();
      }
      ..onResume = () {
        _subscription?.resume();
      }
      ..onCancel = () async {
        final StreamSubscription<List<int>>? subscription = _subscription;
        _subscription = null;
        await subscription?.cancel();
      };
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

/// The body of an HTTP response, backed by a [GitServiceResponse].
///
/// The service body is forwarded only as fast as the adapter consumes it.
/// Cancelling this body cancels the service response and runs [onCancel],
/// which cuts the incoming request body in turn. [prefix], when given, is
/// emitted before the service body: it carries the smart HTTP framing of a
/// reference advertisement. An error of the service body interrupts this
/// body — it ends with the error, never with a valid end of stream — and is
/// reported to [onFirstError] for logging; it is never turned into body
/// content. When [exchange] is given, the body holds its concurrency slot
/// until it ends, fails or is cancelled, and the expiry of its total duration
/// interrupts it while cancelling the service.
final class _ResponseBody extends Stream<List<int>> {
  final GitServiceResponse _response;
  final List<int> _prefix;
  final void Function()? _onCancel;
  final void Function(Object error, StackTrace stackTrace)? _onFirstError;
  final _Exchange? _exchange;
  final StreamController<List<int>> _controller = StreamController<List<int>>();
  StreamSubscription<List<int>>? _subscription;
  bool _finished = false;

  _ResponseBody(
    this._response, {
    List<int> prefix = const <int>[],
    void Function()? onCancel,
    void Function(Object error, StackTrace stackTrace)? onFirstError,
    _Exchange? exchange,
  })  : _prefix = prefix,
        _onCancel = onCancel,
        _onFirstError = onFirstError,
        _exchange = exchange {
    _controller
      ..onListen = () {
        if (_prefix.isNotEmpty) {
          _controller.add(_prefix);
        }
        _subscription = _response.body.listen(
          _controller.add,
          onError: (Object error, StackTrace stackTrace) {
            _onFirstError?.call(error, stackTrace);
            _finish();
            _controller.addError(error, stackTrace);
            _controller.close();
          },
          onDone: () {
            _finish();
            _controller.close();
          },
        );
      }
      ..onPause = () {
        _subscription?.pause();
      }
      ..onResume = () {
        _subscription?.resume();
      }
      ..onCancel = () async {
        final StreamSubscription<List<int>>? subscription = _subscription;
        _subscription = null;
        if (subscription != null) {
          await subscription.cancel();
        }
        await _response.cancel();
        _onCancel?.call();
        _finish();
      };
    _exchange?.expired.then((_) => _expire());
  }

  /// Releases the concurrency slot, once.
  void _finish() {
    if (_finished) {
      return;
    }
    _finished = true;
    _exchange?.release();
  }

  /// The total duration elapsed while streaming: cancel the service, cut the
  /// request body, release the slot and end the body with the failure.
  Future<void> _expire() async {
    if (_finished) {
      return;
    }
    _finished = true;
    final StreamSubscription<List<int>>? subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
    await _response.cancel();
    _onCancel?.call();
    _exchange?.release();
    if (_controller.isClosed) {
      return;
    }
    _controller.addError(
      _exchange!.expiredError,
      StackTrace.current,
    );
    await _controller.close();
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
