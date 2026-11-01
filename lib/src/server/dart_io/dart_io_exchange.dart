import 'dart:async';

import '../git_http_headers.dart';
import '../git_http_request.dart';
import '../git_http_response.dart';
import '../git_principal.dart';
import '../git_smart_http_handler.dart';
import 'dart_io_body_decoder.dart';

/// An incoming smart HTTP request as the `dart:io` serving logic reads it.
///
/// It carries exactly what [GitHttpRequest] carries, so a transport supplies
/// the request data and the serving logic never depends on a concrete HTTP
/// framework. The `dart:io` adapter implements it on top of an `HttpRequest`;
/// tests supply their own implementation.
abstract interface class DartIoRequest implements GitHttpRequest {}

/// The outgoing side of one smart HTTP exchange.
///
/// A transport implements the four operations the serving logic needs: set
/// the response line and headers, forward the body (with backpressure), end
/// the response, or destroy the connection without ending the response.
abstract interface class DartIoResponse {
  /// Writes the status line and [headers], and configures the connection for
  /// one streamed response.
  void configure({
    required int statusCode,
    required GitHttpHeaders headers,
  });

  /// Forwards [body] to the client, respecting the backpressure of the sink.
  Future<void> addStream(Stream<List<int>> body);

  /// Ends the response after the whole body was written.
  Future<void> close();

  /// Destroys the connection without ending the response, so a truncated
  /// body is never mistaken for a complete one.
  Future<void> abort();
}

/// The transport-independent logic of [DartIoGitHttpServer].
///
/// It authenticates one request, hands it to the [GitSmartHttpHandler], and
/// writes the returned response with backpressure, cancellation and failure
/// handling. It also supplies the `dart:io` gzip decoder when the handler
/// carries none, so the adapter's behaviour can be exercised with simulated
/// requests and responses.
final class DartIoExchange<Q extends DartIoRequest> {
  /// Creates the exchange around [handler], authenticating each request with
  /// [authenticate].
  DartIoExchange({
    required GitSmartHttpHandler handler,
    required FutureOr<GitPrincipal?> Function(Q request) authenticate,
  })  : _handler = _withGzipDecoder(handler),
        _authenticate = authenticate;

  final GitSmartHttpHandler _handler;
  final FutureOr<GitPrincipal?> Function(Q request) _authenticate;

  /// Answers one request: the host authenticates it, the handler processes
  /// it, and the response is written to [response].
  Future<void> serve(Q request, DartIoResponse response) async {
    try {
      final GitPrincipal? principal = await _authenticate(request);
      final GitHttpResponse handled = await _handler.handle(
        request,
        principal: principal,
      );
      await _write(response, handled);
    } catch (_) {
      await _fail(response);
    }
  }

  /// Writes [response] to [target], forwarding the body with backpressure
  /// while the request body keeps flowing.
  ///
  /// A sink that gives up on a body that is still streaming means the client
  /// is gone: the source is released and the connection is cut, like a failed
  /// write would.
  Future<void> _write(
    DartIoResponse target,
    GitHttpResponse response,
  ) async {
    try {
      target.configure(
        statusCode: response.status,
        headers: response.headers,
      );
    } catch (_) {
      await _cancelBody(response.body);
      await _abort(target);
      return;
    }

    if (response.body is EmptyGitHttpResponseBody) {
      // A response without a body, often a refusal: close it without reading
      // a request body the client may still be sending.
      try {
        await target.close();
      } catch (_) {
        await _abort(target);
      }
      return;
    }

    final _ForwardedBody body = _ForwardedBody(response.body);
    try {
      await target.addStream(body);
    } catch (_) {
      await body.cancelSource();
      await _abort(target);
      return;
    }
    if (!body.sourceEnded) {
      await body.cancelSource();
      await _abort(target);
      return;
    }
    try {
      await target.close();
    } catch (_) {
      await _abort(target);
    }
  }

  /// Answers an internal failure that happened before the response was
  /// written.
  Future<void> _fail(DartIoResponse target) async {
    try {
      target.configure(
        statusCode: 500,
        headers: GitHttpHeaders.empty(),
      );
    } catch (_) {
      await _abort(target);
      return;
    }
    try {
      await target.close();
    } catch (_) {
      await _abort(target);
    }
  }

  /// Releases a response body nobody can consume, so the service behind it
  /// stops even though no header could be written.
  Future<void> _cancelBody(Stream<List<int>> body) async {
    try {
      final StreamSubscription<List<int>> subscription = body.listen(null);
      await subscription.cancel();
    } catch (_) {
      // The body is already released.
    }
  }

  /// Destroys the connection without ending the response.
  Future<void> _abort(DartIoResponse target) async {
    try {
      await target.abort();
    } catch (_) {
      // The connection is already gone.
    }
  }

  /// [handler] with the `dart:io` gzip decoder when it carries none.
  static GitSmartHttpHandler _withGzipDecoder(GitSmartHttpHandler handler) {
    if (handler.bodyDecoder != null) {
      return handler;
    }
    return GitSmartHttpHandler(
      resolveRepository: handler.resolveRepository,
      authorizationPolicy: handler.authorizationPolicy,
      uploadPack: handler.uploadPack,
      wwwAuthenticateChallenge: handler.wwwAuthenticateChallenge,
      bodyDecoder: dartIoGzipBodyDecoder,
      maxBodyBytes: handler.maxBodyBytes,
      maxConcurrentExchanges: handler.maxConcurrentExchanges,
      maxExchangeDuration: handler.maxExchangeDuration,
      onError: handler.onError,
    );
  }
}

/// A response body forwarded to the response sink while keeping the source
/// subscription under control.
///
/// Pausing and resuming the controller pauses and resumes the source, so the
/// pace of the connection reaches the service. Cancelling the controller
/// cancels the source; [cancelSource] also closes the controller, which
/// releases a writer waiting on a client that went away.
final class _ForwardedBody extends Stream<List<int>> {
  final Stream<List<int>> _source;
  final StreamController<List<int>> _controller = StreamController<List<int>>();
  final Completer<void> _sourceEnded = Completer<void>();
  StreamSubscription<List<int>>? _subscription;
  bool _cancelled = false;

  _ForwardedBody(this._source) {
    _controller
      ..onListen = _subscribe
      ..onPause = () {
        _subscription?.pause();
      }
      ..onResume = () {
        _subscription?.resume();
      }
      ..onCancel = _cancelSubscription;
  }

  /// Whether the source ended or failed on its own — as opposed to a
  /// consumer that stopped reading it.
  bool get sourceEnded => _sourceEnded.isCompleted;

  void _subscribe() {
    if (_cancelled) {
      return;
    }
    _subscription = _source.listen(
      _controller.add,
      onError: (Object error, StackTrace stackTrace) {
        _endSource();
        _controller.addError(error, stackTrace);
      },
      onDone: () {
        _endSource();
        _controller.close();
      },
    );
  }

  void _endSource() {
    if (!_sourceEnded.isCompleted) {
      _sourceEnded.complete();
    }
  }

  Future<void> _cancelSubscription() async {
    _cancelled = true;
    final StreamSubscription<List<int>>? subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  /// Stops forwarding the source and ends the controller, releasing a
  /// pending write.
  Future<void> cancelSource() async {
    await _cancelSubscription();
    if (!_controller.isClosed) {
      await _controller.close();
    }
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
