import 'dart:async';

import 'package:git_engine/git_engine.dart';

/// A request a test builds for a handler.
final class FakeGitHttpRequest implements GitHttpRequest {
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

  /// Creates the request.
  FakeGitHttpRequest({
    this.method = 'GET',
    required this.path,
    this.queryParameters = const <String, List<String>>{},
    GitHttpHeaders? headers,
    Stream<List<int>>? body,
  })  : headers = headers ?? GitHttpHeaders.empty(),
        body = body ?? const Stream<List<int>>.empty();
}

/// A principal a test authenticates.
final class FakeGitPrincipal implements GitPrincipal {
  @override
  final String name;

  /// Creates the identity [name].
  const FakeGitPrincipal(this.name);
}

/// An authorization policy a test controls, recording its calls.
final class FakeGitAuthorizationPolicy implements GitAuthorizationPolicy {
  final FutureOr<bool> Function(GitPrincipal? principal)? onCanRead;
  final FutureOr<bool> Function(GitPrincipal? principal)? onCanWrite;
  final List<GitPrincipal?> canReadCalls = <GitPrincipal?>[];
  final List<GitPrincipal?> canWriteCalls = <GitPrincipal?>[];

  /// Creates the policy; without hooks every read is allowed and every
  /// write is refused.
  FakeGitAuthorizationPolicy({this.onCanRead, this.onCanWrite});

  @override
  FutureOr<bool> canRead(
    GitPrincipal? principal,
    GitServedRepositoryId repository,
  ) {
    canReadCalls.add(principal);
    return onCanRead?.call(principal) ?? true;
  }

  @override
  FutureOr<bool> canWrite(
    GitPrincipal? principal,
    GitServedRepositoryId repository,
  ) {
    canWriteCalls.add(principal);
    return onCanWrite?.call(principal) ?? false;
  }
}

/// A request body that records what happens to it, so tests can check that
/// nobody listens to it, that it stays paused, or that it is cancelled.
final class RecordingBody extends Stream<List<int>> {
  final StreamController<List<int>> _source = StreamController<List<int>>();
  final StreamController<List<int>> _tracked = StreamController<List<int>>();
  StreamSubscription<List<int>>? _subscription;

  /// Whether anyone listened to this body.
  bool listened = false;

  /// Whether the listener cancelled this body.
  bool cancelled = false;

  /// How many times the listener paused this body.
  int pauses = 0;

  /// How many times the listener resumed this body.
  int resumes = 0;

  /// How many bytes actually crossed this body.
  int deliveredBytes = 0;

  /// Creates the body.
  RecordingBody() {
    _tracked
      ..onListen = () {
        listened = true;
        _subscription = _source.stream.listen(
          (List<int> chunk) {
            deliveredBytes += chunk.length;
            _tracked.add(chunk);
          },
          onError: _tracked.addError,
          onDone: _tracked.close,
        );
      }
      ..onPause = () {
        pauses++;
        _subscription?.pause();
      }
      ..onResume = () {
        resumes++;
        _subscription?.resume();
      }
      ..onCancel = () async {
        cancelled = true;
        final StreamSubscription<List<int>>? subscription = _subscription;
        _subscription = null;
        await subscription?.cancel();
      };
  }

  /// Pushes a chunk into the body; it stays buffered until someone listens.
  void add(List<int> chunk) => _source.add(chunk);

  /// Fails the body.
  void addError(Object error, [StackTrace? stackTrace]) =>
      _source.addError(error, stackTrace);

  /// Closes the body.
  Future<void> closeSource() => _source.close();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _tracked.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
