import 'package:git_engine/testing.dart';

import 'scripted_git_runner.dart';

export 'process_backend_types.dart';

/// Synthetic repository path used by unit tests; no such directory exists.
const String syntheticRepositoryPath = '/repo';

/// Synthetic object name of a tree.
const String syntheticTreeOid = '1111111111111111111111111111111111111111';

/// Synthetic object name of a first parent commit.
const String syntheticFirstParentOid =
    '2222222222222222222222222222222222222222';

/// Synthetic object name of a second parent commit.
const String syntheticSecondParentOid =
    '3333333333333333333333333333333333333333';

/// Synthetic object name of a commit.
const String syntheticCommitOid = '4444444444444444444444444444444444444444';

/// Synthetic object name of a blob.
const String syntheticBlobOid = '5555555555555555555555555555555555555555';

/// Synthetic object name of a subtree.
const String syntheticSubtreeOid = '6666666666666666666666666666666666666666';

/// Synthetic object name of a symbolic-link blob.
const String syntheticLinkOid = '7777777777777777777777777777777777777777';

/// Synthetic object name of an annotated tag.
const String syntheticTagOid = '8888888888888888888888888888888888888888';

/// A working repository view running commands through [runner] at [path],
/// under [platform] when given.
ProcessGitWorkingRepository syntheticWorkingRepository(
  ScriptedGitRunner runner, {
  String path = syntheticRepositoryPath,
  GitPlatform? platform,
}) {
  return ProcessGitWorkingRepository(
    runner: runner,
    context: GitRepositoryContext(path: path, platform: platform),
    platform: platform,
  );
}

/// An indexed repository view running commands through [runner] at [path],
/// under [platform] when given.
ProcessGitIndexedRepository syntheticIndexedRepository(
  ScriptedGitRunner runner, {
  String path = syntheticRepositoryPath,
  GitPlatform? platform,
}) {
  return ProcessGitIndexedRepository(
    runner: runner,
    context: GitRepositoryContext(path: path, platform: platform),
    platform: platform,
  );
}

/// An engine running commands through [runner], under [platform] when given.
ProcessGitEngine syntheticEngine(
  ScriptedGitRunner runner, {
  GitPlatform? platform,
}) {
  return ProcessGitEngine(runner: runner, platform: platform);
}
