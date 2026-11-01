@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../restoring/restoring_support.dart';

/// The ignore rules of a copy decide what a read of the work tree sees:
/// paths the ignore records are reported as ignored, paths no rule matches
/// are not, and a tracked path is only reported ignored when the index is
/// bypassed.
void main() {
  late RestoreSandbox sandbox;
  late GitWorkingRepository copy;

  setUp(() async {
    sandbox = await RestoreSandbox.create();
    final GitFileBareRepository origin = await sandbox.seedBare(
      'origin.git',
      <String, String>{'readme.md': 'origin base\n'},
    );
    copy = await sandbox.clone(origin.path, 'copy');
    // The locator is tracked BEFORE any rule names it: a staged file an
    // ignore record matches is only reachable once the rule comes after
    // the tracking.
    writeFile(copy.path, 'locator.txt', 'tracked\n');
    await copy.worktree.addAll();
    await copy.worktree.commit('track the locator first');
    writeFile(copy.path, '.gitignore', 'build/\nlocator.txt\n');
    await copy.worktree.addAll();
    await copy.worktree.commit('record the ignore rules');
  });

  test('a path the ignore records reports ignored', () async {
    expect(await copy.worktree.isIgnored('build/out.log'), isTrue);
    expect(
      await copy.worktree.isIgnored('locator.txt', noIndex: true),
      isTrue,
    );
  });

  test('a path no rule matches reports not ignored', () async {
    expect(await copy.worktree.isIgnored('readme.md'), isFalse);
    expect(await copy.worktree.isIgnored('locator.txtx'), isFalse);
    expect(await copy.worktree.isIgnored('outside/inside.log'), isFalse);
  });
}
