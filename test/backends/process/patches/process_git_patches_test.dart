import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/memory_working_repository.dart';
import '../support/scripted_git_runner.dart';

/// The temporary patch file [ProcessGitPatches.applyPatch] hands to
/// `git apply`, written through the injected file system and removed
/// afterwards, whatever the outcome.
///
/// Every scenario runs with the Windows and the POSIX path spelling, on any
/// machine, and never touches a disk.
void main() {
  final List<GitPlatform> platforms = <GitPlatform>[
    GitPlatform.windows,
    GitPlatform.linux,
  ];
  for (final GitPlatform platform in platforms) {
    group('applyPatch with ${platform.operatingSystem.name} paths', () {
      late MemoryGitFileSystem fileSystem;
      late ScriptedGitRunner scripted;
      late _ObservingRunner runner;
      late ProcessGitWorkingRepository repository;
      late String sandbox;
      late String patchFile;

      setUp(() {
        fileSystem = MemoryGitFileSystem();
        scripted = ScriptedGitRunner();
        runner = _ObservingRunner(scripted, fileSystem);
        repository = memoryWorkingRepository(
          runner,
          fileSystem,
          platform: platform,
        );
        sandbox = '/tmp/git_engine_patch_1';
        patchFile = platform.pathStyle.join(sandbox, 'patch.diff');
      });

      test('writes the patch to a temporary file and deletes it after success',
          () async {
        final List<int> patch = utf8.encode('diff --git a/a.txt b/a.txt\n');
        scripted.replyTo(
          <String>['apply', patchFile],
          GitRunResult.fromStrings(''),
        );

        final GitApplyResult result =
            await repository.patches.applyPatch(patch, const <String>[]);

        expect(result, isA<GitApplyApplied>());
        expect(
          runner.seenPatchBytes,
          patch,
          reason: 'git apply received the bytes written to the file',
        );
        expect(fileSystem.hasDirectory(sandbox), isFalse);
        expect(fileSystem.hasFile(patchFile), isFalse);
      });

      test('deletes the temporary file when git refuses the patch', () async {
        scripted.failWith(
          <String>['apply', patchFile],
          GitCommandException(
            arguments: const <String>['apply', 'patch.diff'],
            exitCode: 1,
            stderr: 'error: patch does not apply',
          ),
        );

        final GitApplyResult result = await repository.patches.applyPatch(
          utf8.encode('diff --git a/a.txt b/a.txt\n'),
          const <String>[],
        );

        expect(result, isA<GitApplyRefused>());
        expect(
          (result as GitApplyRefused).message,
          contains('patch does not apply'),
        );
        expect(fileSystem.hasDirectory(sandbox), isFalse);
      });

      test('deletes the temporary file when a three-way apply conflicts',
          () async {
        scripted.failWith(
          <String>['apply', '--3way', patchFile],
          GitCommandException(
            arguments: const <String>['apply', '--3way', 'patch.diff'],
            exitCode: 1,
            stderr: "Applied patch to 'a.txt' with conflicts.",
          ),
        );

        final GitApplyResult result = await repository.patches.applyPatch(
          utf8.encode('diff --git a/a.txt b/a.txt\n'),
          const <String>['--3way'],
        );

        expect(result, isA<GitApplyConflicted>());
        expect((result as GitApplyConflicted).paths, <String>['a.txt']);
        expect(fileSystem.hasDirectory(sandbox), isFalse);
      });
    });
  }

  group('change kind filters', () {
    const String fromValue = '1111111111111111111111111111111111111111';
    const String toValue = '2222222222222222222222222222222222222222';

    late ScriptedGitRunner scripted;
    late ProcessGitWorkingRepository repository;
    late GitOid from;
    late GitOid to;

    setUp(() {
      scripted = ScriptedGitRunner();
      repository = memoryWorkingRepository(
        scripted,
        MemoryGitFileSystem(),
      );
      from = GitOid.parse(fromValue);
      to = GitOid.parse(toValue);
    });

    test('maps each kind alone to its diff-filter letter', () async {
      for (final GitChangeKind kind in GitChangeKind.values) {
        final String letter = _filterLetters[kind]!;
        final List<String> arguments = <String>[
          'diff',
          '--name-only',
          '-z',
          ..._expectedFilterArguments(<GitChangeKind>{kind}, letter),
          fromValue,
          toValue,
        ];
        scripted.replyTo(arguments, GitRunResult.fromStrings(''));

        expect(
          await repository.patches.changedPaths(
            from,
            to,
            kinds: <GitChangeKind>{kind},
          ),
          isEmpty,
          reason: 'kind $kind',
        );
        expect(scripted.requests.last.arguments, arguments);
      }
    });

    test('combines kinds in enum order', () async {
      final List<String> arguments = <String>[
        'diff',
        '--name-only',
        '-z',
        ..._expectedFilterArguments(
          <GitChangeKind>{
            GitChangeKind.modified,
            GitChangeKind.added,
          },
          'AM',
        ),
        fromValue,
        toValue,
      ];
      scripted.replyTo(arguments, GitRunResult.fromStrings(''));

      await repository.patches.changedPaths(
        from,
        to,
        kinds: <GitChangeKind>{
          GitChangeKind.modified,
          GitChangeKind.added,
        },
      );

      expect(scripted.requests.last.arguments, arguments);
    });

    test('enables rename and copy detection when asked', () async {
      final List<String> arguments = <String>[
        'diff',
        '--name-only',
        '-z',
        ..._expectedFilterArguments(
          <GitChangeKind>{
            GitChangeKind.added,
            GitChangeKind.copied,
          },
          'AC',
        ),
        fromValue,
        toValue,
      ];
      scripted.replyTo(arguments, GitRunResult.fromStrings(''));

      await repository.patches.changedPaths(
        from,
        to,
        kinds: <GitChangeKind>{
          GitChangeKind.added,
          GitChangeKind.copied,
        },
      );

      expect(scripted.requests.last.arguments, arguments);
    });

    test('places the filter in every comparison', () async {
      const String treeValue = '3333333333333333333333333333333333333333';
      final GitOid tree = GitOid.parse(treeValue);
      final List<String> filter = _expectedFilterArguments(
        <GitChangeKind>{GitChangeKind.modified},
        'M',
      );
      final List<List<String>> commands = <List<String>>[
        <String>[
          'diff',
          '--name-only',
          '-z',
          ...filter,
          '--cached',
          treeValue,
        ],
        <String>['diff', '--name-only', '-z', ...filter],
        <String>['diff', '--name-only', '-z', ...filter, treeValue],
      ];
      for (final List<String> arguments in commands) {
        scripted.replyTo(arguments, GitRunResult.fromStrings(''));
      }

      expect(
        await repository.patches.changedPathsAgainstIndex(
          tree,
          kinds: <GitChangeKind>{GitChangeKind.modified},
        ),
        isEmpty,
      );
      expect(
        await repository.patches.changedPathsAgainstWorkTree(
          kinds: <GitChangeKind>{GitChangeKind.modified},
        ),
        isEmpty,
      );
      expect(
        await repository.patches.changedPathsFromTree(
          tree,
          kinds: <GitChangeKind>{GitChangeKind.modified},
        ),
        isEmpty,
      );
    });

    test('leaves the filter out when kinds is null and sorts the paths',
        () async {
      scripted.replyTo(
        <String>['diff', '--name-only', '-z', fromValue, toValue],
        GitRunResult.fromStrings(
          'b/x.txt\u0000b.x.txt\u0000b-x.txt\u0000a-b/c.txt\u0000b.x.txt\u0000',
        ),
      );

      expect(
        await repository.patches.changedPaths(from, to),
        <String>['a-b/c.txt', 'b-x.txt', 'b.x.txt', 'b/x.txt'],
      );
    });

    test('refuses an empty kind set before running a command', () async {
      const String treeValue = '3333333333333333333333333333333333333333';
      final GitOid tree = GitOid.parse(treeValue);
      const Set<GitChangeKind> none = <GitChangeKind>{};

      await expectLater(
        repository.patches.changedPaths(from, to, kinds: none),
        throwsArgumentError,
      );
      await expectLater(
        repository.patches.changedPathsAgainstIndex(tree, kinds: none),
        throwsArgumentError,
      );
      await expectLater(
        repository.patches.changedPathsAgainstWorkTree(kinds: none),
        throwsArgumentError,
      );
      await expectLater(
        repository.patches.changedPathsFromTree(tree, kinds: none),
        throwsArgumentError,
      );
      expect(scripted.requests, isEmpty);
    });
  });

  group('applyable patch arguments', () {
    const String fromValue = '1111111111111111111111111111111111111111';
    const String toValue = '2222222222222222222222222222222222222222';
    const String treeValue = '3333333333333333333333333333333333333333';
    const List<String> options = <String>[
      '--binary',
      '--full-index',
      '--no-color',
      '--no-textconv',
      '--no-ext-diff',
      '--src-prefix=a/',
      '--dst-prefix=b/',
    ];

    late ScriptedGitRunner scripted;
    late ProcessGitWorkingRepository repository;
    late GitOid from;
    late GitOid to;
    late GitOid tree;

    setUp(() {
      scripted = ScriptedGitRunner();
      repository = memoryWorkingRepository(
        scripted,
        MemoryGitFileSystem(),
      );
      from = GitOid.parse(fromValue);
      to = GitOid.parse(toValue);
      tree = GitOid.parse(treeValue);
    });

    test('binaryDiff ignores the repository diff configuration', () async {
      final List<String> arguments = <String>[
        'diff',
        ...options,
        fromValue,
        toValue,
      ];
      scripted.replyTo(arguments, GitRunResult.fromStrings('patch'));

      expect(
        await repository.patches.binaryDiff(from, to),
        utf8.encode('patch'),
      );
      expect(scripted.requests.last.arguments, arguments);
    });

    test('binaryDiffAgainstIndex ignores the repository diff configuration',
        () async {
      final List<String> arguments = <String>[
        'diff',
        ...options,
        '--cached',
        treeValue,
      ];
      scripted.replyTo(arguments, GitRunResult.fromStrings('patch'));

      expect(
        await repository.patches.binaryDiffAgainstIndex(tree),
        utf8.encode('patch'),
      );
      expect(scripted.requests.last.arguments, arguments);
    });

    test('binaryDiffAgainstWorkTree ignores the repository diff configuration',
        () async {
      final List<String> arguments = <String>['diff', ...options];
      scripted.replyTo(arguments, GitRunResult.fromStrings('patch'));

      expect(
        await repository.patches.binaryDiffAgainstWorkTree(),
        utf8.encode('patch'),
      );
      expect(scripted.requests.last.arguments, arguments);
    });

    test('binaryDiffFromTree ignores the repository diff configuration',
        () async {
      final List<String> arguments = <String>[
        'diff',
        ...options,
        treeValue,
      ];
      scripted.replyTo(arguments, GitRunResult.fromStrings('patch'));

      expect(
        await repository.patches.binaryDiffFromTree(tree),
        utf8.encode('patch'),
      );
      expect(scripted.requests.last.arguments, arguments);
    });
  });
}

/// Git's diff-filter letter for each change kind, as the process backend
/// emits them.
const Map<GitChangeKind, String> _filterLetters = <GitChangeKind, String>{
  GitChangeKind.added: 'A',
  GitChangeKind.copied: 'C',
  GitChangeKind.deleted: 'D',
  GitChangeKind.modified: 'M',
  GitChangeKind.renamed: 'R',
  GitChangeKind.typeChanged: 'T',
  GitChangeKind.unmerged: 'U',
};

/// Arguments the process backend must emit for [kinds], whose diff-filter
/// letters are [letters].
List<String> _expectedFilterArguments(
  Set<GitChangeKind> kinds,
  String letters,
) {
  return <String>[
    '--diff-filter=$letters',
    if (kinds.contains(GitChangeKind.renamed) ||
        kinds.contains(GitChangeKind.copied))
      '-M',
    if (kinds.contains(GitChangeKind.copied)) '--find-copies-harder',
  ];
}

/// A runner that records the patch file content before every command and
/// delegates the answer to a scripted runner.
final class _ObservingRunner implements GitRunner {
  _ObservingRunner(this._scripted, this._fileSystem);

  final ScriptedGitRunner _scripted;
  final MemoryGitFileSystem _fileSystem;

  /// Bytes of the temporary patch file the last `apply` command received.
  Uint8List? seenPatchBytes;

  @override
  Future<GitRunResult> run(GitRunRequest request) {
    if (request.arguments.isNotEmpty && request.arguments.first == 'apply') {
      final String path = request.arguments.last;
      seenPatchBytes = _fileSystem.fileContent(path);
    }
    return _scripted.run(request);
  }
}
