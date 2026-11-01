@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'sandbox.dart';

/// Path history between two commits of one branch: which commits touched
/// which file, between a base and a tip, with nothing when the range holds no
/// commit for the path.
///
/// The commits come back newest first for every requested path, so a consumer
/// knows which landed change last moved the file it conflicts on.
void main() {
  late ReplaySandbox sandbox;
  late GitWorkingRepository repository;
  late GitOid base;

  setUp(() async {
    sandbox = await ReplaySandbox.create();
    repository = await sandbox.initWorking('repo');
    base = await sandbox.commit(
      repository,
      <String, String>{'a.txt': 'a0\n', 'b.txt': 'b0\n', 'c.txt': 'c0\n'},
      'base',
    );
  });

  test('lists no commit for any path when the range is empty', () async {
    expect(
      await repository.history.commitsTouching(
        'a.txt',
        from: base.value,
        to: base.value,
      ),
      isEmpty,
    );
    expect(
      await repository.history.commitsTouching(
        'b.txt',
        from: base.value,
        to: base.value,
      ),
      isEmpty,
    );
    expect(
      await repository.history.commitsTouching(
        'c.txt',
        from: base.value,
        to: base.value,
      ),
      isEmpty,
    );
  });
}
