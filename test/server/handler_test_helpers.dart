import 'dart:async';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';

import '../support/fake_git_http.dart';

/// The repository id the default resolver of the test handlers returns.
const GitServedRepositoryId repoId = GitServedRepositoryId('repo');

/// The smart HTTP framing of an advertisement, as the handler must emit it.
final List<int> advertisementPrefix = <int>[
  ...'001e# service=git-upload-pack\n'.codeUnits,
  ...'0000'.codeUnits,
];

/// A handler built for a test.
GitSmartHttpHandler buildHandler({
  FutureOr<GitServedRepositoryId?> Function(List<String> segments)?
      resolveRepository,
  FakeGitAuthorizationPolicy? policy,
  required GitUploadPackService service,
  String? challenge,
  GitHttpBodyDecoder? decoder,
  int maxBodyBytes = 1024 * 1024,
  int maxConcurrentExchanges = 32,
  Duration maxExchangeDuration = const Duration(minutes: 10),
  void Function(Object error, StackTrace stackTrace)? onError,
}) {
  return GitSmartHttpHandler(
    resolveRepository: resolveRepository ?? (List<String> segments) => null,
    authorizationPolicy: policy ?? FakeGitAuthorizationPolicy(),
    uploadPack: service,
    wwwAuthenticateChallenge: challenge,
    bodyDecoder: decoder,
    maxBodyBytes: maxBodyBytes,
    maxConcurrentExchanges: maxConcurrentExchanges,
    maxExchangeDuration: maxExchangeDuration,
    onError: onError,
  );
}

/// A handler factory whose resolver accepts a set of segment lists, and
/// records every resolution it is asked for.
final class RecordingResolver {
  /// Creates the factory for [accepted] segment lists.
  RecordingResolver({
    Set<List<String>> accepted = const <List<String>>{
      <String>['repo'],
    },
  }) : accepted = accepted;

  /// The segment lists that resolve to [repoId].
  final Set<List<String>> accepted;

  final List<List<String>> calls = <List<String>>[];

  /// Builds the handler around [service] and the other test knobs.
  GitSmartHttpHandler handler({
    required GitUploadPackService service,
    FakeGitAuthorizationPolicy? policy,
    String? challenge,
    GitHttpBodyDecoder? decoder,
    int maxBodyBytes = 1024 * 1024,
    int maxConcurrentExchanges = 32,
    Duration maxExchangeDuration = const Duration(minutes: 10),
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    return buildHandler(
      resolveRepository: (List<String> segments) {
        calls.add(List<String>.of(segments));
        for (final List<String> candidate in accepted) {
          if (_sameSegments(candidate, segments)) {
            return repoId;
          }
        }
        return null;
      },
      policy: policy,
      service: service,
      challenge: challenge,
      decoder: decoder,
      maxBodyBytes: maxBodyBytes,
      maxConcurrentExchanges: maxConcurrentExchanges,
      maxExchangeDuration: maxExchangeDuration,
      onError: onError,
    );
  }
}

/// Whether two segment lists carry the same segments in the same order.
bool _sameSegments(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) {
      return false;
    }
  }
  return true;
}

/// The outcome of reading a response body until its end or its first error.
final class CollectedBody {
  /// Creates the outcome.
  const CollectedBody(this.bytes, this.error);

  /// Bytes delivered before the body ended or failed.
  final List<int> bytes;

  /// The error that interrupted the body, or null when it ended cleanly.
  final Object? error;
}

/// Reads [body] until it ends or emits its first error.
Future<CollectedBody> collectBody(Stream<List<int>> body) async {
  final Completer<Object?> finished = Completer<Object?>();
  final BytesBuilder builder = BytesBuilder();
  body.listen(
    builder.add,
    onError: (Object error) {
      if (!finished.isCompleted) {
        finished.complete(error);
      }
    },
    onDone: () {
      if (!finished.isCompleted) {
        finished.complete(null);
      }
    },
  );
  final Object? error = await finished.future;
  return CollectedBody(builder.takeBytes(), error);
}

/// A [GitHttpBodyDecoder] for tests: it accepts the [accepted] encodings and
/// decompresses them with the gzip of `dart:io`, exactly the way a
/// `dart:io` adapter would, and records every call.
final class RecordingDecoder {
  /// Creates the decoder accepting [accepted].
  RecordingDecoder(this.accepted);

  /// The encodings the decoder accepts.
  final Set<String> accepted;

  /// Every encoding the handler asked it to decode, in order.
  final List<String> calls = <String>[];

  /// Whether the handler called the decoder at all.
  bool get called => calls.isNotEmpty;

  /// The decoder function to hand to a handler.
  GitHttpBodyDecoder get fn {
    return (String encoding, Stream<List<int>> body) {
      calls.add(encoding);
      if (!accepted.contains(encoding)) {
        return null;
      }
      return gzip.decoder.bind(body);
    };
  }
}
