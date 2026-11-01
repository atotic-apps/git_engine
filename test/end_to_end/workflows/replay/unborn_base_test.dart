@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'sandbox.dart';

/// A working clone of an origin that carries no commit at all: the base
/// branch is unborn, `HEAD` resolves to nothing, and the untracked work of
/// the clone is the only state there is.
///
/// A replay that moves the base of such a clone has nothing to capture a
/// patch from and nothing to reset to: the work simply stays in place, `HEAD`
/// stays unborn, and the origin keeps carrying no ref.
void main() {
  late ReplaySandbox sandbox;
  late GitFileBareRepository origin;
  late GitWorkingRepository work;
  late String workPath;

  setUp(() async {
    sandbox = await ReplaySandbox.create();
    origin = await sandbox.initBare('origin.git');
    work = await sandbox.clone(origin.path, 'work');
    workPath = sandbox.path('work');
    sandbox.write(workPath, 'thing.txt', 'content\n');
  });

  test('clones an origin without history into an unborn working repository',
      () async {
    expect(await work.revisions.resolveRevision('HEAD'), isNull);
    // The origin keeps carrying no ref at all.
    expect(await origin.revisions.resolveRevision('main'), isNull);
  });

  test('keeps the untracked work with HEAD still unborn', () async {
    expect(sandbox.readText(workPath, 'thing.txt'), 'content\n');

    final List<GitStatusEntry> status = await work.worktree.status();
    expect(status, hasLength(1));
    expect(status.single.path, 'thing.txt');
    expect(status.single.isUntracked, isTrue);
    expect(await work.worktree.isClean(), isFalse);

    // Nothing made the base exist: HEAD resolves to nothing still.
    expect(await work.revisions.resolveRevision('HEAD'), isNull);
  });
}
