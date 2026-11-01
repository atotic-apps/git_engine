/// Checks the git behaviour a bare repository relies on: explicit-index
/// applies, soft resets, merge-tree output, ref transactions and symbolic
/// references.
///
/// Every repository is prepared through the shared test support and git is
/// always launched through `ProcessGitRunner`.
@Tags(['git'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import 'support/test_repository.dart';

void main() {
  group('bare repository capabilities', () {
    test('apply --cached updates an explicit index and write-tree sees it',
        () async {
      final _BareFixture fixture = await _createFixture();
      final String index = fixture.newIndexPath('explicit');

      await fixture.loadIndex(index, 'main');
      await fixture.gitWithIndex(
        <String>['apply', '--cached', fixture.featureAPatchPath],
        index,
      );
      final String tree =
          (await fixture.gitWithIndex(<String>['write-tree'], index))
              .stdout
              .trim();

      expect(
        await fixture.blobAt(tree, 'conflict.txt'),
        await fixture.blobAt('feature-a', 'conflict.txt'),
      );
      expect(_hasFileNamed(fixture.barePath, 'index'), isFalse);
    });

    test('apply --cached --3way leaves conflicts in an explicit index',
        () async {
      final _BareFixture fixture = await _createFixture();
      final String index = fixture.newIndexPath('three-way');

      await fixture.loadIndex(index, 'feature-b');
      final GitCommandException failure = await _failure(
        fixture.gitWithIndex(
          <String>['apply', '--cached', '--3way', fixture.featureAPatchPath],
          index,
        ),
      );

      // apply --cached --3way merges into the index, records the three stages
      // of conflict.txt, and exits 1. It is not a flat refusal.
      expect(failure.exitCode, 1);
      expect(failure.stderr, contains('with conflicts'));

      final String unmerged =
          (await fixture.gitWithIndex(<String>['ls-files', '-u'], index))
              .stdout;
      final Map<int, String> stageBlobs = _unmergedStages(unmerged);
      expect(stageBlobs.keys, unorderedEquals(<int>[1, 2, 3]));
      expect(stageBlobs[1], await fixture.blobAt(fixture.base, 'conflict.txt'));
      expect(
        stageBlobs[2],
        await fixture.blobAt('feature-b', 'conflict.txt'),
      );
      expect(
        stageBlobs[3],
        await fixture.blobAt('feature-a', 'conflict.txt'),
      );
      expect(_hasFileNamed(fixture.barePath, 'index'), isFalse);
    });

    test('apply --cached without GIT_INDEX_FILE uses the implicit index',
        () async {
      final _BareFixture fixture = await _createFixture();

      // A fresh bare clone has no index. git does not create one from nothing:
      // apply --cached reads it as empty and refuses a patch that modifies a
      // path, without writing $GIT_DIR/index.
      expect(File(TestRepository.join(fixture.barePath, 'index')).existsSync(),
          isFalse);
      final GitCommandException failure = await _failure(
        fixture.git(<String>['apply', '--cached', fixture.featureAPatchPath]),
      );
      expect(failure.exitCode, 1);
      expect(failure.stderr, contains('does not exist in index'));
      expect(File(TestRepository.join(fixture.barePath, 'index')).existsSync(),
          isFalse);

      // Once $GIT_DIR/index exists, git uses it implicitly: read-tree creates
      // it and apply --cached without GIT_INDEX_FILE rewrites its content.
      await fixture.git(<String>['read-tree', 'feature-b']);
      expect(File(TestRepository.join(fixture.barePath, 'index')).existsSync(),
          isTrue);
      await fixture.git(
        <String>['apply', '--cached', fixture.toBasePatchPath],
      );

      final String tree =
          (await fixture.git(<String>['write-tree'])).stdout.trim();
      expect(
        await fixture.blobAt(tree, 'conflict.txt'),
        await fixture.blobAt(fixture.base, 'conflict.txt'),
      );
      expect(File(TestRepository.join(fixture.barePath, 'index')).existsSync(),
          isTrue);
    });

    test('reset --soft moves the branch HEAD points at', () async {
      final _BareFixture fixture = await _createFixture();
      expect(await fixture.oid('refs/heads/main'), fixture.base);

      await fixture.git(<String>['reset', '--soft', 'feature-a']);

      expect(await fixture.oid('refs/heads/main'), fixture.featureA);
      expect(
        (await fixture.git(<String>['symbolic-ref', 'HEAD'])).stdout.trim(),
        'refs/heads/main',
      );
    });

    test('mixed reset is refused in a bare repository', () async {
      final _BareFixture fixture = await _createFixture();

      final GitCommandException failure = await _failure(
          fixture.git(<String>['reset', '--mixed', 'feature-a']));

      expect(failure.exitCode, 128);
      expect(
        failure.stderr,
        contains('mixed reset is not allowed in a bare repository'),
      );
      expect(await fixture.oid('refs/heads/main'), fixture.base);
    });

    test('merge-tree --write-tree --name-only reports clean and conflict',
        () async {
      final _BareFixture fixture = await _createFixture();

      // main is an ancestor of feature-a: the merge is clean, exit 0, and the
      // only stdout line is the resulting tree.
      final GitRunResult clean = await fixture.git(<String>[
        'merge-tree',
        '--write-tree',
        '--name-only',
        'main',
        'feature-a',
      ]);
      final List<String> cleanLines = clean.stdout.trim().split('\n');
      expect(cleanLines, hasLength(1));
      expect(
        (await fixture.git(<String>['cat-file', '-t', cleanLines.single]))
            .stdout
            .trim(),
        'tree',
      );
      expect(
        await fixture.blobAt(cleanLines.single, 'conflict.txt'),
        await fixture.blobAt('feature-a', 'conflict.txt'),
      );

      // Conflicting branches exit 1 and still print a tree: the first stdout
      // line is the tree, then the conflicted path names, then git's messages.
      final GitCommandException conflict = await _failure(fixture.git(<String>[
        'merge-tree',
        '--write-tree',
        '--name-only',
        'feature-a',
        'feature-b',
      ]));
      expect(conflict.exitCode, 1);
      expect(conflict.stderr, isEmpty);
      final List<String> lines = conflict.stdout.trim().split('\n');
      expect(lines.first, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(lines[1], 'conflict.txt');
      expect(conflict.stdout, contains('CONFLICT (content)'));
      expect(
        (await fixture.git(<String>['cat-file', '-t', lines.first]))
            .stdout
            .trim(),
        'tree',
      );
    });

    test('update-ref --stdin applies a prepared transaction atomically',
        () async {
      final _BareFixture fixture = await _createFixture();

      final GitRunResult applied = await fixture.git(
        <String>['update-ref', '--stdin'],
        stdin: _stdin(<String>[
          'start',
          'update refs/heads/main ${fixture.featureA} ${fixture.base}',
          'create refs/heads/temp ${fixture.featureB}',
          'prepare',
          'commit',
        ]),
      );
      expect(applied.stdout, contains('commit: ok'));
      expect(await fixture.oid('refs/heads/main'), fixture.featureA);
      expect(await fixture.oid('refs/heads/temp'), fixture.featureB);

      // A wrong expected old value makes prepare fail with exit 128; neither
      // update of the transaction is applied.
      final GitCommandException refused = await _failure(
        fixture.git(
          <String>['update-ref', '--stdin'],
          stdin: _stdin(<String>[
            'start',
            'update refs/heads/main ${fixture.base} ${fixture.featureB}',
            'create refs/heads/should-not-exist ${fixture.featureA}',
            'prepare',
            'commit',
          ]),
        ),
      );
      expect(refused.exitCode, 128);
      expect(refused.stderr, contains('cannot lock ref'));
      expect(await fixture.oid('refs/heads/main'), fixture.featureA);
      final GitCommandException missing = await _failure(
        fixture.git(<String>[
          'rev-parse',
          '--verify',
          'refs/heads/should-not-exist',
        ]),
      );
      expect(missing.exitCode, 128);
    });

    test('symbolic-ref HEAD reads the target of the symbolic reference',
        () async {
      final _BareFixture fixture = await _createFixture();

      final GitRunResult result =
          await fixture.git(<String>['symbolic-ref', 'HEAD']);

      expect(result.stdout.trim(), 'refs/heads/main');
    });
  });
}

/// A repository with three commits — a base and two branches changing the same
/// line — plus a bare clone of it and the patches the tests apply.
final class _BareFixture {
  _BareFixture({
    required this.repository,
    required this.barePath,
    required this.base,
    required this.featureA,
    required this.featureB,
    required this.featureAPatchPath,
    required this.toBasePatchPath,
  });

  final TestRepository repository;
  final String barePath;
  final String base;
  final String featureA;
  final String featureB;
  final String featureAPatchPath;
  final String toBasePatchPath;

  /// Runs git inside the bare clone.
  Future<GitRunResult> git(
    List<String> arguments, {
    Map<String, String> environment = const <String, String>{},
    Uint8List? stdin,
  }) {
    return repository.runGit(
      arguments,
      workingDirectory: barePath,
      environment: environment,
      stdin: stdin,
    );
  }

  /// Runs git inside the bare clone with [index] as its explicit index.
  Future<GitRunResult> gitWithIndex(List<String> arguments, String index) {
    return git(
      arguments,
      environment: <String, String>{'GIT_INDEX_FILE': index},
    );
  }

  /// Loads [rev]'s tree into the explicit index.
  Future<void> loadIndex(String index, String rev) async {
    await gitWithIndex(<String>['read-tree', rev], index);
  }

  /// A fresh index path in the sandbox, outside the bare repository.
  String newIndexPath(String name) {
    return repository.sandboxFile('$name.index').path;
  }

  /// Object name [rev] resolves to.
  Future<String> oid(String rev) async {
    return (await git(<String>['rev-parse', rev])).stdout.trim();
  }

  /// Object name of [path] inside [rev].
  Future<String> blobAt(String rev, String path) async {
    return (await git(<String>['rev-parse', '$rev:$path'])).stdout.trim();
  }
}

Future<_BareFixture> _createFixture() async {
  final TestRepository repo = await createTestRepository();
  repo.writeFile('conflict.txt', 'one\ntwo\nthree\n');
  await repo.runGit(<String>['add', '--', 'conflict.txt']);
  await repo.runGit(<String>['commit', '-m', 'base']);
  final String base = await _revParse(repo, repo.directory.path, 'HEAD');

  await repo.runGit(<String>['checkout', '-b', 'feature-a']);
  repo.writeFile('conflict.txt', 'one\nfeature a\nthree\n');
  await repo.runGit(<String>['add', '--', 'conflict.txt']);
  await repo.runGit(<String>['commit', '-m', 'feature a']);
  final String featureA = await _revParse(repo, repo.directory.path, 'HEAD');

  await repo.runGit(<String>['checkout', 'main']);
  await repo.runGit(<String>['checkout', '-b', 'feature-b']);
  repo.writeFile('conflict.txt', 'one\nfeature b\nthree\n');
  await repo.runGit(<String>['add', '--', 'conflict.txt']);
  await repo.runGit(<String>['commit', '-m', 'feature b']);
  final String featureB = await _revParse(repo, repo.directory.path, 'HEAD');

  await repo.runGit(<String>['checkout', 'main']);

  final String barePath = TestRepository.join(repo.sandbox.path, 'bare.git');
  await repo.runGit(
    <String>['clone', '--bare', '--', repo.directory.path, barePath],
    workingDirectory: repo.sandbox.path,
  );

  final String featureAPatchPath =
      repo.sandboxFile('main-to-feature-a.patch').path;
  final String featureAPatch = (await repo.runGit(
    <String>['diff', 'main', 'feature-a', '--', 'conflict.txt'],
    workingDirectory: barePath,
  ))
      .stdout;
  expect(featureAPatch, isNotEmpty);
  File(featureAPatchPath).writeAsStringSync(featureAPatch);

  final String toBasePatchPath =
      repo.sandboxFile('feature-b-to-base.patch').path;
  final String toBasePatch = (await repo.runGit(
    <String>['diff', 'feature-b', base, '--', 'conflict.txt'],
    workingDirectory: barePath,
  ))
      .stdout;
  expect(toBasePatch, isNotEmpty);
  File(toBasePatchPath).writeAsStringSync(toBasePatch);

  return _BareFixture(
    repository: repo,
    barePath: barePath,
    base: base,
    featureA: featureA,
    featureB: featureB,
    featureAPatchPath: featureAPatchPath,
    toBasePatchPath: toBasePatchPath,
  );
}

Future<String> _revParse(
  TestRepository repo,
  String directory,
  String rev,
) async {
  return (await repo.runGit(
    <String>['rev-parse', rev],
    workingDirectory: directory,
  ))
      .stdout
      .trim();
}

/// Runs [action] and returns the git failure it must produce.
Future<GitCommandException> _failure(Future<Object?> action) async {
  try {
    await action;
  } on GitCommandException catch (error) {
    return error;
  }
  fail('expected the git command to fail, but it succeeded');
}

/// Maps unmerged stage numbers to object names from `ls-files -u` output.
Map<int, String> _unmergedStages(String unmerged) {
  final Map<int, String> stages = <int, String>{};
  for (final String line in unmerged.trim().split('\n')) {
    final int tab = line.indexOf('\t');
    final List<String> fields = line.substring(0, tab).split(' ');
    stages[int.parse(fields[2])] = fields[1];
  }
  return stages;
}

/// Whether [directory] holds a file named [name], at any depth.
bool _hasFileNamed(String directory, String name) {
  return Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .any((File file) => file.path.split(Platform.pathSeparator).last == name);
}

/// Bytes of a `update-ref --stdin` script, one command per line.
Uint8List _stdin(List<String> lines) {
  return Uint8List.fromList(utf8.encode('${lines.join('\n')}\n'));
}
