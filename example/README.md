# Examples

Usage and explanations are in each Dart file.

| File | Usage |
| --- | --- |
| [git_engine_example.dart](git_engine_example.dart) | Self-contained local repository: create, commit, print the branch. |
| [local_repository.dart](local_repository.dart) | Local repository, commits, branches, tags, diff. |
| [client.dart](client.dart) | Clone, push, fetch and pull with a local origin. |
| [remote_client.dart](remote_client.dart) | Public HTTPS clone, fetch and pull; optional `--log file`. |
| [remote_tags.dart](remote_tags.dart) | Public HTTPS fetch of lightweight and annotated tags. |
| [smart_http_server.dart](smart_http_server.dart) | Read-only smart HTTP server. |
| [bare_repository.dart](bare_repository.dart) | Bare repository, temporary index, merge prediction. |

```sh
dart run example/git_engine_example.dart # self-contained example
dart run example/local_repository.dart   # local repository
dart run example/client.dart             # local client
dart run example/bare_repository.dart    # bare repository
dart run example/remote_client.dart      # requires internet
dart run example/remote_tags.dart        # requires internet
dart run tool/check_examples.dart        # runs the four local examples
```
