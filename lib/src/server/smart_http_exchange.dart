part of 'git_smart_http_handler.dart';

/// The value of the `Retry-After` header of a 503, in seconds.
const String _retryAfterSeconds = '1';

/// Thrown into the request body and the response body of a `git-upload-pack`
/// exchange whose total duration elapsed.
final class _ExchangeExpiredException implements Exception {
  /// Creates the failure for [maxDuration].
  const _ExchangeExpiredException(this.maxDuration);

  /// The configured maximum duration.
  final Duration maxDuration;

  @override
  String toString() => 'The upload-pack exchange exceeded the maximum '
      'duration of ${maxDuration.inMilliseconds} ms and was stopped.';
}

/// The concurrency slot and the total-duration timer of one accepted
/// `git-upload-pack` exchange.
///
/// [release] gives the slot back exactly once and stops the timer, whichever
/// way the exchange ends. [expired] completes once when the timer elapses;
/// the exchange stays active until it is released.
final class _Exchange {
  /// Creates the exchange and starts its timer.
  _Exchange({
    required this.maxDuration,
    required void Function() onRelease,
  }) : _onRelease = onRelease {
    _timer = Timer(maxDuration, _expire);
  }

  /// The configured maximum duration.
  final Duration maxDuration;

  final void Function() _onRelease;
  final Completer<void> _expired = Completer<void>();
  late final Timer _timer;
  bool _released = false;

  /// Completes once the total duration elapsed.
  Future<void> get expired => _expired.future;

  /// The failure reported to the service and to the response body when the
  /// duration elapsed.
  _ExchangeExpiredException get expiredError =>
      _ExchangeExpiredException(maxDuration);

  void _expire() {
    if (!_expired.isCompleted) {
      _expired.complete();
    }
  }

  /// Releases the concurrency slot and stops the timer; idempotent.
  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _timer.cancel();
    _onRelease();
  }
}

/// Takes a concurrency slot on [handler] for one upload-pack exchange, or
/// returns null when its [GitSmartHttpHandler.maxConcurrentExchanges] is
/// already reached.
_Exchange? _beginExchange(GitSmartHttpHandler handler) {
  if (handler._activeExchanges >= handler.maxConcurrentExchanges) {
    return null;
  }
  handler._activeExchanges++;
  return _Exchange(
    maxDuration: handler.maxExchangeDuration,
    onRelease: () => handler._activeExchanges--,
  );
}

/// The headers of a protocol response: its content type and no caching.
GitHttpHeaders _protocolHeaders(String contentType) {
  return GitHttpHeaders(<String, List<String>>{
    'Content-Type': <String>[contentType],
    'Cache-Control': <String>['no-cache'],
  });
}

/// The headers of a 503: no caching, and a retry delay.
GitHttpHeaders _retryAfterHeaders() {
  return GitHttpHeaders(<String, List<String>>{
    'Retry-After': <String>[_retryAfterSeconds],
    'Cache-Control': <String>['no-cache'],
  });
}

/// Waits for the service call of [exchange], failing with
/// [_ExchangeExpiredException] when the total duration elapses first.
///
/// A response that arrives after the expiry is cancelled, so a service that
/// already launched a process releases it even though nobody consumes its
/// body.
Future<GitServiceResponse> _awaitService(
  Future<GitServiceResponse> service,
  _Exchange exchange,
) {
  final Completer<GitServiceResponse> result = Completer<GitServiceResponse>();
  service.then(
    (GitServiceResponse response) {
      if (result.isCompleted) {
        unawaited(_cancelQuietly(response));
      } else {
        result.complete(response);
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!result.isCompleted) {
        result.completeError(error, stackTrace);
      }
    },
  );
  exchange.expired.then((_) {
    if (!result.isCompleted) {
      result.completeError(exchange.expiredError, StackTrace.current);
    }
  });
  return result.future;
}

/// Cancels [response], ignoring a release failure: the exchange is already
/// being abandoned.
Future<void> _cancelQuietly(GitServiceResponse response) async {
  try {
    await response.cancel();
  } catch (_) {
    // The service is gone or already released.
  }
}
