# Getting started

`git_engine` drives the installed git executable behind typed Dart
contracts. An application chooses one engine where it wires its
dependencies, then programs against interfaces, so the backend stays
replaceable.

## Choosing the engine at the composition root

Import `package:git_engine/git_engine.dart` for the contracts and value
types. Import `package:git_engine/process.dart` only where the application
constructs the process backend; take from it [ProcessGitEngine] and
[ProcessGitUploadPackService], then hold the constructed objects as
contracts.

[ProcessGitEngine] implements [GitRepositoryManager], [GitFileClient] and
[GitEngineRuntime]. Its constructor names the git program, the environment
layered over every command, the Windows long-path setting and the default
command delay. Giving a runner together with any of those options is
refused, because the runner already carries them.

[GitEngineRuntime] exposes the version facts a backend can report, through
engineVersion and ensureMinimumVersion. A backend without a notion of
version does not expose it. A timeout and an engine below the requested
minimum stay domain refusals of `git_engine.dart`, so portable code catches
them whatever the backend.

The process backend expects git 2.28 or newer. Its in-memory mergeTree needs
git 2.38 or newer; an older installation cannot run that operation and the
call is refused.

```dart
import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main() async {
  final ProcessGitEngine engine = ProcessGitEngine(
    executable: 'git',
    globalEnvironment: <String, String>{'GIT_CONFIG_NOSYSTEM': '1'},
    defaultTimeout: const Duration(minutes: 5),
  );
  final GitRepositoryManager repositories = engine;
  final GitFileClient client = engine;
  final GitEngineRuntime runtime = engine;
  print('${await runtime.engineVersion()}: $repositories $client');
}
```

## Repository hierarchy

The hierarchy classifies a repository by the capabilities it has.

- [GitRepository] is the base contract. It assumes no index, no work tree
  and no filesystem, and every repository exposes its domain accessors:
  config, remotes, branches, tags, refs, revisions, history, objects,
  tree patches, merge and reference transactions. It also offers
  withTemporaryIndex and pruneWorktrees.
- [GitIndexedRepository] adds an active [GitIndex] and the patch operations
  that compare with or apply to that index. An indexed view derived from a
  bare repository no longer carries the bare marker.
- [GitFileRepository] adds disk facts: path, gitDir and the plain files of
  the git directory through [GitDirectoryFiles].
- [GitWorkingRepository] implements both [GitIndexedRepository] and
  [GitFileRepository]. It is the only level with a work tree, adding
  toplevel, worktree, work-tree patches and in-place merge.
- [GitBareRepository] adds no operation. It marks a repository without a
  work tree, so a signature can require one; index work on it goes through
  an explicit index view.
- [GitFileBareRepository] combines bare storage with disk access. It is the
  type a server opens from disk.

## Opening and creating

Opening reads the repository kind from git, so a directory that is not a
repository fails immediately. `open` returns a [GitFileRepository] whose
precise type is either [GitWorkingRepository] or [GitFileBareRepository];
`openWorking` and `openBare` return that precise type when the caller
already knows it.

Creation fixes the type too: `init` returns a [GitWorkingRepository] with a
work tree, and `initBare` returns a [GitFileBareRepository]. A missing
target directory, missing parents included, is created; an existing empty
directory is used as it stands. A directory that already holds files is
refused before git runs unless `allowOccupied` hands it to git, which
reinitializes an existing repository and keeps its data. `initialBranch`
makes HEAD point at the named branch.

Cloning belongs to the client, not the manager: [GitFileClient] offers
`clone` and `cloneBare`. The short runnable examples are
`example/local_repository.dart` and `example/bare_repository.dart`.

```dart
import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main() async {
  final GitRepositoryManager repositories = ProcessGitEngine();
  final GitWorkingRepository working =
      await repositories.init('/srv/project', initialBranch: 'main');
  final GitFileRepository opened = await repositories.open(working.path);
  final GitFileBareRepository bare =
      await repositories.initBare('/srv/project.git', initialBranch: 'main');
  print('${opened.runtimeType} ${await bare.gitDir()}');
}
```
