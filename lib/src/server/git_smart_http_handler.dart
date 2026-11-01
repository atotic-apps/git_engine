import 'dart:async';

import 'git_authorization_policy.dart';
import 'git_http_headers.dart';
import 'git_http_request.dart';
import 'git_http_response.dart';
import 'git_principal.dart';
import 'git_protocol_parameters.dart';
import 'git_served_repository_id.dart';
import 'git_service_response.dart';
import 'git_unknown_served_repository_exception.dart';
import 'git_upload_pack_service.dart';

part 'smart_http_bodies.dart';
part 'smart_http_exchange.dart';
part 'smart_http_routing.dart';

/// Decompresses a request body carrying a `Content-Encoding`.
///
/// The transport adapter supplies the decoder — the `dart:io` adapter
/// supplies the gzip of `dart:io` — and returns null for an encoding it does
/// not support, which the handler reports as 415. The handler applies it
/// exactly once per request, on the encoded body, and only when the request
/// carries a `Content-Encoding` other than `identity`.
/// {@category Server}
typedef GitHttpBodyDecoder = Stream<List<int>>? Function(
  String contentEncoding,
  Stream<List<int>> body,
);

const String _infoRefsSuffix = '/info/refs';
const String _uploadPackSuffix = '/git-upload-pack';
const String _receivePackSuffix = '/git-receive-pack';
const String _uploadPackServiceName = 'git-upload-pack';
const String _advertisementContentType =
    'application/x-git-upload-pack-advertisement';
const String _requestContentType = 'application/x-git-upload-pack-request';
const String _resultContentType = 'application/x-git-upload-pack-result';

/// Smart HTTP processing for the server layer: routes the smart HTTP
/// requests of a read-only service to a [GitUploadPackService], and
/// translates service outcomes into HTTP responses.
///
/// ## What the host supplies
///
/// The host maps URLs to repositories itself: [resolveRepository] receives
/// the percent-decoded path segments and returns the
/// [GitServedRepositoryId], or null when no repository is served there. It
/// authenticates requests itself and passes the resulting [GitPrincipal] to
/// [handle] (null = anonymous). [authorizationPolicy] then decides whether
/// the identity may read the repository. [wwwAuthenticateChallenge], when
/// given, is sent as the `WWW-Authenticate` header of a 401. [bodyDecoder],
/// when given, decompresses request bodies; [maxBodyBytes] bounds a request
/// body both as received and after decompression (413 beyond); [onError]
/// receives the errors that interrupt a response after its headers were sent.
///
/// ## Limits
///
/// The handler bounds the number and the duration of the `git-upload-pack`
/// exchanges it accepts, for every transport adapter. Every call to the
/// service is an exchange, the reference advertisement of the `GET` as well
/// as the stateless RPC of the `POST`: a clone or a fetch chains one
/// advertisement then one or more `POST`s, each holding a slot for as long as
/// its own response lasts.
///
/// - [maxConcurrentExchanges] caps the exchanges active at once. An exchange
///   is active from the acceptance of its request until its response body
///   ends, fails, or is cancelled. A request beyond the cap receives 503 with
///   `Retry-After`; the service is not called and its body is not read.
/// - [maxExchangeDuration] caps the duration of one exchange, measured from
///   its acceptance. When it elapses, the handler cancels the service — which
///   stops the git process in the process backend, though descendants that
///   outlive it may keep running — and interrupts the response. While the
///   service has not produced its response, no header could have been sent and
///   the answer is 503 with `Retry-After`; once the response was handed to the
///   adapter, the body ends with an error and the adapter destroys the
///   connection, so a truncated body is never mistaken for a complete one. The
///   duration adds to the service's own inactivity delay, which keeps its
///   meaning.
///
/// The concurrency slot is released on every path: normal end, error, client
/// disconnect and expiry. A malformed request, an unknown repository and an
/// authorization refusal are decided before any slot is taken, so they never
/// occupy one. These limits are global to the handler; per-client or
/// per-address limits belong to the host, which receives the
/// [GitPrincipal] on each [handle] call.
///
/// ## What it routes
///
/// - `GET <path>/info/refs?service=git-upload-pack` — the first response of
///   a fetch: the body of the service's [GitUploadPackService.advertiseRefs]
///   framed with the `# service=git-upload-pack` pkt-line, with the
///   `application/x-git-upload-pack-advertisement` content type;
/// - `POST <path>/git-upload-pack` — one stateless RPC: the service's
///   [GitUploadPackService.uploadPack], with the
///   `application/x-git-upload-pack-request` request content type required
///   and the `application/x-git-upload-pack-result` response content type;
/// - `POST <path>/git-receive-pack` and `?service=git-receive-pack` are
///   refused with 403 while the server is read-only.
///
/// Every response carries `Cache-Control: no-cache`. The protocol version is
/// negotiated from the `Git-Protocol` header and passed to the service as
/// [GitProtocolParameters].
///
/// ## Errors
///
/// - 404: [resolveRepository] returned null, or the service's own
///   resolution refused the identifier as unknown
///   ([GitUnknownServedRepositoryException]);
/// - 401: an anonymous request was refused by the policy, with the
///   configured `WWW-Authenticate` challenge; without a configured
///   challenge the refusal is a 403;
/// - 403: an authenticated identity was refused, or the service is unknown
///   or disabled — in particular `git-receive-pack` during the read-only
///   phase;
/// - 400: a malformed request — no protocol suffix in the path, a method
///   that does not fit the suffix, an ambiguous path (empty segment, `.`,
///   `..`, an encoded `/` or NUL character, a broken percent-escape), the
///   dumb protocol (`info/refs` without `service=`), a wrong `Content-Type`
///   on the RPC endpoint, or an unparsable `Content-Length`;
/// - 413: `Content-Length` beyond [maxBodyBytes]; a body that grows past
///   the limit while it streams — as received or after decompression —
///   fails mid-flight instead, after the headers;
/// - 415: a `Content-Encoding` other than `identity` with no decoder or a
///   decoder that refuses it;
/// - 503: [maxConcurrentExchanges] reached, or [maxExchangeDuration] expired
///   before the service produced its response — so before any header was
///   sent — with a `Retry-After` header;
/// - 500: an internal error before the headers were sent, never carrying
///   the service's own error output.
///
/// After the response headers were sent, an error interrupts the response —
/// the body stream ends with that error, which is not body content — and is
/// reported to [onError] for logging; it never reaches the client as body.
///
/// ## Memory and backpressure
///
/// A request body is never held whole in memory: it is read only as fast as
/// the service consumes it, the size limit counts bytes as they cross both
/// before and after decompression, and a decompression is applied as a
/// stream. The response body is produced only as fast as the adapter writes
/// it, and cancelling it stops the service and the reading of the request
/// body.
/// {@category Server}
final class GitSmartHttpHandler {
  /// Maps decoded path segments to a served repository: an asynchronous or
  /// synchronous function returning the [GitServedRepositoryId], or null
  /// when no repository is served there (404).
  ///
  /// It never receives the encoded path and no path is ever built from it.
  final FutureOr<GitServedRepositoryId?> Function(List<String> segments)
      resolveRepository;

  /// Decides whether the authenticated identity may read the repository.
  final GitAuthorizationPolicy authorizationPolicy;

  /// The service that answers the fetch protocol.
  final GitUploadPackService uploadPack;

  /// The value of the `WWW-Authenticate` header sent with a 401; without
  /// one, the refusal of an anonymous request is a 403.
  final String? wwwAuthenticateChallenge;

  /// Decompresses request bodies; without it, a compressed request receives
  /// 415. See [GitHttpBodyDecoder].
  final GitHttpBodyDecoder? bodyDecoder;

  /// The largest request body accepted, in bytes, both as received and after
  /// decompression: a larger `Content-Length` receives 413; a body that grows
  /// past it while it streams fails mid-flight instead.
  final int maxBodyBytes;

  /// Receives the errors that interrupt a response after its headers were
  /// sent, for logging. Never called with an error the client receives as
  /// body.
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// The largest number of `git-upload-pack` exchanges that may be active at
  /// once; beyond it, the request receives 503 with `Retry-After`.
  ///
  /// An exchange is active from the acceptance of its request until its
  /// response body ends, fails or is cancelled. The count is global to this
  /// handler: per-client or per-address limits belong to the host, which
  /// receives the [GitPrincipal] on each [handle] call.
  final int maxConcurrentExchanges;

  /// The longest duration of one `git-upload-pack` exchange, measured from
  /// its acceptance; it adds to the service's own inactivity delay.
  ///
  /// When it elapses, the service is cancelled — stopping the git process in
  /// the process backend, though descendants that outlive it may keep
  /// running — and the response is interrupted.
  final Duration maxExchangeDuration;

  int _activeExchanges = 0;

  /// Creates the handler.
  ///
  /// [maxBodyBytes], [maxConcurrentExchanges] and [maxExchangeDuration] must
  /// be positive; every other member is documented on the class.
  GitSmartHttpHandler({
    required this.resolveRepository,
    required this.authorizationPolicy,
    required this.uploadPack,
    this.wwwAuthenticateChallenge,
    this.bodyDecoder,
    required this.maxBodyBytes,
    this.maxConcurrentExchanges = 32,
    this.maxExchangeDuration = const Duration(minutes: 10),
    this.onError,
  }) {
    if (maxBodyBytes <= 0) {
      throw ArgumentError.value(
        maxBodyBytes,
        'maxBodyBytes',
        'must be positive',
      );
    }
    if (maxConcurrentExchanges <= 0) {
      throw ArgumentError.value(
        maxConcurrentExchanges,
        'maxConcurrentExchanges',
        'must be positive',
      );
    }
    if (maxExchangeDuration <= Duration.zero) {
      throw ArgumentError.value(
        maxExchangeDuration,
        'maxExchangeDuration',
        'must be positive',
      );
    }
  }

  /// Handles one request and returns the response whose headers are ready;
  /// the body then streams at the pace of the adapter.
  ///
  /// [principal] is the identity the host authenticated for this request, or
  /// null for an anonymous one.
  Future<GitHttpResponse> handle(
    GitHttpRequest request, {
    GitPrincipal? principal,
  }) async {
    try {
      return await _process(request, principal);
    } on _MalformedRequestException {
      return _statusResponse(400);
    } catch (_) {
      return _statusResponse(500);
    }
  }

  Future<GitHttpResponse> _process(
    GitHttpRequest request,
    GitPrincipal? principal,
  ) async {
    final String path = request.path;
    final String suffix = _protocolSuffix(path);
    if (suffix == _receivePackSuffix) {
      return _statusResponse(403);
    }
    if (suffix == _infoRefsSuffix) {
      if (request.method != 'GET') {
        throw _MalformedRequestException('info/refs requires GET');
      }
      final List<String>? serviceValues = request.queryParameters['service'];
      final String? service = serviceValues == null || serviceValues.isEmpty
          ? null
          : serviceValues.first;
      if (service == null || service.isEmpty) {
        throw _MalformedRequestException(
          'info/refs without service= is the dumb protocol',
        );
      }
      if (service != _uploadPackServiceName) {
        return _statusResponse(403);
      }
    } else {
      if (request.method != 'POST') {
        throw _MalformedRequestException(
          'git-upload-pack requires POST',
        );
      }
      final String? contentType =
          request.headers.firstValue('content-type')?.trim();
      if (contentType == null ||
          contentType.toLowerCase() != _requestContentType) {
        throw _MalformedRequestException(
          'git-upload-pack requires the $_requestContentType content type',
        );
      }
    }

    final List<String> segments = _decodeSegments(
      path.substring(0, path.length - suffix.length),
    );
    final GitServedRepositoryId? repository = await resolveRepository(segments);
    if (repository == null) {
      return _statusResponse(404);
    }
    if (!await authorizationPolicy.canRead(principal, repository)) {
      if (principal == null && wwwAuthenticateChallenge != null) {
        return _statusResponse(
          401,
          headers: GitHttpHeaders(<String, List<String>>{
            'WWW-Authenticate': <String>[wwwAuthenticateChallenge!],
          }),
        );
      }
      return _statusResponse(403);
    }

    final GitProtocolParameters protocol = _protocolParameters(
      request.headers,
    );
    if (suffix == _infoRefsSuffix) {
      final _Exchange? exchange = _beginExchange(this);
      if (exchange == null) {
        return _statusResponse(503, headers: _retryAfterHeaders());
      }
      final GitServiceResponse serviceResponse;
      try {
        serviceResponse = await _awaitService(
          uploadPack.advertiseRefs(repository, protocol: protocol),
          exchange,
        );
      } on _ExchangeExpiredException {
        exchange.release();
        return _statusResponse(503, headers: _retryAfterHeaders());
      } on GitUnknownServedRepositoryException {
        exchange.release();
        return _statusResponse(404);
      } catch (_) {
        exchange.release();
        return _statusResponse(500);
      }
      return _GitHttpResponse(
        200,
        _protocolHeaders(_advertisementContentType),
        _ResponseBody(
          serviceResponse,
          prefix: _advertisementPrefix,
          exchange: exchange,
          onFirstError: onError,
        ),
      );
    }

    final String? contentLength =
        request.headers.firstValue('content-length')?.trim();
    if (contentLength != null && contentLength.isNotEmpty) {
      final int? length = int.tryParse(contentLength);
      if (length == null || length < 0) {
        throw _MalformedRequestException(
          'unparsable Content-Length: $contentLength',
        );
      }
      if (length > maxBodyBytes) {
        return _statusResponse(413);
      }
    }

    Stream<List<int>> body = _LimitedBody(request.body, maxBodyBytes);
    final String? encoding =
        request.headers.firstValue('content-encoding')?.trim();
    if (encoding != null && encoding.isNotEmpty) {
      if (encoding.toLowerCase() != 'identity') {
        final Stream<List<int>>? decoded = bodyDecoder?.call(encoding, body);
        if (decoded == null) {
          return _statusResponse(415);
        }
        body = _LimitedBody(decoded, maxBodyBytes);
      }
    }

    final _InterruptibleBody interruptible = _InterruptibleBody(body);
    final _Exchange? exchange = _beginExchange(this);
    if (exchange == null) {
      return _statusResponse(503, headers: _retryAfterHeaders());
    }
    final GitServiceResponse serviceResponse;
    try {
      serviceResponse = await _awaitService(
        uploadPack.uploadPack(
          repository,
          interruptible,
          protocol: protocol,
        ),
        exchange,
      );
    } on _ExchangeExpiredException catch (error) {
      interruptible.interrupt(error, StackTrace.current);
      exchange.release();
      return _statusResponse(503, headers: _retryAfterHeaders());
    } on GitUnknownServedRepositoryException {
      exchange.release();
      return _statusResponse(404);
    } catch (error) {
      interruptible.interrupt(error, StackTrace.current);
      exchange.release();
      return _statusResponse(500);
    }
    return _GitHttpResponse(
      200,
      _protocolHeaders(_resultContentType),
      _ResponseBody(
        serviceResponse,
        exchange: exchange,
        onCancel: () => interruptible.interrupt(
          _ResponseCancelledException(),
          StackTrace.current,
        ),
        onFirstError: onError,
      ),
    );
  }

  /// A response without a body.
  GitHttpResponse _statusResponse(int status, {GitHttpHeaders? headers}) {
    return _GitHttpResponse(
      status,
      headers ??
          GitHttpHeaders(<String, List<String>>{
            'Cache-Control': <String>['no-cache'],
          }),
      const EmptyGitHttpResponseBody(),
    );
  }
}

final class _GitHttpResponse implements GitHttpResponse {
  @override
  final int status;

  @override
  final GitHttpHeaders headers;

  @override
  final Stream<List<int>> body;

  _GitHttpResponse(this.status, this.headers, this.body);
}
