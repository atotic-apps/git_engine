import 'dart:async';

import 'git_http_headers.dart';

/// A response a handler produced, independent of any HTTP framework.
///
/// The transport adapter reads the status and headers, then writes the body
/// at its own pace: the body stream is produced only as fast as the adapter
/// consumes it. Cancelling the body stream releases the whole chain behind
/// the response.
///
/// Host applications consume this type; the library produces it.
/// {@category Server}
abstract interface class GitHttpResponse {
  /// HTTP status code.
  int get status;

  /// Response headers, multi-valued and case-insensitive.
  GitHttpHeaders get headers;

  /// The response body, as bytes.
  Stream<List<int>> get body;
}

/// The body of a response that carries no byte, such as a refusal or an
/// empty status.
///
/// A transport can recognize it and send the status line and headers without
/// waiting for a request body the client is still sending. It is an internal
/// detail of the server layer, not part of the public API.
final class EmptyGitHttpResponseBody extends Stream<List<int>> {
  /// Creates the empty body.
  const EmptyGitHttpResponseBody();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return const Stream<List<int>>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
