# Testing

## A real temporary repository

Facades are implemented by the engines maintained with the package, so a test
that needs one opens a real temporary repository through the process backend.
Isolate git from the machine's configuration: set `GIT_CONFIG_NOSYSTEM=1`, point
`GIT_CONFIG_GLOBAL` at an empty file, fix the local identity and set
`core.autocrlf=false`. Remove the sandbox when the test ends; on Windows, retry
the deletion while git may still hold file locks.

Tests that drive the installed git are tagged `git`; `dart test` skips them and
`dart test --run-skipped` runs them where git 2.28 or newer is on the `PATH`.

```dart
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main() async {
  final Directory sandbox =
      await Directory.systemTemp.createTemp('engine_test_');
  final File globalConfig = File('${sandbox.path}/gitconfig');
  await globalConfig.writeAsString('');
  try {
    final ProcessGitEngine engine = ProcessGitEngine(
      globalEnvironment: <String, String>{
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': globalConfig.path,
      },
    );
    final GitWorkingRepository repository =
        await engine.init('${sandbox.path}/repo', initialBranch: 'main');
    print(await repository.branches.current());
  } finally {
    await sandbox.delete(recursive: true);
  }
}
```

## Implementable contracts

A test may implement a capability contract only: provide the members the test
uses and leave the others unimplemented. The repository-side contracts are
[GitObjectReader], [GitObjectWriter], [GitObjectStore], [GitRefReader],
[GitRevisionResolver], [GitHistoryReader], [GitRefTransaction],
[GitRepositoryReader] and [GitRepositoryWriter]. The server-side contracts are
[GitPrincipal], [GitAuthorizationPolicy], [GitServiceResponse],
[GitUploadPackService] and [GitHttpRequest].

Because a test double and the real engine satisfy the same contract, one shared
suite can run against both. Facades are not implemented by tests: a test that
needs one uses the real repository above.

## Seams of `package:git_engine/testing.dart`

That entry point exposes four seams:

- [GitRunner] gathers a command through [GitRunRequest] and returns a
  [GitRunResult]; every command of every domain passes through it.
- [GitProcessLauncher] starts a streaming process through
  [GitProcessLaunchRequest] and returns a [GitLaunchedProcess].
- [GitFileSystem] performs file operations, [GitFileSystemEntry] describes a
  listed child and [MemoryGitFileSystem] keeps everything in memory.
- [GitPlatform] supplies the operating system and path spelling as
  [GitOperatingSystem] and [GitPathStyle], plus the environment variables.

[ProcessGitEngine] accepts a runner, a launcher, a file system and a platform
through its constructor. A runner already carries the executable, environment,
long-path setting and timeout, so supplying a non-default value for one of
those with it raises [ArgumentError]. The memory file system uses POSIX paths,
so pair it with `GitPlatform.linux`.

```dart
import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';
import 'package:git_engine/testing.dart';

Future<void> main() async {
  final MemoryGitFileSystem fileSystem = MemoryGitFileSystem();
  final ProcessGitEngine engine = ProcessGitEngine(
    fileSystem: fileSystem,
    platform: GitPlatform.linux,
  );
  fileSystem.seedDirectory('/repo');
  fileSystem.seedFile('/repo/notes.txt', <int>[65]);
  try {
    await engine.init('/repo');
  } on GitOccupiedDirectoryException catch (error) {
    print(error.path);
  }
}
```

The creation guard of `init` consults the injected file system, so an occupied
target is refused before git runs and no repository is created.
