import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the `GitConfig.getAll` contract against [factory].
///
/// Every case runs on the local configuration of a fresh working repository.
void defineGitConfigContract(BackendFactory factory) {
  group('GitConfig.getAll', () {
    late GitConfig config;

    setUp(() async {
      config = (await factory.createWorkingRepository()).config;
    });

    test('an empty prefix returns every local entry', () async {
      final List<GitConfigEntry> entries = await config.getAll();

      expect(entries, isNotEmpty);
      expect(
        entries.map((GitConfigEntry entry) => entry.key),
        containsAll(<String>['user.name', 'user.email']),
      );
    });

    test('a section prefix selects its entries in file order', () async {
      await config.set('custom.sample.one', 'first');
      await config.set('custom.sample.two', 'second');
      await config.set('custom.other.key', 'third');

      expect(
        await config.getAll(prefix: 'custom.sample'),
        <GitConfigEntry>[
          const GitConfigEntry(key: 'custom.sample.one', value: 'first'),
          const GitConfigEntry(key: 'custom.sample.two', value: 'second'),
        ],
      );
    });

    test('a subsection keeps its written case while the name is lowercase',
        () async {
      await config.set('custom.CamelCase.Key', 'value');

      expect(
        await config.getAll(prefix: 'custom.CamelCase'),
        <GitConfigEntry>[
          const GitConfigEntry(key: 'custom.CamelCase.key', value: 'value'),
        ],
      );
    });

    test('values keep their newlines exactly', () async {
      const String value = 'first line\nsecond line\n\nfourth line';
      await config.set('custom.lines.value', value);

      expect(
        (await config.getAll(prefix: 'custom.lines.value')).single.value,
        value,
      );
    });

    test('an empty local configuration yields an empty list', () async {
      final Set<String> sections = (await config.getAll())
          .map((GitConfigEntry entry) =>
              entry.key.substring(0, entry.key.lastIndexOf('.')))
          .toSet();
      for (final String section in sections) {
        await config.removeSection(section);
      }

      expect(await config.getAll(), isEmpty);
    });
  });
}
