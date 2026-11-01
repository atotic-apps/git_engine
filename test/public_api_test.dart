import 'dart:io';

import 'package:test/test.dart';

/// Public API contract of `git_engine`.
///
/// `lib/git_engine.dart` exposes the backend-independent production API: the
/// engine and repository interfaces, the typed errors, the value types, the
/// server contracts and the smart HTTP processing. The process backend entry
/// points live in `package:git_engine/process.dart`, the `dart:io` HTTP
/// server adapter lives in `package:git_engine/server_io.dart`, and the rules
/// shared by the engines maintained with the package live in
/// `package:git_engine/backend.dart`, with no stability guarantee during 0.x.
/// `lib/testing.dart` exposes the seams where the platform leaves the
/// package: the gathered-command runner (`GitRunner`, `GitRunRequest`,
/// `GitRunResult`), the streaming launcher (`GitProcessLauncher`,
/// `GitProcessLaunchRequest`, `GitLaunchedProcess`), the file operations
/// (`GitFileSystem`, `GitFileSystemEntry`, with `MemoryGitFileSystem` as an
/// in-memory implementation) and the platform description (`GitPlatform`,
/// `GitPathStyle`, `GitOperatingSystem`).
///
/// Every export directive carries an explicit `show` list, and no exported
/// name matches a name from `dart:core`, `dart:async`, `dart:io`,
/// `dart:convert` or `dart:typed_data`.
const List<String> _expectedPublicNames = <String>[
  'GitEngineRuntime',
  'GitFileClient',
  'GitRepositoryManager',
  'GitBareRepository',
  'GitFileBareRepository',
  'GitFileRepository',
  'GitIndexedRepository',
  'GitRepository',
  'GitRepositoryReader',
  'GitRepositoryWriter',
  'GitWorkingRepository',
  'GitAuthenticationException',
  'GitEngineUnavailableException',
  'GitException',
  'GitFeatureUnavailableException',
  'GitNotABareRepositoryException',
  'GitNoUpstreamException',
  'GitNotARepositoryException',
  'GitNotAWorkingRepositoryException',
  'GitOccupiedDirectoryException',
  'GitOutputLimitException',
  'GitRemoteRepositoryNotFoundException',
  'GitRemoteUnreachableException',
  'GitRepositoryKindException',
  'GitTimeoutException',
  'GitUnsupportedUrlException',
  'GitVersionException',
  'GitApplyApplied',
  'GitApplyConflicted',
  'GitApplyRefused',
  'GitApplyResult',
  'GitArchiveFormat',
  'GitBranch',
  'GitBranches',
  'GitBranchNotMergedException',
  'GitChangeKind',
  'GitCommit',
  'GitConflictRegion',
  'GitConfigEntry',
  'GitDirectoryDrift',
  'GitDirectoryFiles',
  'GitDirectorySnapshot',
  'GitIdentity',
  'GitLogCommit',
  'GitLogEntry',
  'GitMergeMode',
  'GitMergeCommit',
  'GitMergeConflicts',
  'GitMergeFastForward',
  'GitMergeResult',
  'GitMergeStopped',
  'GitMergeUpToDate',
  'GitMergeTreeResult',
  'GitObjectType',
  'GitOid',
  'GitRawObject',
  'GitRef',
  'GitRefExistsException',
  'GitRefNotFoundException',
  'GitRefReader',
  'GitRefMismatchException',
  'GitRefTransaction',
  'GitRefs',
  'GitRevisionResolver',
  'GitRevisions',
  'GitUnknownRevisionException',
  'GitStatusEntry',
  'GitTag',
  'GitTagFetch',
  'GitTagRef',
  'GitTags',
  'GitTree',
  'GitTreeEntry',
  'GitUnmergedEntry',
  'GitHistory',
  'GitHistoryReader',
  'GitIndex',
  'GitMerge',
  'GitMergeNotFastForwardException',
  'GitNoMergeInProgressException',
  'GitUnrelatedHistoriesException',
  'GitWorkingMerge',
  'GitInvalidObjectException',
  'GitObjectReader',
  'GitObjectStore',
  'GitObjectWriter',
  'GitObjects',
  'GitInvalidRefNameException',
  'GitIndexedPatches',
  'GitPatches',
  'GitWorkingPatches',
  'GitConfig',
  'GitPushRejectedException',
  'GitRemoteRefNotFoundException',
  'GitRemotes',
  'GitFileState',
  'GitLocalChangesOverwrittenException',
  'GitResetMode',
  'GitWorktree',
  'GitAuthorizationPolicy',
  'GitReadOnlyAuthorizationPolicy',
  'GitHttpBodyDecoder',
  'GitHttpHeaders',
  'GitHttpRequest',
  'GitHttpResponse',
  'GitPrincipal',
  'GitProtocolParameters',
  'GitServedRepositoryId',
  'GitServiceResponse',
  'GitSmartHttpHandler',
  'GitUnknownServedRepositoryException',
  'GitUploadPackService',
];

/// Names exported by `lib/testing.dart`, the seams where the platform
/// leaves the package: gathered commands, streaming processes, file
/// operations and platform facts.
const List<String> _expectedTestingNames = <String>[
  'GitRunner',
  'GitRunRequest',
  'GitRunResult',
  'GitProcessLauncher',
  'GitProcessLaunchRequest',
  'GitLaunchedProcess',
  'GitFileSystem',
  'GitFileSystemEntry',
  'MemoryGitFileSystem',
  'GitPlatform',
  'GitPathStyle',
  'GitOperatingSystem',
];

/// Names exported by `lib/server_io.dart`, the `dart:io` server entry point:
/// the HTTP transport adapter and the gzip body decoder it supplies.
const List<String> _expectedServerIoNames = <String>[
  'DartIoGitHttpServer',
  'dartIoGzipBodyDecoder',
];

/// Names exported by `lib/backend.dart`, the engine-author entry point: the
/// common remote-location refusal, the reference-name rules, the argument and
/// URL redaction helpers, the relative-path check and the diagnostic chain
/// bound.
const List<String> _expectedBackendNames = <String>[
  'checkRemoteLocation',
  'maxDiagnosticChainLength',
  'redactGitArguments',
  'redactUrlUserinfo',
  'relativePathError',
  'checkBranchName',
  'checkTagName',
  'checkWritableRefName',
  'readsAsOption',
  'refuseOptionLikeRevision',
];

/// Every name shown by an export directive of [source], in order.
List<String> _exportedNames(String source) {
  final RegExp exportPattern = RegExp(
    r"export\s+'[^']+'\s+show\s+([^;]+);",
    multiLine: true,
  );
  final List<String> names = <String>[];
  for (final RegExpMatch export in exportPattern.allMatches(source)) {
    for (final String part in export.group(1)!.split(',')) {
      final String name = part.trim();
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
  }
  return names;
}

/// Whether every export directive of [source] carries a `show` list.
bool _allExportsShowTheirNames(String source) {
  final int exports =
      RegExp(r'^export\s+', multiLine: true).allMatches(source).length;
  final int shown = RegExp(
    r"^export\s+'[^']+'\s+show\s+[^;]+;",
    multiLine: true,
  ).allMatches(source).length;
  return exports == shown;
}

void main() {
  test('git_engine.dart exports exactly its documented public names', () {
    final String source = File('lib/git_engine.dart').readAsStringSync();

    expect(
      _exportedNames(source),
      unorderedEquals(_expectedPublicNames),
      reason: 'the production API is a closed list',
    );
  });

  test('testing.dart exports exactly the platform seams', () {
    final String source = File('lib/testing.dart').readAsStringSync();

    expect(
      _exportedNames(source),
      unorderedEquals(_expectedTestingNames),
      reason: 'the test seam is limited to commands, streaming processes, file '
          'operations and platform facts',
    );
  });

  test('server_io.dart exports exactly the dart:io server entry points', () {
    final String source = File('lib/server_io.dart').readAsStringSync();

    expect(
      _exportedNames(source),
      unorderedEquals(_expectedServerIoNames),
      reason: 'the dart:io server entry point is a closed list',
    );
  });

  test('backend.dart exports exactly the shared engine rules', () {
    final String source = File('lib/backend.dart').readAsStringSync();

    expect(
      _exportedNames(source),
      unorderedEquals(_expectedBackendNames),
      reason: 'the engine-author entry point is a closed list and exports no '
          'backend type',
    );
  });

  test(
    'every export of all public libraries carries an explicit show list',
    () {
      for (final String path in <String>[
        'lib/backend.dart',
        'lib/git_engine.dart',
        'lib/process.dart',
        'lib/server_io.dart',
        'lib/testing.dart',
      ]) {
        expect(
          _allExportsShowTheirNames(File(path).readAsStringSync()),
          isTrue,
          reason: '$path must name every symbol it exports',
        );
      }
    },
  );
}
