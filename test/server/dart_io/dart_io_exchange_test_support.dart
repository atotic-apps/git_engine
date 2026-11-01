import 'dart:async';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/src/server/dart_io/dart_io_exchange.dart';

/// A request a test feeds to a [DartIoExchange].
final class FakeDartIoRequest implements DartIoRequest {
  @override
  final String method;

  @override
  final String path;

  @override
  final Map<String, List<String>> queryParameters;

  @override
  final GitHttpHeaders headers;

  @override
  final Stream<List<int>> body;

  /// Creates the simulated request.
  FakeDartIoRequest({
    this.method = 'GET',
    required this.path,
    this.queryParameters = const <String, List<String>>{},
    GitHttpHeaders? headers,
    Stream<List<int>>? body,
  })  : headers = headers ?? GitHttpHeaders.empty(),
        body = body ?? const Stream<List<int>>.empty();
}

/// A response sink that records the status, the headers and the body.
class RecordingDartIoResponse implements DartIoResponse {
  /// The status the exchange wrote, or null before the response started.
  int? statusCode;

  /// The headers the exchange wrote, or null before the response started.
  GitHttpHeaders? headers;

  final BytesBuilder _body = BytesBuilder(copy: false);

  /// The chunks the exchange forwarded, in order.
  final List<List<int>> received = <List<int>>[];

  /// Whether the exchange ended the response.
  bool closed = false;

  /// Whether the exchange destroyed the connection.
  bool aborted = false;

  /// The bytes written so far.
  List<int> get bytes => _body.toBytes();

  @override
  void configure({
    required int statusCode,
    required GitHttpHeaders headers,
  }) {
    this.statusCode = statusCode;
    this.headers = headers;
  }

  @override
  Future<void> addStream(Stream<List<int>> body) async {
    await for (final List<int> chunk in body) {
      received.add(chunk);
      _body.add(chunk);
    }
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> abort() async {
    aborted = true;
  }
}

/// A response sink that records the error that interrupts the body.
final class FailingWriteResponse extends RecordingDartIoResponse {
  /// The error that stopped the body, or null when it ended cleanly.
  Object? writeError;

  @override
  Future<void> addStream(Stream<List<int>> body) async {
    try {
      await super.addStream(body);
    } catch (error) {
      writeError = error;
      rethrow;
    }
  }
}

/// A response sink that stops reading after its first chunk, like a client
/// that disappeared.
final class ClientGoneResponse extends RecordingDartIoResponse {
  /// Completes when the first chunk was written.
  final Completer<void> firstChunk = Completer<void>();

  final Completer<void> _finished = Completer<void>();

  @override
  Future<void> addStream(Stream<List<int>> body) async {
    late StreamSubscription<List<int>> subscription;
    subscription = body.listen(
      (List<int> chunk) {
        received.add(chunk);
        _body.add(chunk);
        if (!firstChunk.isCompleted) {
          firstChunk.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_finished.isCompleted) {
          _finished.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!_finished.isCompleted) {
          _finished.complete();
        }
      },
    );
    await firstChunk.future;
    await subscription.cancel();
    if (!_finished.isCompleted) {
      _finished.complete();
    }
  }
}

/// A response sink that pauses after its first chunk and resumes on demand.
final class PausedDartIoResponse extends RecordingDartIoResponse {
  /// Completes when the first chunk was written and the body was paused.
  final Completer<void> firstChunk = Completer<void>();

  final Completer<void> _finished = Completer<void>();
  late StreamSubscription<List<int>> _subscription;

  @override
  Future<void> addStream(Stream<List<int>> body) async {
    _subscription = body.listen(
      (List<int> chunk) {
        received.add(chunk);
        _body.add(chunk);
        if (received.length == 1) {
          _subscription.pause();
          firstChunk.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_finished.isCompleted) {
          _finished.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!_finished.isCompleted) {
          _finished.complete();
        }
      },
    );
    await _finished.future;
  }

  /// Resumes the paused body.
  void resume() => _subscription.resume();
}

/// A response sink that signals its first chunk and then reads to the end.
final class FirstChunkResponse extends RecordingDartIoResponse {
  /// Completes when the first chunk was written.
  final Completer<void> firstChunk = Completer<void>();

  @override
  Future<void> addStream(Stream<List<int>> body) async {
    await for (final List<int> chunk in body) {
      received.add(chunk);
      _body.add(chunk);
      if (!firstChunk.isCompleted) {
        firstChunk.complete();
      }
    }
  }
}

/// An upload-pack service whose request reading and response production pace
/// each other: every response chunk is derived from one request chunk, and
/// the next request chunk is read only once the previous response chunk was
/// consumed.
final class InterlockedUploadPackService implements GitUploadPackService {
  @override
  Future<GitServiceResponse> advertiseRefs(
    GitServedRepositoryId repository, {
    required GitProtocolParameters protocol,
  }) async {
    throw UnimplementedError('this fake only serves uploadPack');
  }

  @override
  Future<GitServiceResponse> uploadPack(
    GitServedRepositoryId repository,
    Stream<List<int>> request, {
    required GitProtocolParameters protocol,
  }) async {
    final StreamIterator<List<int>> requestIterator =
        StreamIterator<List<int>>(request);
    if (!await requestIterator.moveNext()) {
      await requestIterator.cancel();
      throw StateError('the request body ended before its first chunk');
    }
    final List<int> first = requestIterator.current;

    Stream<List<int>> pump() async* {
      yield _shifted(first);
      while (await requestIterator.moveNext()) {
        yield _shifted(requestIterator.current);
      }
    }

    return _InterlockedResponse(pump(), requestIterator.cancel);
  }
}

/// [chunk] with every byte incremented by one, independent of where the
/// transport cut the request into chunks.
List<int> _shifted(List<int> chunk) {
  final Uint8List shifted = Uint8List(chunk.length);
  for (var index = 0; index < shifted.length; index++) {
    shifted[index] = (chunk[index] + 1) & 0xff;
  }
  return shifted;
}

/// A [GitServiceResponse] whose release cancels the reading of the request.
final class _InterlockedResponse implements GitServiceResponse {
  final Stream<List<int>> _body;
  final Future<void> Function() _release;

  _InterlockedResponse(this._body, this._release);

  @override
  Stream<List<int>> get body => _body;

  @override
  Future<void> cancel() => _release();
}
