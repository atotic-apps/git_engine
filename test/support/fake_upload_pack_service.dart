import 'dart:async';

import 'package:git_engine/git_engine.dart';

/// A [GitServiceResponse] a fake service hands out: the test drives its body
/// through [controller] and observes cancellation and pauses.
final class FakeServiceResponse implements GitServiceResponse {
  /// Drives the body. Single-subscription, like the contract requires.
  final StreamController<List<int>> controller = StreamController<List<int>>();

  final Completer<void> _cancelled = Completer<void>();
  StreamSubscription<List<int>>? _sourceSubscription;

  /// How many times [cancel] was called.
  int cancelCalls = 0;

  /// Completes the first time [cancel] is called.
  Future<void> get cancelled => _cancelled.future;

  /// Whether the consumer of the body paused it.
  bool get bodyPaused => controller.isPaused;

  /// Forwards [source] into the body, echoing its error and its end, and
  /// stops the forwarding when the response is cancelled.
  void echo(Stream<List<int>> source) {
    _sourceSubscription = source.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
  }

  /// Fills the body with [chunks], then closes it — or fails it with
  /// [error] without a valid end, like a service whose work blew up
  /// mid-flight.
  void completeWith(List<List<int>> chunks, {Object? error}) {
    for (final List<int> chunk in chunks) {
      controller.add(chunk);
    }
    if (error != null) {
      controller.addError(error);
    } else {
      controller.close();
    }
  }

  @override
  Stream<List<int>> get body => controller.stream;

  @override
  Future<void> cancel() async {
    cancelCalls++;
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
    await _sourceSubscription?.cancel();
  }
}

/// One [GitUploadPackService.advertiseRefs] call.
final class RecordedAdvertise {
  /// Creates the record.
  const RecordedAdvertise(this.repository, this.protocol);

  /// Repository the service was asked about.
  final GitServedRepositoryId repository;

  /// Protocol parameters the transport passed.
  final GitProtocolParameters protocol;
}

/// One [GitUploadPackService.uploadPack] call.
final class RecordedUpload {
  /// Creates the record.
  const RecordedUpload(this.repository, this.request, this.protocol);

  /// Repository the service was asked about.
  final GitServedRepositoryId repository;

  /// Request body the transport handed over.
  final Stream<List<int>> request;

  /// Protocol parameters the transport passed.
  final GitProtocolParameters protocol;
}

/// A [GitUploadPackService] a test controls, recording every call.
///
/// Tests configure it per scenario: [advertiseError] and [uploadPackError]
/// make the calls throw, [echoRequestBody] mirrors the request body into the
/// response body (the way a real service feeds git), and [readRequestBody]
/// set to false keeps the request body untouched so a test can verify
/// backpressure.
final class FakeUploadPackService implements GitUploadPackService {
  /// Every advertise call, in order.
  final List<RecordedAdvertise> advertiseCalls = <RecordedAdvertise>[];

  /// Every upload call, in order.
  final List<RecordedUpload> uploadCalls = <RecordedUpload>[];

  /// Every response the service produced, in order.
  final List<FakeServiceResponse> responses = <FakeServiceResponse>[];

  /// When set, [advertiseRefs] throws this.
  Object? advertiseError;

  /// When set, [uploadPack] throws this.
  Object? uploadPackError;

  /// A delay before [uploadPack] answers, so a test can let the total
  /// duration expire before the response headers are sent.
  Duration uploadPackDelay = Duration.zero;

  /// Whether [uploadPack] mirrors the request body into the response body.
  bool echoRequestBody = false;

  /// Whether [uploadPack] may listen to the request body at all.
  bool readRequestBody = true;

  /// When true, the canned response body stays open and empty, so a test
  /// can cancel a response that has not ended by itself.
  bool holdResponseOpen = false;

  /// The chunks of the canned response body, then its end.
  List<List<int>> cannedChunks = <List<int>>[
    <int>[48, 48, 48, 48],
  ];

  @override
  Future<GitServiceResponse> advertiseRefs(
    GitServedRepositoryId repository, {
    required GitProtocolParameters protocol,
  }) async {
    advertiseCalls.add(RecordedAdvertise(repository, protocol));
    final Object? error = advertiseError;
    if (error != null) {
      throw error;
    }
    return _response(_fillCanned);
  }

  @override
  Future<GitServiceResponse> uploadPack(
    GitServedRepositoryId repository,
    Stream<List<int>> request, {
    required GitProtocolParameters protocol,
  }) async {
    uploadCalls.add(RecordedUpload(repository, request, protocol));
    if (uploadPackDelay > Duration.zero) {
      await Future<void>.delayed(uploadPackDelay);
    }
    final Object? error = uploadPackError;
    if (error != null) {
      throw error;
    }
    if (echoRequestBody && readRequestBody) {
      return _response((FakeServiceResponse response) {
        response.echo(request);
      });
    }
    return _response(_fillCanned);
  }

  void _fillCanned(FakeServiceResponse response) {
    if (holdResponseOpen) {
      return;
    }
    response.completeWith(cannedChunks);
  }

  FakeServiceResponse _response(void Function(FakeServiceResponse) fill) {
    final FakeServiceResponse response = FakeServiceResponse();
    fill(response);
    responses.add(response);
    return response;
  }
}
