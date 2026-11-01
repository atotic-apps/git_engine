import 'dart:async';
import 'dart:io';

import '../git_http_headers.dart';
import '../git_http_request.dart';
import '../git_principal.dart';
import '../git_smart_http_handler.dart';
import 'dart_io_exchange.dart';

/// Smart HTTP server over `dart:io`'s [HttpServer].
///
/// This is the only transport adapter of the server layer, and its folder is
/// the only place of that layer that imports `dart:io`. It is deliberately
/// thin: it converts each [HttpRequest] into a [GitHttpRequest] without
/// decoding the path and without decompressing the body, hands it to a
/// [GitSmartHttpHandler], and writes the returned response back.
///
/// ## What the server does
///
/// - It passes the request path exactly as received (still percent-encoded)
///   and the request body as a byte stream, so the processing decodes the
///   path and applies the body decoder itself.
/// - When the handler carries no body decoder, the server supplies
///   [dartIoGzipBodyDecoder], so `gzip`-compressed request bodies are read
///   out of the box.
/// - The request body and the response body flow at the same time: the
///   response is written through the HTTP response, which reads the service
///   only as fast as the socket accepts the bytes, while the request body
///   keeps being read at the pace its consumer set. Neither direction waits
///   for the other, and memory stays bounded in both.
/// - When the response body fails mid-flight, it destroys the connection
///   instead of ending the chunked stream, so the client never mistakes a
///   truncated body for a complete one.
/// - When the client disconnects, it cancels the response, which releases the
///   service and the git process behind it.
/// - One connection carries one exchange: the connection closes after the
///   response.
/// - The concurrency and duration limits are the handler's; the adapter only
///   carries requests and destroys a connection whose response fails.
///
/// ## Authentication
///
/// Authentication belongs to the host application. The server receives an
/// [authenticate] callback that reads the [HttpRequest] and returns the
/// [GitPrincipal] the host authenticated, or null for an anonymous request.
/// The server never inspects credentials itself.
/// {@category Server}
final class DartIoGitHttpServer {
  final HttpServer _server;
  final DartIoExchange<_DartIoGitHttpRequest> _exchange;

  DartIoGitHttpServer._(this._server, this._exchange) {
    unawaited(_accept());
  }

  /// Binds a server on [address] and [port], and starts answering smart HTTP
  /// requests with [handler].
  ///
  /// [address] defaults to the loopback address and [port] to 0, which lets
  /// the operating system choose a free port; read it from [port]. [shared]
  /// asks the operating system to allow several servers on the same port.
  ///
  /// [authenticate] is called for every request, before the handler runs, and
  /// returns the identity the host authenticated, or null for an anonymous
  /// request.
  static Future<DartIoGitHttpServer> bind({
    required GitSmartHttpHandler handler,
    required FutureOr<GitPrincipal?> Function(HttpRequest request) authenticate,
    InternetAddress? address,
    int port = 0,
    bool shared = false,
  }) async {
    final HttpServer server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
      shared: shared,
    );
    return DartIoGitHttpServer._(
      server,
      DartIoExchange<_DartIoGitHttpRequest>(
        handler: handler,
        authenticate: (_DartIoGitHttpRequest request) =>
            authenticate(request.raw),
      ),
    );
  }

  /// The address the server listens on.
  InternetAddress get address => _server.address;

  /// The port the server listens on; the effective port when [bind] was
  /// given 0.
  int get port => _server.port;

  /// Stops accepting requests and closes the server.
  ///
  /// [force] closes the connections that are still open instead of waiting
  /// for their responses to end.
  Future<void> close({bool force = false}) => _server.close(force: force);

  /// Answers the requests until the server closes.
  Future<void> _accept() async {
    try {
      await for (final HttpRequest request in _server) {
        unawaited(_serve(request));
      }
    } catch (_) {
      // Closing the server ends the request stream.
    }
  }

  /// Answers one request through the transport-independent exchange logic.
  Future<void> _serve(HttpRequest request) {
    return _exchange.serve(
      _DartIoGitHttpRequest(request),
      _DartIoGitHttpResponse(request.response),
    );
  }
}

/// The request built from a `dart:io` [HttpRequest]: the body is the request
/// stream itself, delivered as the processing reads it.
final class _DartIoGitHttpRequest implements DartIoRequest {
  final HttpRequest raw;

  _DartIoGitHttpRequest(this.raw);

  @override
  String get method => raw.method;

  /// The path as received, still percent-encoded: `Uri.path` keeps the
  /// escapes, so the handler is the only one to decode them.
  @override
  String get path => raw.uri.path;

  @override
  Map<String, List<String>> get queryParameters => raw.uri.queryParametersAll;

  @override
  GitHttpHeaders get headers {
    final Map<String, List<String>> values = <String, List<String>>{};
    raw.headers.forEach((String name, List<String> headerValues) {
      values[name] = List<String>.of(headerValues);
    });
    return GitHttpHeaders(values);
  }

  @override
  Stream<List<int>> get body => raw;
}

/// The response sink built from a `dart:io` [HttpResponse].
final class _DartIoGitHttpResponse implements DartIoResponse {
  final HttpResponse _response;
  bool _wroteBody = false;

  _DartIoGitHttpResponse(this._response);

  @override
  void configure({
    required int statusCode,
    required GitHttpHeaders headers,
  }) {
    _response.bufferOutput = false;
    _response.statusCode = statusCode;
    headers.toMap().forEach((String name, List<String> values) {
      if (values.isNotEmpty) {
        _response.headers.set(name, values);
      }
    });
    _response.headers.chunkedTransferEncoding = true;
    _response.persistentConnection = false;
  }

  @override
  Future<void> addStream(Stream<List<int>> body) {
    return _response.addStream(body.map((List<int> chunk) {
      if (chunk.isNotEmpty) {
        _wroteBody = true;
      }
      return chunk;
    }));
  }

  @override
  Future<void> close() async {
    if (_wroteBody) {
      await _response.close();
      return;
    }
    try {
      // No body was written: send a zero-length response and close the
      // connection instead of waiting for the client to finish a request
      // body nobody reads.
      _response.headers.chunkedTransferEncoding = false;
      _response.contentLength = 0;
      final Socket socket = await _response.detachSocket(writeHeaders: true);
      socket.destroy();
    } catch (_) {
      try {
        await _response.close();
      } catch (_) {
        // The connection is already gone.
      }
    }
  }

  @override
  Future<void> abort() async {
    try {
      final Socket socket = await _response.detachSocket(writeHeaders: false);
      socket.destroy();
    } catch (_) {
      // The connection is already gone.
    }
  }
}
