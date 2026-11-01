import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/fake_git_process_launcher.dart';
import '../support/scripted_git_runner.dart';

void main() {
  final GitOid treeish = GitOid.parse('a' * 40);

  (ProcessGitWorkingRepository, FakeGitProcessLauncher) buildRepository() {
    final FakeGitProcessLauncher launcher = FakeGitProcessLauncher();
    final ProcessGitWorkingRepository repository = ProcessGitWorkingRepository(
      runner: ScriptedGitRunner(),
      context: GitRepositoryContext(
        path: '/repo',
        platform: GitPlatform.linux,
      ),
      platform: GitPlatform.linux,
      launcher: launcher,
    );
    return (repository, launcher);
  }

  test('streams the process output launched in the repository context',
      () async {
    final (
      ProcessGitWorkingRepository repository,
      FakeGitProcessLauncher launcher
    ) = buildRepository();
    final Future<(List<int>, Object?)> result = _collect(
        repository.objects.archive(treeish, format: GitArchiveFormat.zip));

    await _waitFor(() => launcher.processes.isNotEmpty);
    final FakeGitProcess process = launcher.processes.single;
    process.stdoutController.add(const <int>[1, 2, 3]);
    process.stdoutController.add(const <int>[4]);
    await process.stdoutController.close();
    await process.stderrController.close();
    process.exit.complete(0);

    final (List<int> bytes, Object? error) = await result;
    expect(error, isNull);
    expect(bytes, <int>[1, 2, 3, 4]);

    expect(launcher.requests.single.arguments, <String>[
      'archive',
      '--format=zip',
      treeish.value,
    ]);
    expect(
      launcher.requests.single.workingDirectory,
      repository.context.path,
    );
    expect(
      launcher.requests.single.environment,
      repository.context.environment,
    );
  });

  test('cancelling the subscription kills the process', () async {
    final (
      ProcessGitWorkingRepository repository,
      FakeGitProcessLauncher launcher
    ) = buildRepository();

    final StreamSubscription<List<int>> subscription =
        repository.objects.archive(treeish).listen((_) {});
    await _waitFor(() => launcher.processes.isNotEmpty);
    final FakeGitProcess process = launcher.processes.single;
    process.stdoutController.add(const <int>[1, 2, 3]);

    await subscription.cancel();

    expect(process.killCalls, 1);
    expect(process.exit.isCompleted, isTrue);
  });

  test('reports a non-zero exit as an error of the stream', () async {
    final (
      ProcessGitWorkingRepository repository,
      FakeGitProcessLauncher launcher
    ) = buildRepository();
    final Future<Object?> failure =
        _firstError(repository.objects.archive(treeish));

    await _waitFor(() => launcher.processes.isNotEmpty);
    final FakeGitProcess process = launcher.processes.single;
    process.stderrController.add(utf8.encode('fatal: not a valid object name'));
    await process.stderrController.close();
    await process.stdoutController.close();
    process.exit.complete(128);

    final Object? error = await failure;
    expect(error, isA<GitException>());
    expect(error, isA<GitCommandException>());
    expect(
      (error! as GitCommandException).stderr,
      contains('fatal: not a valid object name'),
    );
  });

  test('bounds the reported stderr to its most recent bytes', () async {
    final (
      ProcessGitWorkingRepository repository,
      FakeGitProcessLauncher launcher
    ) = buildRepository();
    final Future<Object?> failure =
        _firstError(repository.objects.archive(treeish));

    await _waitFor(() => launcher.processes.isNotEmpty);
    final FakeGitProcess process = launcher.processes.single;
    final Uint8List line =
        Uint8List.fromList(utf8.encode('remote: ${'x' * 119}\n'));
    final Uint8List flood = Uint8List(1024 * 1024);
    for (var offset = 0; offset < flood.length; offset += line.length) {
      flood.setRange(offset, offset + line.length, line);
    }
    process.stderrController.add(utf8.encode('early marker'));
    for (var index = 0; index < 17; index++) {
      process.stderrController.add(flood);
    }
    process.stderrController.add(utf8.encode('fatal: late marker'));
    await process.stderrController.close();
    await process.stdoutController.close();
    process.exit.complete(128);

    final Object? error = await failure;
    expect(error, isA<GitCommandException>());
    final String stderr = (error! as GitCommandException).stderr;
    expect(stderr.length, lessThanOrEqualTo(16 * 1024 * 1024));
    expect(stderr, endsWith('fatal: late marker'));
    expect(stderr, isNot(contains('early marker')));
  });
}

/// Collects [stream] into one buffer and reports its first error.
Future<(List<int>, Object?)> _collect(Stream<List<int>> stream) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  final Completer<Object?> done = Completer<Object?>();
  stream.listen(
    builder.add,
    onError: done.complete,
    onDone: () => done.complete(null),
    cancelOnError: true,
  );
  final Object? error = await done.future;
  return (builder.takeBytes(), error);
}

/// The first error or the end of [stream].
Future<Object?> _firstError(Stream<List<int>> stream) {
  final Completer<Object?> done = Completer<Object?>();
  stream.listen(
    (_) {},
    onError: done.complete,
    onDone: () => done.complete(null),
    cancelOnError: true,
  );
  return done.future;
}

/// Waits until [condition] holds or a short budget expires.
Future<void> _waitFor(bool Function() condition) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition() && watch.elapsedMilliseconds < 2000) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
