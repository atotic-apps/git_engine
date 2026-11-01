# Serving repositories

The server role is assembled from small contracts: a host supplies storage,
identity and policy, and the handler speaks smart HTTP over them. The
processing is transport-independent until a thin adapter turns its requests
and responses into the ones of a concrete server.

## Contracts

A served repository is named by a [GitServedRepositoryId] chosen by the
host. A [GitPrincipal] is the identity the host authenticated; null means
anonymous. A [GitAuthorizationPolicy] decides canRead and canWrite, and the
shipped [GitReadOnlyAuthorizationPolicy] allows every read and refuses every
write. A [GitUploadPackService] advertises refs and answers uploadPack,
exchanging [GitServiceResponse] bodies and transport-independent
[GitProtocolParameters].

[GitSmartHttpHandler] performs the protocol processing without `dart:io`. It
routes `GET …/info/refs?service=git-upload-pack` and
`POST …/git-upload-pack`, decodes the path itself, decompresses the request
body once through the decoder the transport supplies, and bounds the body
before and after decompression. Malformed requests and ambiguous paths are
400; unknown repositories are 404; an anonymous refusal is 401 with the
configured `WWW-Authenticate` challenge, or 403 without one; a refused
identity or a disabled service, including `git-receive-pack`, is 403; a
`Content-Length` beyond the body limit is 413; an unsupported content
encoding is 415; internal failures before the headers are 500. A body that
grows past the limit while streaming, or a response that fails after its
headers, ends in an error rather than a well-formed body.

```dart
import 'package:git_engine/git_engine.dart';

GitSmartHttpHandler buildHandler(GitUploadPackService uploadPack) {
  return GitSmartHttpHandler(
    resolveRepository: (List<String> segments) => segments.length == 1
        ? GitServedRepositoryId(segments.single)
        : null,
    authorizationPolicy: const GitReadOnlyAuthorizationPolicy(),
    uploadPack: uploadPack,
    maxBodyBytes: 64 * 1024 * 1024,
  );
}
```

## Bounds on exchanges

Every call to the service is an exchange: the advertisement of the `GET` and
the stateless RPC of each `POST` alike. A clone or a fetch chains one
advertisement then one or more `POST`s, each holding a slot for as long as
its own response lasts.

`maxConcurrentExchanges` (default 32) caps the exchanges active at once. A
request beyond it receives 503 with `Retry-After`, without calling the
service and without reading its body. `maxExchangeDuration` (default ten
minutes) bounds one exchange from its acceptance: at expiry the handler
cancels the service and interrupts the response. Before the service produced
a response, that answer is 503 with `Retry-After`; once the body is
streaming, it ends with an error. The duration adds to the service's own
inactivity delay.

A malformed request, an unknown repository and an authorization refusal are
decided before a slot is taken, so they never occupy one. Both limits are
global to the handler; per-client or per-address limits belong to the host,
which receives the [GitPrincipal] on each request.

## Process upload-pack service

[ProcessGitUploadPackService] delegates the protocol to the git executable.
It is built with an asynchronous resolution from [GitServedRepositoryId] to
[GitFileBareRepository], an inactivity delay and a buffer size. Without a
launcher it starts the configured executable with the layered environment.
The resolution may be asynchronous; a null result for an identifier becomes
the handler's 404.

`advertiseRefs` launches `git upload-pack --stateless-rpc --advertise-refs`
on the resolved git directory. `uploadPack` launches
`git upload-pack --stateless-rpc` and writes the request into its standard
input. Protocol parameters reach git only through `GIT_PROTOCOL`, after
every entry is validated; no other variable and no option comes from the
request.

The exchange keeps its memory bounded and its streams backpressured: the
request is written only as fast as git accepts it, the response only as fast
as the consumer reads it, and standard error is drained eagerly within the
buffer, never sent to the client. Every stop — cancellation, the end of the
body subscription, inactivity, a failing request body or a broken pipe —
kills the process and stops reading the request. A non-zero exit after the
body started becomes an error of the body, reported to the host callback.

## Serving over dart:io

[DartIoGitHttpServer] is the thin `dart:io` adapter, exported by
`package:git_engine/server_io.dart` together with `dartIoGzipBodyDecoder`.
It builds a [GitHttpRequest] from each `dart:io` request without decoding
the path or decompressing the body, supplies the gzip decoder when the
handler has none, writes the response with backpressure, destroys the
connection when a streamed response fails, and cancels the response when the
client disconnects. Authentication stays with the host: the adapter passes
the result of a callback, a [GitPrincipal] or null, to the handler.

The runnable scenario is `example/smart_http_server.dart`: it serves a
temporary bare repository on a local port and prints the clone and fetch
commands for another terminal.

## Read-only scope

The shipped server serves clone and fetch only. A push is not served:
`git-receive-pack` is answered 403. The only transport is smart HTTP over
`dart:io`; there is no server-side SSH. Authentication belongs to the host,
and the shipped policy allows every read. Hooks, quarantine and push
validation are not implemented, because they belong to a push service.
