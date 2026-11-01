# Compatibility

This page is the only statement of the package's compatibility policy.

## Platforms and toolchain

The package runs on the Dart VM on Linux, macOS and Windows and requires Dart
SDK `^3.3.0`. The process backend needs git 2.28 or newer, the release that
provides `init --initial-branch`; reference transactions already need 2.27.
`GitMerge.mergeTree` needs git 2.38 or newer (`merge-tree --write-tree`).
Browsers are not supported, and the `dart:io` server adapter targets the Dart
VM.

## Versioned libraries

`package:git_engine/git_engine.dart`, `package:git_engine/process.dart`,
`package:git_engine/server_io.dart` and `package:git_engine/testing.dart`
follow semantic versioning.

`package:git_engine/backend.dart` serves the engines maintained with the
package and stays outside that promise.

Everything under `lib/src/` is private.

## Capability contracts

These small shapes are implemented outside the package by a backend or a host.
They grow only in a major version, by a new interface that extends the old one.

Repository-side contracts:

- [GitObjectReader], [GitObjectWriter], [GitObjectStore], [GitRefReader].
- [GitRevisionResolver], [GitHistoryReader], [GitRefTransaction].
- [GitRepositoryReader], [GitRepositoryWriter].

Server-side contracts:

- [GitPrincipal], [GitAuthorizationPolicy], [GitServiceResponse].
- [GitUploadPackService], [GitHttpRequest].

## Facades

Facades aggregate capabilities and convenience methods. Members may be added to
them in a minor version, and they are not meant to be implemented outside the
package.

- The repository hierarchy: [GitRepository], [GitIndexedRepository],
  [GitFileRepository].
- [GitWorkingRepository], [GitBareRepository], [GitFileBareRepository].
- [GitRepositoryManager], [GitFileClient], [GitEngineRuntime],
  [GitSmartHttpHandler].
- Repository configuration: [GitConfig], [GitRemotes].
- Branches and tags: [GitBranches], [GitTags], [GitRefs].
- Revisions and history: [GitRevisions], [GitHistory].
- Objects and index: [GitObjects], [GitIndex].
- Work tree and patches: [GitWorktree], [GitPatches], [GitIndexedPatches].
- [GitWorkingPatches], [GitMerge], [GitWorkingMerge], [GitDirectoryFiles].

## Incompatible changes

An incompatible change waits for a major version and goes through deprecations
first.
