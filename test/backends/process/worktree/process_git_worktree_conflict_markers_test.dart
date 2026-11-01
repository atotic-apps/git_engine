import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/src/backends/process/worktree/process_git_worktree.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/memory_working_repository.dart';
import '../support/scripted_git_runner.dart';

/// [ProcessGitWorktree.scanConflictMarkers] reading a work tree held in the
/// injected file system.
///
/// Complete blocks are reported, an isolated separator or an unterminated
/// block is not, carriage returns are tolerated, and absent paths are skipped.
/// Every scenario runs with the Windows and the POSIX path spelling, on any
/// machine, and never touches a disk.
void main() {
  final List<GitPlatform> platforms = <GitPlatform>[
    GitPlatform.windows,
    GitPlatform.linux,
  ];
  for (final GitPlatform platform in platforms) {
    group('scanConflictMarkers with ${platform.operatingSystem.name} paths',
        () {
      late MemoryGitFileSystem fileSystem;
      late ScriptedGitRunner runner;
      late ProcessGitWorkingRepository repository;
      late String workTree;

      String joinPath(String base, String relative) =>
          platform.pathStyle.join(base, relative);

      setUp(() {
        fileSystem = MemoryGitFileSystem();
        runner = ScriptedGitRunner();
        repository = memoryWorkingRepository(
          runner,
          fileSystem,
          platform: platform,
        );
        workTree = repository.path;
        runner.replyTo(
          const <String>['rev-parse', '--show-toplevel'],
          GitRunResult.fromStrings(workTree),
        );
      });

      void seedWorkTreeFile(String path, String content) {
        fileSystem.seedFile(joinPath(workTree, path), utf8.encode(content));
      }

      test('reports a complete block with its three lines', () async {
        seedWorkTreeFile(
          'notes.txt',
          <String>[
            'before',
            '<<<<<<< HEAD',
            'at work',
            '=======',
            'on the branch',
            '>>>>>>> topic',
            'after',
          ].join('\n'),
        );

        final List<GitConflictRegion> regions =
            await repository.worktree.scanConflictMarkers(
          <String>['notes.txt'],
        );

        expect(regions, hasLength(1));
        expect(regions.single.path, 'notes.txt');
        expect(regions.single.startLine, 2);
        expect(regions.single.separatorLine, 4);
        expect(regions.single.endLine, 6);
      });

      test('never reports a lone separator', () async {
        seedWorkTreeFile(
          'notes.txt',
          <String>['a chosen side', '=======', 'a plain rule'].join('\n'),
        );

        expect(
          await repository.worktree.scanConflictMarkers(<String>['notes.txt']),
          isEmpty,
        );
      });

      test('never reports an unterminated block', () async {
        seedWorkTreeFile(
          'notes.txt',
          <String>['<<<<<<< HEAD', 'at work', '=======', 'on the branch']
              .join('\n'),
        );

        expect(
          await repository.worktree.scanConflictMarkers(<String>['notes.txt']),
          isEmpty,
        );
      });

      test('reads blocks written with carriage returns', () async {
        seedWorkTreeFile(
          'windows.txt',
          <String>[
            '<<<<<<< HEAD',
            'at work',
            '=======',
            'on the branch',
            '>>>>>>> topic',
          ].join('\r\n'),
        );

        final List<GitConflictRegion> regions =
            await repository.worktree.scanConflictMarkers(
          <String>['windows.txt'],
        );

        expect(regions, hasLength(1));
        expect(regions.single.startLine, 1);
        expect(regions.single.endLine, 5);
      });

      test('skips paths the file system does not hold', () async {
        seedWorkTreeFile(
          'present.txt',
          <String>['<<<<<<< HEAD', 'at work', '=======', 'there', '>>>>>>> t']
              .join('\n'),
        );

        final List<GitConflictRegion> regions =
            await repository.worktree.scanConflictMarkers(
          <String>['gone.txt', 'present.txt', 'alsonot.txt'],
        );

        expect(regions, hasLength(1));
        expect(regions.single.path, 'present.txt');
      });

      test('refuses paths outside the work tree without reading them',
          () async {
        seedWorkTreeFile(
          '../outside.txt',
          <String>[
            '<<<<<<< HEAD',
            'at work',
            '=======',
            'on the branch',
            '>>>>>>> topic',
          ].join('\n'),
        );
        seedWorkTreeFile(
          'present.txt',
          <String>['<<<<<<< HEAD', 'at work', '=======', 'there', '>>>>>>> t']
              .join('\n'),
        );
        final List<String> refused = <String>[
          '',
          platform.pathStyle.isWindows ? r'C:\outside.txt' : '/outside.txt',
          '../outside.txt',
          'a/../b',
          './a',
          'a//b',
          r'a\b',
          'nul\u0000byte',
          if (platform.pathStyle.isWindows) ...<String>[
            r'\\server\share\outside.txt',
            'CON',
            'aux.txt',
            'a.',
            'a:b',
          ],
        ];

        for (final String path in refused) {
          await expectLater(
            repository.worktree.scanConflictMarkers(
              <String>['present.txt', path],
            ),
            throwsA(isA<GitException>()),
            reason: 'the path "$path" must be refused',
          );
        }

        expect(
          runner.requests,
          isEmpty,
          reason: 'the whole call is refused before anything is read',
        );
      });

      test('ignores a final link and a linked directory', () async {
        final String block = <String>[
          '<<<<<<< HEAD',
          'at work',
          '=======',
          'on the branch',
          '>>>>>>> topic',
        ].join('\n');
        seedWorkTreeFile('../outside.txt', block);
        seedWorkTreeFile('../outside/inside.txt', block);
        fileSystem.seedLink(
          joinPath(workTree, 'linked.txt'),
          joinPath(workTree, '../outside.txt'),
        );
        fileSystem.seedLink(
          joinPath(workTree, 'linked-dir'),
          joinPath(workTree, '../outside'),
        );

        final List<GitConflictRegion> regions =
            await repository.worktree.scanConflictMarkers(
          <String>['linked.txt', 'linked-dir/inside.txt'],
        );

        expect(regions, isEmpty);
      });
    });
  }

  group('scanConflictRegions', () {
    test('scans 200 000 starts without separator in linear time', () {
      final Uint8List bytes = utf8.encode(
        List<String>.filled(200000, '<<<<<<< HEAD').join('\n'),
      );
      final Stopwatch watch = Stopwatch()..start();
      final List<GitConflictRegion> regions =
          ProcessGitWorktree.scanConflictRegions('many.txt', bytes);
      watch.stop();

      expect(regions, isEmpty);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('scans 100 000 pairs without closing tail in linear time', () {
      final List<String> lines = <String>[];
      for (var index = 0; index < 100000; index++) {
        lines
          ..add('<<<<<<< HEAD')
          ..add('=======');
      }
      final Uint8List bytes = utf8.encode(lines.join('\n'));
      final Stopwatch watch = Stopwatch()..start();
      final List<GitConflictRegion> regions =
          ProcessGitWorktree.scanConflictRegions('pairs.txt', bytes);
      watch.stop();

      expect(regions, isEmpty);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('matches the per-line reference walk on generated markers', () {
      final Random random = Random(20261029);
      final List<String> pool = <String>[
        '<<<<<<< HEAD',
        '<<<<<<< topic',
        '<<<<<<<',
        '=======',
        '========',
        '======= label',
        '>>>>>>> topic',
        '>>>>>>>',
        '>>>>>>> label',
        'ordinary text',
        '',
        ' <<<<<<< indented',
        '<<<<<<<x',
        '>>>>>>>x',
      ];
      for (var round = 0; round < 20; round++) {
        final String content = List<String>.generate(
          250,
          (int index) => pool[random.nextInt(pool.length)],
        ).join('\n');
        final Uint8List bytes = utf8.encode(content);

        expect(
          _signature(ProcessGitWorktree.scanConflictRegions('f.txt', bytes)),
          _signature(_referenceRegions('f.txt', bytes)),
          reason: 'round $round',
        );
      }
    });
  });
}

/// The fields of [regions], in order, as comparable text.
List<String> _signature(List<GitConflictRegion> regions) {
  return <String>[
    for (final GitConflictRegion region in regions)
      '${region.path}:${region.startLine}:${region.separatorLine}:'
          '${region.endLine}',
  ];
}

/// The per-line walk the linear scanner replaced, kept to compare results.
List<GitConflictRegion> _referenceRegions(String path, Uint8List bytes) {
  final RegExp start = RegExp(r'^<{7}( .*)?$');
  final RegExp separator = RegExp(r'^={7}$');
  final RegExp end = RegExp(r'^>{7}( .*)?$');
  final List<String> lines = utf8
      .decode(bytes, allowMalformed: true)
      .split('\n')
      .map((String line) =>
          line.endsWith('\r') ? line.substring(0, line.length - 1) : line)
      .toList();
  final List<GitConflictRegion> regions = <GitConflictRegion>[];
  var index = 0;
  while (index < lines.length) {
    if (!start.hasMatch(lines[index])) {
      index++;
      continue;
    }
    var separatorLine = index + 1;
    while (separatorLine < lines.length &&
        !separator.hasMatch(lines[separatorLine])) {
      separatorLine++;
    }
    if (separatorLine >= lines.length) {
      index++;
      continue;
    }
    var endLine = separatorLine + 1;
    while (endLine < lines.length && !end.hasMatch(lines[endLine])) {
      endLine++;
    }
    if (endLine >= lines.length) {
      index++;
      continue;
    }
    regions.add(GitConflictRegion(
      path: path,
      startLine: index + 1,
      separatorLine: separatorLine + 1,
      endLine: endLine + 1,
    ));
    index = endLine + 1;
  }
  return regions;
}
