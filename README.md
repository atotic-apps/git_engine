# git_engine

`git_engine` is a typed Dart API over the installed git executable. Operations
return Dart values and report refusals as typed exceptions, so callers never
parse command output or exit codes.

## Installation

Add the package from pub.dev:

```sh
dart pub add git_engine
```

## Quick start

```dart
import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main() async {
  final ProcessGitEngine engine = ProcessGitEngine();
  final GitWorkingRepository repository =
      await engine.init('path/to/repo', initialBranch: 'main');
  print(await repository.branches.current());
}
```

Run it from the package root with `dart run example/git_engine_example.dart`,
a self-contained example that creates a temporary repository and commits a
file.

## Roles

| Role | Import | Guide | Example |
| --- | --- | --- | --- |
| Local repository | `package:git_engine/git_engine.dart`, `package:git_engine/process.dart` | [Getting started](doc/getting_started.md) | [git_engine_example.dart](example/git_engine_example.dart) |
| Client | `package:git_engine/git_engine.dart`, `package:git_engine/process.dart` | [Client role](doc/client.md) | [client.dart](example/client.dart) |
| Server | `package:git_engine/git_engine.dart`, `package:git_engine/process.dart`, `package:git_engine/server_io.dart` | [Serving repositories](doc/serving.md) | [smart_http_server.dart](example/smart_http_server.dart) |
| Tests | `package:git_engine/testing.dart` | [Testing](doc/testing.md) | [local_repository.dart](example/local_repository.dart) |

More examples: [bare_repository.dart](example/bare_repository.dart),
[remote_client.dart](example/remote_client.dart) and
[remote_tags.dart](example/remote_tags.dart).

## Prerequisites

- git 2.28 or newer; `GitMerge.mergeTree` needs git 2.38 or newer.
- Dart SDK `^3.3.0`.
- Linux, macOS or Windows.

## What it does not do

- It does not implement git: it starts the installed executable and ships no git or libgit2 code.
- It does not supply credentials; git uses the host's authentication setup.
- It does not wrap submodules, bisect, stash or notes.
- It never prompts by default: git terminal prompts are off and SSH runs in batch mode (see [Client role](doc/client.md)).
- Its configuration API only touches repository-local settings.

## Documentation

- [Getting started](doc/getting_started.md)
- [Client role](doc/client.md)
- [Serving repositories](doc/serving.md)
- [Errors](doc/errors.md)
- [Testing](doc/testing.md)
- [Compatibility](doc/compatibility.md)
- [Examples](example/README.md)

## License

MIT — see [LICENSE](LICENSE).

The package contains no code from git or libgit2, both GPLv2: it only starts
the installed `git` executable.
