import 'dart:async';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/fake_git_http.dart';
import '../support/fake_upload_pack_service.dart';
import 'handler_test_helpers.dart';

/// The concurrency and duration limits of [GitSmartHttpHandler], exercised
/// with a service a test controls so every exit path can be observed.
void main() {
  late FakeUploadPackService service;
  late RecordingResolver resolver;

  setUp(() {
    service = FakeUploadPackService()..holdResponseOpen = true;
    resolver = RecordingResolver();
  });

  FakeGitHttpRequest postRequest({Stream<List<int>>? body}) {
    return FakeGitHttpRequest(
      method: 'POST',
      path: '/repo/git-upload-pack',
      headers: GitHttpHeaders(<String, List<String>>{
        'Content-Type': <String>['application/x-git-upload-pack-request'],
      }),
      body: body,
    );
  }

  FakeGitHttpRequest getRequest() {
    return FakeGitHttpRequest(
      path: '/repo/info/refs',
      queryParameters: <String, List<String>>{
        'service': <String>['git-upload-pack'],
      },
    );
  }

  group('GitSmartHttpHandler concurrency limit', () {
    test('answers 503 with Retry-After without calling the service', () async {
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);
      final RecordingBody body = RecordingBody();

      final GitHttpResponse first = await handler.handle(postRequest());
      expect(first.status, 200);

      final GitHttpResponse second =
          await handler.handle(postRequest(body: body));
      expect(second.status, 503);
      expect(second.headers.firstValue('retry-after'), '1');
      expect(second.headers.firstValue('cache-control'), 'no-cache');
      expect(body.listened, isFalse);
      expect(service.uploadCalls, hasLength(1));

      await _finish(service.responses.single, first);
    });

    test('releases the slot when the response ends normally', () async {
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse first = await handler.handle(postRequest());
      final GitHttpResponse second = await handler.handle(postRequest());
      expect(second.status, 503);

      await _finish(service.responses.single, first);

      final GitHttpResponse third = await handler.handle(postRequest());
      expect(third.status, 200);
      await _finish(service.responses.last, third);
    });

    test('releases the slot when the response body fails', () async {
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse first = await handler.handle(postRequest());
      final GitHttpResponse second = await handler.handle(postRequest());
      expect(second.status, 503);

      service.responses.single.controller.addError(StateError('pack failed'));
      unawaited(service.responses.single.controller.close());
      final CollectedBody collected = await collectBody(first.body);
      expect(collected.error, isNotNull);

      final GitHttpResponse third = await handler.handle(postRequest());
      expect(third.status, 200);
      await _finish(service.responses.last, third);
    });

    test('releases the slot when the response is cancelled', () async {
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse first = await handler.handle(postRequest());
      final GitHttpResponse second = await handler.handle(postRequest());
      expect(second.status, 503);

      final StreamSubscription<List<int>> subscription =
          first.body.listen((List<int> chunk) {});
      await pumpEventQueue();
      await subscription.cancel();

      final GitHttpResponse third = await handler.handle(postRequest());
      expect(third.status, 200);
      await _finish(service.responses.last, third);
    });

    test('releases the slot when the service call fails', () async {
      service.uploadPackError = StateError('git refused');
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse first = await handler.handle(postRequest());
      expect(first.status, 500);

      service.uploadPackError = null;
      final GitHttpResponse second = await handler.handle(postRequest());
      expect(second.status, 200);
      await _finish(service.responses.last, second);
    });

    test('counts a reference advertisement as an exchange', () async {
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse post = await handler.handle(postRequest());
      expect(post.status, 200);

      final GitHttpResponse advertisement = await handler.handle(getRequest());
      expect(advertisement.status, 503);
      expect(advertisement.headers.firstValue('retry-after'), '1');
      expect(service.advertiseCalls, isEmpty);

      await _finish(service.responses.single, post);
    });
  });

  group('GitSmartHttpHandler advertisement exchanges', () {
    test('refuses a second advertisement at the cap', () async {
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse first = await handler.handle(getRequest());
      expect(first.status, 200);

      final GitHttpResponse second = await handler.handle(getRequest());
      expect(second.status, 503);
      expect(second.headers.firstValue('retry-after'), '1');
      expect(service.advertiseCalls, hasLength(1));

      await _finish(service.responses.single, first);
    });

    test('refuses a POST while an advertisement holds the slot', () async {
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse advertisement = await handler.handle(getRequest());
      expect(advertisement.status, 200);

      final RecordingBody body = RecordingBody();
      final GitHttpResponse post =
          await handler.handle(postRequest(body: body));
      expect(post.status, 503);
      expect(post.headers.firstValue('retry-after'), '1');
      expect(body.listened, isFalse);
      expect(service.uploadCalls, isEmpty);

      await _finish(service.responses.single, advertisement);
    });

    test('releases the slot when the advertisement ends normally', () async {
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse first = await handler.handle(getRequest());
      final GitHttpResponse second = await handler.handle(getRequest());
      expect(second.status, 503);

      await _finish(service.responses.single, first);

      final GitHttpResponse third = await handler.handle(getRequest());
      expect(third.status, 200);
      await _finish(service.responses.last, third);
    });

    test('releases the slot when the advertisement body fails', () async {
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse first = await handler.handle(getRequest());
      final GitHttpResponse second = await handler.handle(getRequest());
      expect(second.status, 503);

      service.responses.single.controller.addError(
        StateError('advertisement failed'),
      );
      unawaited(service.responses.single.controller.close());
      final CollectedBody collected = await collectBody(first.body);
      expect(collected.error, isNotNull);

      final GitHttpResponse third = await handler.handle(getRequest());
      expect(third.status, 200);
      await _finish(service.responses.last, third);
    });

    test('releases the slot when the advertisement is cancelled', () async {
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse first = await handler.handle(getRequest());
      final GitHttpResponse second = await handler.handle(getRequest());
      expect(second.status, 503);

      final StreamSubscription<List<int>> subscription =
          first.body.listen((List<int> chunk) {});
      await pumpEventQueue();
      await subscription.cancel();

      final GitHttpResponse third = await handler.handle(getRequest());
      expect(third.status, 200);
      await _finish(service.responses.last, third);
    });

    test('releases the slot when the advertisement answers 404', () async {
      service.advertiseError = GitUnknownServedRepositoryException(repoId);
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse first = await handler.handle(getRequest());
      expect(first.status, 404);

      service.advertiseError = null;
      final GitHttpResponse second = await handler.handle(getRequest());
      expect(second.status, 200);
      await _finish(service.responses.single, second);
    });

    test('releases the slot when the advertisement call fails', () async {
      service.advertiseError = StateError('git refused');
      final GitSmartHttpHandler handler =
          resolver.handler(service: service, maxConcurrentExchanges: 1);

      final GitHttpResponse first = await handler.handle(getRequest());
      expect(first.status, 500);

      service.advertiseError = null;
      final GitHttpResponse second = await handler.handle(getRequest());
      expect(second.status, 200);
      await _finish(service.responses.single, second);
    });
  });

  group('GitSmartHttpHandler exchange duration', () {
    test('answers 503 when the duration expires before the headers', () async {
      service.uploadPackDelay = const Duration(milliseconds: 150);
      final GitSmartHttpHandler handler = resolver.handler(
        service: service,
        maxConcurrentExchanges: 1,
        maxExchangeDuration: const Duration(milliseconds: 20),
      );

      final GitHttpResponse response = await handler.handle(postRequest());
      expect(response.status, 503);
      expect(response.headers.firstValue('retry-after'), '1');

      await _waitUntil(() => service.responses.isNotEmpty);
      await service.responses.single.cancelled
          .timeout(const Duration(seconds: 2));

      service.uploadPackDelay = Duration.zero;
      service.holdResponseOpen = false;
      final GitHttpResponse next = await handler.handle(postRequest());
      expect(next.status, 200, reason: 'the slot was released');
      await collectBody(next.body);
    });

    test('interrupts the response when the duration expires while streaming',
        () async {
      final GitSmartHttpHandler handler = resolver.handler(
        service: service,
        maxConcurrentExchanges: 1,
        maxExchangeDuration: const Duration(milliseconds: 30),
      );

      final GitHttpResponse response = await handler.handle(postRequest());
      expect(response.status, 200);

      final CollectedBody collected = await collectBody(response.body);
      expect(collected.error, isNotNull);
      expect(collected.error.toString(), contains('maximum duration'));
      expect(service.responses.single.cancelCalls, 1);

      service.holdResponseOpen = false;
      final GitHttpResponse next = await handler.handle(postRequest());
      expect(next.status, 200, reason: 'the slot was released');
      await collectBody(next.body);
    });

    test('answers 503 when the advertisement expires first', () async {
      final Completer<void> release = Completer<void>();
      final _HeldAdvertiseService held =
          _HeldAdvertiseService(service, release.future);
      final GitSmartHttpHandler handler = resolver.handler(
        service: held,
        maxConcurrentExchanges: 1,
        maxExchangeDuration: const Duration(milliseconds: 20),
      );

      final GitHttpResponse response = await handler.handle(getRequest());
      expect(response.status, 503);
      expect(response.headers.firstValue('retry-after'), '1');

      release.complete();
      await _waitUntil(() => service.responses.isNotEmpty);
      await service.responses.single.cancelled
          .timeout(const Duration(seconds: 2));

      service.holdResponseOpen = false;
      final GitHttpResponse next = await handler.handle(getRequest());
      expect(next.status, 200, reason: 'the slot was released');
      await collectBody(next.body);
    });

    test('interrupts the advertisement while streaming', () async {
      final GitSmartHttpHandler handler = resolver.handler(
        service: service,
        maxConcurrentExchanges: 1,
        maxExchangeDuration: const Duration(milliseconds: 30),
      );

      final GitHttpResponse response = await handler.handle(getRequest());
      expect(response.status, 200);

      final CollectedBody collected = await collectBody(response.body);
      expect(collected.error, isNotNull);
      expect(collected.error.toString(), contains('maximum duration'));
      expect(service.responses.single.cancelCalls, 1);

      service.holdResponseOpen = false;
      final GitHttpResponse next = await handler.handle(getRequest());
      expect(next.status, 200, reason: 'the slot was released');
      await collectBody(next.body);
    });
  });

  group('GitSmartHttpHandler limit validation', () {
    test('refuses a non-positive concurrency limit', () {
      expect(
        () => buildHandler(service: service, maxConcurrentExchanges: 0),
        throwsArgumentError,
      );
    });

    test('refuses a non-positive maximum duration', () {
      expect(
        () =>
            buildHandler(service: service, maxExchangeDuration: Duration.zero),
        throwsArgumentError,
      );
    });
  });
}

/// A service whose advertisement resolution waits for a test-controlled
/// release before delegating to [inner].
final class _HeldAdvertiseService implements GitUploadPackService {
  /// Creates the service around [inner], resolving an advertisement once
  /// [release] completes.
  _HeldAdvertiseService(this.inner, this.release);

  /// The service that actually produces the responses.
  final FakeUploadPackService inner;

  /// Completes when the advertisement resolution may proceed.
  final Future<void> release;

  @override
  Future<GitServiceResponse> advertiseRefs(
    GitServedRepositoryId repository, {
    required GitProtocolParameters protocol,
  }) async {
    await release;
    return inner.advertiseRefs(repository, protocol: protocol);
  }

  @override
  Future<GitServiceResponse> uploadPack(
    GitServedRepositoryId repository,
    Stream<List<int>> request, {
    required GitProtocolParameters protocol,
  }) {
    return inner.uploadPack(repository, request, protocol: protocol);
  }
}

/// Closes the canned body of [response] and consumes it, so the exchange
/// releases its slot.
Future<void> _finish(
    FakeServiceResponse response, GitHttpResponse handled) async {
  if (!response.controller.isClosed) {
    unawaited(response.controller.close());
  }
  await collectBody(handled.body);
}

/// Waits until [condition] holds, failing after [timeout].
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
