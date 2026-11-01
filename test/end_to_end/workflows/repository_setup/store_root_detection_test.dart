@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'repository_setup_support.dart';

/// Where a repository is found from a path inside it: a nested directory of a
/// bare store resolves the store, and a nested directory of a work tree
/// resolves the work tree root.
void main() {
  late SetupArea area;

  setUp(() async {
    area = await SetupArea.create();
  });

  test('a directory nested in a bare store resolves the store itself',
      () async {
    final String storePath = area.path('store');
    await area.engine.initBare(storePath, initialBranch: 'main');
    final String nested = join(storePath, 'objects');
    expect(Directory(nested).existsSync(), isTrue,
        reason: 'a bare store always carries an objects directory');

    final GitRepository resolved = await area.engine.open(nested);

    expect(resolved, isA<GitBareRepository>());
    expect(resolved, isNot(isA<GitWorkingRepository>()));
    expect(
      sameDirectory(await (resolved as GitFileRepository).gitDir(), storePath),
      isTrue,
      reason: 'git climbs out of the nested directory to the store root',
    );
    expect(await area.engine.openBare(nested), isA<GitFileBareRepository>());
  });

  test('a directory nested in a work tree resolves the work tree root',
      () async {
    final GitWorkingRepository working =
        await area.engine.init(area.path('work'), initialBranch: 'main');
    final String nested = join(working.path, 'sub');
    Directory(nested).createSync();

    final GitWorkingRepository resolved = await area.engine.openWorking(nested);

    expect(resolved, isA<GitWorkingRepository>());
    expect(resolved, isNot(isA<GitBareRepository>()));
    expect(
      sameDirectory(await resolved.toplevel(), working.path),
      isTrue,
      reason: 'git climbs out of the nested directory to the work tree root',
    );
  });
}
