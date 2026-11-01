# Changelog

## 1.0.0

Initial release.

- Typed Dart API backed by the installed Git executable, with value types and
  typed exceptions.
- Local working and bare repositories: initialization, objects, references,
  branches, tags, history, index, work tree, patches and merges.
- Remote client operations: clone, fetch, push and pull over local paths,
  file URLs, HTTP, HTTPS and SSH.
- Read-only smart HTTP server for clone and fetch, with a `dart:io` adapter,
  host-provided authentication and authorization, streaming and exchange limits.
- Backend-independent capability contracts and testing seams for process,
  file system and platform behavior.
- API documentation, guides and executable examples.
