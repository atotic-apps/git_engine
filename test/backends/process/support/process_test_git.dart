import 'package:git_engine/git_engine.dart';

import 'process_backend_types.dart' show ProcessGitRepository;

export 'process_backend_types.dart';

/// Stages [oid] at [path] in the active index of [repository] with [mode].
///
/// The typed index facade has no operation for staging an arbitrary mode, so
/// preparation that needs an executable, a symbolic link or a gitlink entry
/// goes through the process backend directly.
Future<void> stageIndexEntry(
  GitRepository repository, {
  required String mode,
  required GitOid oid,
  required String path,
}) async {
  await _process(repository).runCommand(<String>[
    'update-index',
    '--add',
    '--cacheinfo',
    '$mode,${oid.value},$path',
  ]);
}

/// Points the symbolic reference [name] of [repository] at [target].
Future<void> pointSymbolicRef(
  GitRepository repository,
  String name,
  String target,
) async {
  await _process(repository).runCommand(<String>[
    'symbolic-ref',
    name,
    target,
  ]);
}

ProcessGitRepository _process(GitRepository repository) {
  if (repository is ProcessGitRepository) {
    return repository;
  }
  throw ArgumentError.value(
    repository,
    'repository',
    'must be a repository of the process backend',
  );
}
