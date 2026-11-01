@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'preparation_support.dart';

void main() {
  late PreparationWorkdir workdir;
  late String originPath;

  setUp(() async {
    workdir = await PreparationWorkdir.create();
    originPath = await workdir.createOrigin(
      'origin',
      <String, String>{'README.md': '# repo\n'},
    );
  });

  group('preparing a working copy from a bare origin', () {
    test(
      'clones the origin and creates the work branch at the integration '
      'branch tip',
      () async {
        final String copyDir = copyPath(workdir, 'copy');

        final GitWorkingRepository copy = await workdir.engine.clone(
          originPath,
          copyDir,
        );
        await copy.worktree.checkoutNewBranch(
          'work-branch',
          startPoint: 'origin/main',
        );

        expect(await copy.branches.current(), 'work-branch');
        final GitFileBareRepository origin =
            await workdir.engine.openBare(originPath);
        expect(
          await copy.refs.resolveRef('refs/heads/work-branch'),
          await origin.refs.resolveRef('refs/heads/main'),
          reason: 'the work branch starts at the integration branch tip',
        );
        expect(contentOf(join(copyDir, 'README.md')), '# repo\n');
        expect(await copy.worktree.isClean(), isTrue);
      },
    );

    test('clones an origin that holds no commit yet (unborn HEAD)', () async {
      final String emptyOrigin =
          await workdir.createOrigin('empty-origin', null);
      final String copyDir = copyPath(workdir, 'empty-copy');

      final GitWorkingRepository copy = await workdir.engine.clone(
        emptyOrigin,
        copyDir,
      );

      expect(await copy.refs.resolveRef('HEAD'), isNull);
      expect(await copy.branches.current(), 'main');
      expect(await copy.worktree.isClean(), isTrue);
      expect(Directory(join(copyDir, '.git')).existsSync(), isTrue);
      expect(File(join(copyDir, 'README.md')).existsSync(), isFalse);
    });

    test('resolves a relative work directory to an absolute clone location',
        () async {
      final String unique =
          DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final String relativeRoot =
          join('.dart_tool', 'preparation_relative_$unique');
      final String relativeWork = join(relativeRoot, 'work');
      final String relativeCopy = join(relativeWork, 'copy');
      final Directory absoluteRoot =
          Directory(join(Directory.current.path, relativeRoot));
      addTearDown(() => deleteRecursively(absoluteRoot));

      final GitWorkingRepository copy = await workdir.engine.clone(
        originPath,
        relativeCopy,
      );

      expect(isAbsolutePath(copy.path), isTrue);
      expect(
        sameDirectory(copy.path, Directory(relativeCopy).absolute.path),
        isTrue,
      );
      expect(
        sameDirectory(
          await copy.toplevel(),
          Directory(relativeCopy).absolute.path,
        ),
        isTrue,
      );
      expect(contentOf(join(copy.path, 'README.md')), '# repo\n');
      expect(await copy.worktree.isClean(), isTrue);
      expect(
        Directory(
          join(Directory(relativeCopy).absolute.path, relativeRoot),
        ).existsSync(),
        isFalse,
        reason: 'git must not resolve the relative target against its own '
            'working directory, which would double the prefix',
      );
    });
  });
}
