@Tags(['git'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import '../support/remote_test_support.dart';

void main() {
  late TestRepository repo;
  late ProcessGitRepository repository;

  setUp(() async {
    repo = await createTestRepository();
    repository = await openAt(repo);
  });

  test('reads the identity the support wrote locally', () async {
    expect(await repository.config.get('user.name'), testUserName);
    expect(await repository.config.get('user.email'), testUserEmail);
  });

  test('writes, reads and replaces values', () async {
    await repository.config.set('sample.check', 'written');
    expect(await repository.config.get('sample.check'), 'written');

    await repository.config.set('sample.check', 'replaced');
    expect(await repository.config.get('sample.check'), 'replaced');
  });

  test('values keep their spaces, values may even start with a dash', () async {
    await repository.config.set('sample.spaced', 'two words here');
    expect(await repository.config.get('sample.spaced'), 'two words here');

    await repository.config.set('sample.dashed', '-dashy value');
    expect(await repository.config.get('sample.dashed'), '-dashy value');
  });

  test('values keep every newline they hold', () async {
    const String multiline = 'first line\nsecond line\n\nfourth line';
    await repository.config.set('sample.multiline', multiline);

    expect(
      (await repository.config.getAll(prefix: 'sample.multiline')).single.value,
      multiline,
    );
  });

  test('reads null for an absent key', () async {
    expect(await repository.config.get('sample.absent.key'), isNull);
  });

  test('a malformed key is a typed error', () async {
    await expectLater(
      repository.config.get('no_section_here'),
      throwsA(isA<GitCommandException>()),
    );
  });

  test('lists the keys matching a pattern', () async {
    await repository.config.set('custom.sample.one', 'first');
    await repository.config.set('custom.sample.two', 'second');
    await repository.config.set('custom.other.key', 'third');

    expect(
      await repository.config.getAll(prefix: 'custom.sample'),
      <GitConfigEntry>[
        const GitConfigEntry(key: 'custom.sample.one', value: 'first'),
        const GitConfigEntry(key: 'custom.sample.two', value: 'second'),
      ],
    );
  });

  test('lists multi-valued keys in the order they were added', () async {
    await repo.runGit(const <String>[
      'config',
      '--local',
      '--add',
      'custom.multi.key',
      'first',
    ]);
    await repo.runGit(const <String>[
      'config',
      '--local',
      '--add',
      'custom.multi.key',
      'second',
    ]);

    expect(
      await repository.config.getAll(prefix: 'custom.multi.key'),
      <GitConfigEntry>[
        const GitConfigEntry(key: 'custom.multi.key', value: 'first'),
        const GitConfigEntry(key: 'custom.multi.key', value: 'second'),
      ],
    );
  });

  test('lists nothing when no key matches', () async {
    await repository.config.set('custom.sample.one', 'first');
    expect(await repository.config.getAll(prefix: 'nothing.matches'), isEmpty);
  });

  test('unset removes a value', () async {
    await repository.config.set('sample.gone', 'there');
    await repository.config.unset('sample.gone');
    expect(await repository.config.get('sample.gone'), isNull);
  });

  test('unsetting an absent key is refused', () async {
    await expectLater(
      repository.config.unset('sample.absent.key'),
      throwsA(isA<GitCommandException>()),
    );
  });

  test('removeSection empties the whole section', () async {
    await repository.config.set('custom.sample.one', 'first');
    await repository.config.set('custom.sample.two', 'second');
    await repository.config.set('custom.other.key', 'third');

    await repository.config.removeSection('custom.sample');

    expect(await repository.config.get('custom.sample.one'), isNull);
    expect(await repository.config.getAll(prefix: 'custom.sample'), isEmpty);
    expect(await repository.config.get('custom.other.key'), 'third');
  });

  test('removing an absent section is refused', () async {
    await expectLater(
      repository.config.removeSection('custom.absent'),
      throwsA(isA<GitCommandException>()),
    );
  });

  test('writes are local only', () async {
    await repository.config.set('sample.local', 'kept');

    // The value is visible in this repository's configuration file,
    final String gitDirectory =
        TestRepository.join(repo.directory.path, '.git');
    final File local = File(TestRepository.join(gitDirectory, 'config'));
    expect(local.existsSync(), isTrue);
    final String localText = utf8.decode(
      local.readAsBytesSync(),
      allowMalformed: true,
    );
    expect(localText.contains('local = kept'), isTrue);

    // and nowhere else: the global configuration file the support isolated
    // stays empty,
    final File global = repo.sandboxFile('gitconfig-global');
    final String globalText = utf8.decode(
      global.readAsBytesSync(),
      allowMalformed: true,
    );
    expect(globalText.contains('sample'), isFalse);

    // and git confirms nothing sits at the global level,
    await expectLater(
      repo.runGit(
        const <String>['config', '--global', '--get', 'sample.local'],
      ),
      throwsA(isA<GitCommandException>()),
    );

    // while a plain read inside the repository still answers locally.
    final result = await repo.runGit(
      const <String>['config', '--get', 'sample.local'],
    );
    expect(result.stdout.trim(), 'kept');
  });
}
