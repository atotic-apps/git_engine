@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import 'worktree_test_support.dart';

/// Scanning work tree files for real conflict markers: the blocks of a
/// conflicted merge are reported line by line, while a lone `=======`
/// separator, a bare `<<<<<<<` without a closing tail, and ordinary text are
/// never reported.
void main() {
  late TestRepository repo;
  late ProcessGitWorkingRepository repository;

  setUp(() async {
    repo = await createTestRepository();
    repository = await openAt(repo);
  });

  /// Writes [content] into the work tree of [repo] as [path].
  void writeWorkTreeFile(String path, String content) {
    repo.writeFile(path, content);
  }

  test('reports the blocks of a conflicted merge with their lines', () async {
    await commitFile(repo, 'shared.txt', 'base\n', 'base');
    await repo.runGit(const <String>['checkout', '-b', 'other']);
    await commitFile(repo, 'shared.txt', 'other\n', 'other');
    await repo.runGit(const <String>['checkout', 'main']);
    await commitFile(repo, 'shared.txt', 'main\n', 'main');

    final GitMergeResult result = await repository.merge.merge('other');
    expect(result, isA<GitMergeConflicts>());
    final List<String> conflicted =
        (result as GitMergeConflicts).conflictingFiles.toList();

    final List<GitConflictRegion> regions =
        await repository.worktree.scanConflictMarkers(conflicted);

    expect(regions, hasLength(1));
    expect(regions.single.path, 'shared.txt');
    expect(regions.single.startLine, 1);
    expect(regions.single.separatorLine, 3);
    expect(regions.single.endLine, 5);
  });

  test('never reports a lone separator or an unterminated start', () async {
    writeWorkTreeFile(
      'notes.txt',
      <String>[
        'a chosen side',
        '=======',
        'a plain rule',
        '<<<<<<< there',
        'a bare start',
      ].join('\n'),
    );

    expect(
      await repository.worktree.scanConflictMarkers(<String>['notes.txt']),
      isEmpty,
    );
  });

  test('reports complete blocks, labels included, several per file', () async {
    writeWorkTreeFile(
      'notes.txt',
      <String>[
        '<<<<<<< HEAD',
        'first at work',
        '=======',
        'first on the branch',
        '>>>>>>> topic',
        'between the blocks',
        '<<<<<<< HEAD',
        'second at work',
        '=======',
        'second on the branch',
        '>>>>>>> topic',
      ].join('\n'),
    );

    final List<GitConflictRegion> regions =
        await repository.worktree.scanConflictMarkers(<String>['notes.txt']);

    expect(regions, hasLength(2));
    expect(regions[0].startLine, 1);
    expect(regions[0].separatorLine, 3);
    expect(regions[0].endLine, 5);
    expect(regions[1].startLine, 7);
    expect(regions[1].separatorLine, 9);
    expect(regions[1].endLine, 11);
  });

  test('reads files with carriage returns and skips unreadable paths',
      () async {
    writeWorkTreeFile(
      'windows.txt',
      <String>[
        '<<<<<<< HEAD',
        'at work',
        '=======',
        'on the branch',
        '>>>>>>> topic',
      ].join('\r\n'),
    );

    final List<String> scanned = <String>[
      'gone.txt',
      'windows.txt',
      'alsonot.txt',
    ];
    final List<GitConflictRegion> regions =
        await repository.worktree.scanConflictMarkers(scanned);

    expect(regions, hasLength(1));
    expect(regions.single.path, 'windows.txt');
    expect(regions.single.startLine, 1);
    expect(regions.single.endLine, 5);
  });

  test('keeps the order of the paths it was given', () async {
    writeWorkTreeFile(
      'b-second.txt',
      <String>['<<<<<<< HEAD', 'at work', '=======', 'there', '>>>>>>> t']
          .join('\n'),
    );
    writeWorkTreeFile(
      'a-first.txt',
      <String>['<<<<<<< HEAD', 'at work', '=======', 'there', '>>>>>>> t']
          .join('\n'),
    );

    final List<String> ordered = <String>[
      'b-second.txt',
      'a-first.txt',
    ];
    final List<GitConflictRegion> regions =
        await repository.worktree.scanConflictMarkers(ordered);

    expect(
      regions.map((GitConflictRegion region) => region.path).toList(),
      <String>['b-second.txt', 'a-first.txt'],
    );
  });

  test('never scans a link to a file outside the work tree', () async {
    final File outside = repo.sandboxFile('outside-markers.txt');
    outside.writeAsStringSync(<String>[
      '<<<<<<< HEAD',
      'at work',
      '=======',
      'on the branch',
      '>>>>>>> topic',
    ].join('\n'));
    final Link link = Link(
      TestRepository.join(repo.directory.path, 'linked.txt'),
    );
    try {
      link.createSync(outside.path);
    } on FileSystemException {
      markTestSkipped(
        'the environment cannot create a symbolic link or a junction',
      );
      return;
    }
    addTearDown(() {
      if (FileSystemEntity.typeSync(link.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        link.deleteSync();
      }
    });

    expect(
      await repository.worktree.scanConflictMarkers(<String>['linked.txt']),
      isEmpty,
    );
  });
}
