import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';
import 'patches_contract_support.dart';

const List<ScenarioCommit> _scenario = <ScenarioCommit>[
  ScenarioCommit(
    message: 'Add a',
    files: <String, String>{'a.txt': 'a\n'},
  ),
  ScenarioCommit(
    message: 'Change a and add b',
    files: <String, String>{'a.txt': 'a changed\n', 'b.txt': 'b\n'},
  ),
  ScenarioCommit(
    message: 'Add accented content',
    files: <String, String>{'accent.txt': 'café\nnaïve\n'},
  ),
  ScenarioCommit(
    message: 'Change accented content',
    files: <String, String>{'accent.txt': 'café\nnaïf\n'},
  ),
];

/// Declares the comparisons of the three patch facades for [factory].
///
/// Tree-to-tree comparisons run on a working and on a bare clone, since every
/// repository carries them. Tree-to-index comparisons run on a working clone;
/// the apply contract also exercises them through an explicit index on a bare
/// repository. Index-to-work-tree comparisons run on a working clone, the only
/// kind with a work tree.
void defineGitPatchesContract(BackendFactory factory) {
  group('GitPatches', () {
    _defineTreeComparisons(
      'on a working clone',
      factory.createRepositoryFromScenario,
    );
    _defineTreeComparisons(
      'on a bare clone',
      factory.createBareRepositoryFromScenario,
    );
    _defineIndexComparisons(factory);
    _defineWorkTreeComparisons(factory);
    _defineKindComparisons(factory);
  });
}

void _defineTreeComparisons(
  String description,
  Future<ScenarioRepository> Function(List<ScenarioCommit>) create,
) {
  group('tree comparisons $description', () {
    late ScenarioRepository scenario;
    late GitPatches patches;

    setUp(() async {
      scenario = await create(_scenario);
      patches = scenario.repository.patches;
    });

    test('lists the paths changed between two trees', () async {
      expect(
        await patches.changedPaths(scenario.commits[0], scenario.commits[1]),
        <String>['a.txt', 'b.txt'],
      );
      expect(
        await patches.changedPaths(scenario.commits[1], scenario.commits[0]),
        <String>['a.txt', 'b.txt'],
      );
    });

    test('filters changed paths by kind', () async {
      expect(
        await patches.changedPaths(
          scenario.commits[0],
          scenario.commits[1],
          kinds: <GitChangeKind>{GitChangeKind.modified},
        ),
        <String>['a.txt'],
      );
      expect(
        await patches.changedPaths(
          scenario.commits[0],
          scenario.commits[1],
          kinds: <GitChangeKind>{GitChangeKind.added},
        ),
        <String>['b.txt'],
      );
      expect(
        await patches.changedPaths(
          scenario.commits[0],
          scenario.commits[1],
          kinds: <GitChangeKind>{
            GitChangeKind.added,
            GitChangeKind.modified,
          },
        ),
        <String>['a.txt', 'b.txt'],
      );
      expect(
        await patches.changedPaths(scenario.commits[0], scenario.commits[1]),
        <String>['a.txt', 'b.txt'],
      );
    });

    test('decodes accented text diffs as UTF-8', () async {
      final String diff = await patches.textDiff(
        scenario.commits[2],
        scenario.commits[3],
      );

      expect(diff, startsWith('diff --git a/accent.txt b/accent.txt'));
      expect(diff, contains('-naïve'));
      expect(diff, contains('+naïf'));
      expect(diff, contains('café'));
    });

    test('restricts a text diff to the given paths', () async {
      final String diff = await patches.textDiff(
        scenario.commits[0],
        scenario.commits[1],
        paths: <String>['a.txt'],
      );

      expect(diff, contains('a.txt'));
      expect(diff, isNot(contains('b.txt')));
      expect(diff, contains('-a\n'));
      expect(diff, contains('+a changed\n'));
    });

    test('returns the raw bytes of a binary diff', () async {
      final Uint8List patch = await patches.binaryDiff(
        scenario.commits[0],
        scenario.commits[1],
      );

      expect(patch, isNotEmpty);
      expect(
        utf8.decode(patch, allowMalformed: true),
        contains('diff --git a/a.txt b/a.txt'),
      );
    });
  });
}

void _defineIndexComparisons(BackendFactory factory) {
  group('tree-to-index comparisons', () {
    late GitWorkingRepository repository;

    setUp(() async {
      repository = await factory.createWorkingRepository();
    });

    test('lists staged changes against a tree', () async {
      final GitOid head = await commitFiles(
          repository, <String, Object>{'a.txt': 'a\n'}, 'base');
      writeRepoFile(repository.path, 'a.txt', 'a changed\n');
      writeRepoFile(repository.path, 'new.txt', 'new\n');
      await repository.worktree.add(<String>['a.txt', 'new.txt']);

      expect(
        await repository.patches.changedPathsAgainstIndex(head),
        <String>['a.txt', 'new.txt'],
      );
      expect(
        await repository.patches.changedPathsAgainstWorkTree(),
        isEmpty,
      );
    });

    test('decodes an accented tree-to-index diff as UTF-8', () async {
      final GitOid head = await commitFiles(
        repository,
        <String, Object>{'accent.txt': 'café\nnaïve\n'},
        'base',
      );
      writeRepoFile(repository.path, 'accent.txt', 'café\nnaïf\n');
      await repository.worktree.add(<String>['accent.txt']);

      final String diff = await repository.patches.textDiffAgainstIndex(head);

      expect(diff, contains('-naïve'));
      expect(diff, contains('+naïf'));
      expect(diff, contains('café'));
    });

    test('returns the raw bytes of a tree-to-index binary diff', () async {
      final GitOid head = await commitFiles(
        repository,
        <String, Object>{
          'data.bin': <int>[0, 1]
        },
        'base',
      );
      writeRepoFile(repository.path, 'data.bin', <int>[0, 2]);
      await repository.worktree.add(<String>['data.bin']);

      final Uint8List patch =
          await repository.patches.binaryDiffAgainstIndex(head);

      expect(
        utf8.decode(patch),
        contains('GIT binary patch'),
      );
      expect(
        await repository.patches.binaryDiffAgainstWorkTree(),
        isEmpty,
      );
    });

    test('restricts a tree-to-index diff to the given paths', () async {
      final GitOid head = await commitFiles(
        repository,
        <String, Object>{'a.txt': 'a\n', 'b.txt': 'b\n'},
        'base',
      );
      writeRepoFile(repository.path, 'a.txt', 'a changed\n');
      writeRepoFile(repository.path, 'b.txt', 'b changed\n');
      await repository.worktree.add(<String>['a.txt', 'b.txt']);

      final String diff = await repository.patches.textDiffAgainstIndex(
        head,
        paths: <String>['a.txt'],
      );

      expect(diff, contains('a.txt'));
      expect(diff, isNot(contains('b.txt')));
    });
  });
}

void _defineWorkTreeComparisons(BackendFactory factory) {
  group('index-to-work-tree comparisons', () {
    late GitWorkingRepository repository;

    setUp(() async {
      repository = await factory.createWorkingRepository();
    });

    test('lists work tree changes relative to the index', () async {
      await commitFiles(
        repository,
        <String, Object>{'a.txt': 'a\n', 'b.txt': 'b\n'},
        'add both',
      );
      writeRepoFile(repository.path, 'b.txt', 'b changed\n');
      writeRepoFile(repository.path, 'c.txt', 'untracked\n');

      expect(
        await repository.patches.changedPathsAgainstWorkTree(),
        <String>['b.txt'],
      );
    });

    test('compares a tree with the work tree from a GitOid', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{'a.txt': 'a\n'},
        'base',
      );
      writeRepoFile(repository.path, 'a.txt', 'a changed\n');

      expect(
        await repository.patches.changedPathsFromTree(base),
        <String>['a.txt'],
      );
      final String diff = await repository.patches.textDiffFromTree(base);
      expect(diff, contains('-a\n'));
      expect(diff, contains('+a changed\n'));
    });

    test('shows staged and unstaged changes separately', () async {
      await commitFiles(
        repository,
        <String, Object>{'a.txt': 'a\n'},
        'base',
      );
      writeRepoFile(repository.path, 'a.txt', 'a staged\n');
      await repository.worktree.add(<String>['a.txt']);
      writeRepoFile(repository.path, 'a.txt', 'a staged again\n');

      final String staged = await repository.patches.textDiffAgainstIndex(
        (await repository.revisions.resolveRevision('HEAD'))!,
      );
      final String workTree =
          await repository.patches.textDiffAgainstWorkTree();

      expect(staged, contains('+a staged\n'));
      expect(staged, isNot(contains('a staged again')));
      expect(workTree, contains('+a staged again'));
    });

    test('keeps only unmerged paths with the unmerged kind', () async {
      await createMergeConflict(repository);

      expect(
        await repository.patches.changedPathsAgainstWorkTree(
          kinds: <GitChangeKind>{GitChangeKind.unmerged},
        ),
        <String>['conflict.txt'],
      );
      expect(
        await repository.patches.changedPathsAgainstWorkTree(
          kinds: <GitChangeKind>{GitChangeKind.added},
        ),
        isEmpty,
      );
    });

    test('decodes accented work tree content as UTF-8', () async {
      await commitFiles(
        repository,
        <String, Object>{'accent.txt': 'café\nnaïve\n'},
        'base',
      );
      writeRepoFile(repository.path, 'accent.txt', 'café\nnaïf\n');

      final String diff = await repository.patches.textDiffAgainstWorkTree();

      expect(diff, startsWith('diff --git a/accent.txt b/accent.txt'));
      expect(diff, contains('-naïve'));
      expect(diff, contains('+naïf'));
      expect(diff, contains('café'));
    });

    test('returns raw bytes holding the binary patch', () async {
      await commitFiles(
        repository,
        <String, Object>{
          'data.bin': <int>[0, 1, 2, 0, 255]
        },
        'base',
      );
      writeRepoFile(repository.path, 'data.bin', <int>[0, 9, 8, 0, 254, 1]);

      final Uint8List patch =
          await repository.patches.binaryDiffAgainstWorkTree();

      expect(patch, isNotEmpty);
      final String text = utf8.decode(patch, allowMalformed: true);
      expect(text, contains('diff --git a/data.bin b/data.bin'));
      expect(text, contains('GIT binary patch'));
    });

    test('returns a binary tree diff for a changed binary file', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{
          'data.bin': <int>[0, 1, 2, 0, 255]
        },
        'base',
      );
      final GitOid next = await commitFiles(
        repository,
        <String, Object>{
          'data.bin': <int>[0, 9, 8, 0, 254, 1]
        },
        'next',
      );

      final Uint8List patch = await repository.patches.binaryDiff(base, next);

      expect(
        utf8.decode(patch, allowMalformed: true),
        contains('GIT binary patch'),
      );
    });
  });
}

void _defineKindComparisons(BackendFactory factory) {
  group('changed path kinds', () {
    late GitWorkingRepository repository;

    setUp(() async {
      repository = await factory.createWorkingRepository();
    });

    test('keeps only added paths', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{'keep.txt': 'keep\n'},
        'base',
      );
      writeRepoFile(repository.path, 'new.txt', 'new\n');
      await repository.worktree.addAll();
      final GitOid next = await repository.worktree.commit('add');

      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{GitChangeKind.added},
        ),
        <String>['new.txt'],
      );
      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{GitChangeKind.modified},
        ),
        isEmpty,
      );
    });

    test('keeps only deleted paths', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{'gone.txt': 'gone\n', 'keep.txt': 'keep\n'},
        'base',
      );
      File(joinPath(repository.path, 'gone.txt')).deleteSync();
      await repository.worktree.addAll();
      final GitOid next = await repository.worktree.commit('delete');

      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{GitChangeKind.deleted},
        ),
        <String>['gone.txt'],
      );
      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{GitChangeKind.added},
        ),
        isEmpty,
      );
    });

    test('keeps only modified paths', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{'file.txt': 'one\n'},
        'base',
      );
      writeRepoFile(repository.path, 'file.txt', 'two\n');
      await repository.worktree.addAll();
      final GitOid next = await repository.worktree.commit('modify');

      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{GitChangeKind.modified},
        ),
        <String>['file.txt'],
      );
      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{GitChangeKind.deleted},
        ),
        isEmpty,
      );
    });

    test('keeps only renamed paths', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{'old.txt': 'same content\n'},
        'base',
      );
      File(joinPath(repository.path, 'old.txt'))
          .renameSync(joinPath(repository.path, 'new.txt'));
      await repository.worktree.addAll();
      final GitOid next = await repository.worktree.commit('rename');

      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{GitChangeKind.renamed},
        ),
        <String>['new.txt'],
      );
      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{GitChangeKind.added},
        ),
        isEmpty,
      );
    });

    test('keeps only copied paths', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{'source.txt': 'copied content\n'},
        'base',
      );
      writeRepoFile(repository.path, 'copy.txt', 'copied content\n');
      await repository.worktree.addAll();
      final GitOid next = await repository.worktree.commit('copy');

      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{GitChangeKind.copied},
        ),
        <String>['copy.txt'],
      );
      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{GitChangeKind.modified},
        ),
        isEmpty,
      );
    });

    test('keeps only type changes', () async {
      final GitOid blob = await repository.objects.writeObject(
        GitObjectType.blob,
        ascii.encode('content\n'),
      );
      final GitOid link = await repository.objects.writeObject(
        GitObjectType.blob,
        ascii.encode('target\n'),
      );
      final GitOid fileTree = await repository.objects.writeObject(
        GitObjectType.tree,
        _treeEntryBytes('100644', 'link.txt', blob),
      );
      final GitOid linkTree = await repository.objects.writeObject(
        GitObjectType.tree,
        _treeEntryBytes('120000', 'link.txt', link),
      );

      expect(
        await repository.patches.changedPaths(
          fileTree,
          linkTree,
          kinds: <GitChangeKind>{GitChangeKind.typeChanged},
        ),
        <String>['link.txt'],
      );
      expect(
        await repository.patches.changedPaths(
          fileTree,
          linkTree,
          kinds: <GitChangeKind>{GitChangeKind.modified},
        ),
        isEmpty,
      );
    });

    test('combines several kinds', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{
          'gone.txt': 'gone\n',
          'mod.txt': 'one\n',
          'moved.txt': 'moved content\n',
        },
        'base',
      );
      File(joinPath(repository.path, 'gone.txt')).deleteSync();
      writeRepoFile(repository.path, 'mod.txt', 'two\n');
      writeRepoFile(repository.path, 'new.txt', 'new\n');
      File(joinPath(repository.path, 'moved.txt'))
          .renameSync(joinPath(repository.path, 'renamed.txt'));
      await repository.worktree.addAll();
      final GitOid next = await repository.worktree.commit('mixed');

      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{
            GitChangeKind.added,
            GitChangeKind.deleted,
          },
        ),
        <String>['gone.txt', 'new.txt'],
      );
      expect(
        await repository.patches.changedPaths(
          base,
          next,
          kinds: <GitChangeKind>{
            GitChangeKind.modified,
            GitChangeKind.renamed,
          },
        ),
        <String>['mod.txt', 'renamed.txt'],
      );
      expect(
        await repository.patches.changedPaths(base, next),
        <String>['gone.txt', 'mod.txt', 'new.txt', 'renamed.txt'],
      );
    });

    test('refuses an empty kind set', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{'file.txt': 'one\n'},
        'base',
      );
      final GitOid tree = await repository.index.writeTree();
      const Set<GitChangeKind> none = <GitChangeKind>{};

      await expectLater(
        repository.patches.changedPaths(base, base, kinds: none),
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
        repository.patches.changedPathsFromTree(base, kinds: none),
        throwsArgumentError,
      );
    });

    test('sorts paths by UTF-8 bytes beside subdirectories', () async {
      final GitOid base = await commitFiles(
        repository,
        <String, Object>{'seed.txt': 'seed\n'},
        'base',
      );
      writeRepoFile(repository.path, 'b/x.txt', 'sub\n');
      writeRepoFile(repository.path, 'b-x.txt', 'dash\n');
      writeRepoFile(repository.path, 'b.x.txt', 'dot\n');
      writeRepoFile(repository.path, 'a-b/c.txt', 'nested\n');
      await repository.worktree.addAll();
      final GitOid next = await repository.worktree.commit('order');

      expect(
        await repository.patches.changedPaths(base, next),
        <String>['a-b/c.txt', 'b-x.txt', 'b.x.txt', 'b/x.txt'],
      );
    });
  });
}

/// Serialized content of a tree object holding a single entry.
List<int> _treeEntryBytes(String mode, String name, GitOid oid) {
  return <int>[
    ...ascii.encode('$mode $name\u0000'),
    ..._hexBytes(oid.value),
  ];
}

/// The bytes represented by the hexadecimal object name [value].
List<int> _hexBytes(String value) {
  final List<int> bytes = <int>[];
  for (var index = 0; index < value.length; index += 2) {
    bytes.add(int.parse(value.substring(index, index + 2), radix: 16));
  }
  return bytes;
}
