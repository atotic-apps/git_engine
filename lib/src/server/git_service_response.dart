/// Response stream of a server service, transport independent.
///
/// A service produces the body only as fast as its consumer reads it, and
/// holds no more memory than a buffer independent of the body size.
///
/// The body is single-subscription: whoever receives a [GitServiceResponse]
/// listens to [body] until it completes, or calls [cancel] to stop early.
/// Cancelling releases the whole chain behind the response — the reading of
/// an incoming request body, a git process and its resources. A response
/// abandoned without being listened to at all is released by the service
/// itself, after its own inactivity delay.
///
/// This is a capability contract: backends implement it, and it only grows
/// through a new interface in a major version.
/// {@category Server}
/// {@category Compatibility}
abstract interface class GitServiceResponse {
  /// The response body. Single-subscription, produced at the pace of the
  /// consumer.
  Stream<List<int>> get body;

  /// Releases every resource behind this response. Completes when the
  /// release is done; calling it more than once is allowed.
  Future<void> cancel();
}
