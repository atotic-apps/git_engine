@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'preparation_support.dart';

void main() {
  late PreparationWorkdir workdir;

  setUp(() async {
    workdir = await PreparationWorkdir.create();
  });

  group('identity recorded in the local configuration', () {
    test('stays scoped to its own working copy', () async {
      final String originPath = await workdir.createOrigin(
        'origin',
        <String, String>{'README.md': '# repo\n'},
      );
      final GitWorkingRepository first = await workdir.engine.clone(
        originPath,
        join(workdir.root.path, 'first'),
      );
      final GitWorkingRepository second = await workdir.engine.clone(
        originPath,
        join(workdir.root.path, 'second'),
      );

      await first.config.set('user.name', 'First Worker');
      await first.config.set('user.email', 'first@preparation.test');

      expect(await first.config.get('user.name'), 'First Worker');
      expect(await first.config.get('user.email'), 'first@preparation.test');
      expect(await second.config.get('user.name'), isNull);
      expect(await second.config.get('user.email'), isNull);
    });
  });
}
