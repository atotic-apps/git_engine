import 'git_http_headers.dart';

/// A request received by a transport adapter, independent of any HTTP
/// framework.
///
/// The adapter — a thin shell over `dart:io`'s `HttpServer`, shelf or
/// another host — builds it from what the client sent and hands it to a
/// handler such as `GitSmartHttpHandler`. The body stays a byte stream: the
/// adapter never buffers it.
///
/// This is a capability contract: host applications implement it, and it only
/// grows through a new interface in a major version.
/// {@category Server}
/// {@category Compatibility}
abstract interface class GitHttpRequest {
  /// Request method, upper case (`GET`, `POST`).
  String get method;

  /// Request path as received, still percent-encoded, without the query.
  ///
  /// The handler is the only one to decode it.
  String get path;

  /// Query parameters, names and values percent-decoded, keeping every
  /// value of every name.
  Map<String, List<String>> get queryParameters;

  /// Request headers, multi-valued and case-insensitive.
  GitHttpHeaders get headers;

  /// The request body, as bytes, read only as fast as its consumer reads
  /// it.
  Stream<List<int>> get body;
}
