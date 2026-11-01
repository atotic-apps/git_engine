@Tags(['git'])
library;

import 'package:test/test.dart';

import '../support/test_repository.dart';
import '../support/remote_test_support.dart';

void main() {
  late TestRepository repo;
  late ProcessGitRepository repository;
  late String firstRepository;
  late String secondRepository;

  setUp(() async {
    repo = await createTestRepository();
    repository = await openAt(repo);
    firstRepository = repo.directory.path;
    secondRepository = await sandboxDirectory(repo, 'un autre dépôt é à');
  });

  test('lists the remotes it registered', () async {
    expect(await repository.remotes.list(), isEmpty);

    await repository.remotes.add('side', firstRepository);
    await repository.remotes.add('other', secondRepository);
    expect(
      await repository.remotes.list(),
      unorderedEquals(<String>['side', 'other']),
    );
  });

  test('reads and rewrites the urls', () async {
    await repository.remotes.add('side', firstRepository);
    expect(await repository.remotes.getUrl('side'), firstRepository);

    await repository.remotes.setUrl('side', secondRepository);
    expect(await repository.remotes.getUrl('side'), secondRepository);
  });

  test('an url of an unknown remote reads null', () async {
    expect(await repository.remotes.getUrl('nowhere'), isNull);
  });

  test('renaming moves the remote along', () async {
    await repository.remotes.add('side', firstRepository);

    await repository.remotes.rename('side', 'upstream');

    expect(await repository.remotes.list(), <String>['upstream']);
    expect(await repository.remotes.getUrl('upstream'), firstRepository);
    expect(await repository.remotes.getUrl('side'), isNull);
  });

  test('removing takes the remote away', () async {
    await repository.remotes.add('side', firstRepository);

    await repository.remotes.remove('side');

    expect(await repository.remotes.list(), isEmpty);
    expect(await repository.remotes.getUrl('side'), isNull);
  });

  test('renaming moves the remote-tracking refs', () async {
    await commitFile(repo, 'a.txt', 'a\n', 'add a');
    final String bare = await cloneBareByRunner(
      repo,
      repo.directory.path,
      'rename-origin.git',
    );
    await repository.remotes.add('origin', bare);
    await engineAt(repo).fetch(repository, remote: 'origin');
    final String fetched = await oidOf(repo, 'refs/remotes/origin/main');

    await repository.remotes.rename('origin', 'upstream');

    expect(
      await oidOf(repo, 'refs/remotes/upstream/main'),
      fetched,
    );
  });

  test('registering an already used name is refused', () async {
    await repository.remotes.add('side', firstRepository);
    await expectLater(
      repository.remotes.add('side', secondRepository),
      throwsA(isA<GitCommandException>()),
    );
  });

  test('an unknown remote is refused', () async {
    await expectLater(
      repository.remotes.remove('nowhere'),
      throwsA(isA<GitCommandException>()),
    );
    await expectLater(
      repository.remotes.rename('nowhere', 'anything'),
      throwsA(isA<GitCommandException>()),
    );
    await expectLater(
      repository.remotes.setUrl('nowhere', firstRepository),
      throwsA(isA<GitCommandException>()),
    );
  });

  test('a name starting with a dash is not read as an option', () async {
    final Matcher unknownRemote = throwsA(
      isA<GitCommandException>().having(
        (GitCommandException error) => error.stderr.toLowerCase(),
        'stderr',
        contains('no such remote'),
      ),
    );
    await expectLater(repository.remotes.remove('--progress'), unknownRemote);
    await expectLater(
      repository.remotes.rename('--progress', 'anything'),
      unknownRemote,
    );
  });
}
