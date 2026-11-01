@Tags(['git'])
library;

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'support/remote_test_support.dart';
import 'support/test_repository.dart';

/// A pull fetches the requested branch and then the tags naming the commits it
/// downloaded. A tag on an older commit must not become the commit the pull
/// merges: the branch tip read before the tag fetch is what the merge takes.
void main() {
  test('a path remote merges the branch tip, not a tag on the old commit',
      () async {
    final TestRepository repo = await createTestRepository();
    final String oldTip = await commitFile(repo, 'a.txt', 'a\n', 'add a');
    await repo.runGit(<String>['tag', 'old', oldTip]);
    final String copyPath =
        await cloneByRunner(repo, repo.directory.path, 'copy-path');
    final String newTip = await commitFile(repo, 'b.txt', 'b\n', 'add b');
    expect(await oidAt(repo, copyPath, 'HEAD'), oldTip);

    final ProcessGitWorkingRepository copy = await engineAt(repo)
        .openWorking(copyPath) as ProcessGitWorkingRepository;
    final GitMergeResult result = await engineAt(repo).pull(
      copy,
      remote: repo.directory.path,
      branch: 'main',
    );

    expect(result, isNot(isA<GitMergeUpToDate>()));
    expect(await oidAt(repo, copyPath, 'HEAD'), newTip);
  });

  test('a file URL remote merges the branch tip, not a tag on the old commit',
      () async {
    final TestRepository repo = await createTestRepository();
    final String oldTip = await commitFile(repo, 'a.txt', 'a\n', 'add a');
    await repo.runGit(<String>['tag', 'old', oldTip]);
    final String copyPath =
        await cloneByRunner(repo, repo.directory.path, 'copy-url');
    final String newTip = await commitFile(repo, 'b.txt', 'b\n', 'add b');
    expect(await oidAt(repo, copyPath, 'HEAD'), oldTip);

    final ProcessGitWorkingRepository copy = await engineAt(repo)
        .openWorking(copyPath) as ProcessGitWorkingRepository;
    final GitMergeResult result = await engineAt(repo).pull(
      copy,
      remote: Uri.file(repo.directory.path).toString(),
      branch: 'main',
    );

    expect(result, isNot(isA<GitMergeUpToDate>()));
    expect(await oidAt(repo, copyPath, 'HEAD'), newTip);
  });

  test('several annotated and lightweight tags on both commits do not win',
      () async {
    final TestRepository repo = await createTestRepository();
    final String oldTip = await commitFile(repo, 'a.txt', 'a\n', 'add a');
    await repo.runGit(<String>['tag', 'old-light', oldTip]);
    await repo.runGit(
      <String>['tag', '-a', 'old-annotated', '-m', 'old annotated', oldTip],
    );
    final String copyPath =
        await cloneByRunner(repo, repo.directory.path, 'copy-tags');
    final String newTip = await commitFile(repo, 'b.txt', 'b\n', 'add b');
    await repo.runGit(<String>['tag', 'new-light', newTip]);
    await repo.runGit(
      <String>['tag', '-a', 'new-annotated', '-m', 'new annotated', newTip],
    );
    expect(await oidAt(repo, copyPath, 'HEAD'), oldTip);

    final ProcessGitWorkingRepository copy = await engineAt(repo)
        .openWorking(copyPath) as ProcessGitWorkingRepository;
    final GitMergeResult result = await engineAt(repo).pull(
      copy,
      remote: repo.directory.path,
      branch: 'main',
    );

    expect(result, isNot(isA<GitMergeUpToDate>()));
    expect(await oidAt(repo, copyPath, 'HEAD'), newTip);
  });

  test('a named remote with a custom fetch refspec merges the branch tip',
      () async {
    final TestRepository repo = await createTestRepository();
    final String oldTip = await commitFile(repo, 'a.txt', 'a\n', 'add a');
    final String copyPath =
        await cloneByRunner(repo, repo.directory.path, 'copy-custom');
    await repo.runGit(
      <String>[
        'config',
        'remote.origin.fetch',
        '+refs/heads/*:refs/remotes/origin/mirror/*',
      ],
      workingDirectory: copyPath,
    );
    final String newTip = await commitFile(repo, 'b.txt', 'b\n', 'add b');
    expect(await oidAt(repo, copyPath, 'HEAD'), oldTip);

    final ProcessGitWorkingRepository copy = await engineAt(repo)
        .openWorking(copyPath) as ProcessGitWorkingRepository;
    final GitMergeResult result = await engineAt(repo).pull(
      copy,
      remote: 'origin',
      branch: 'main',
    );

    expect(result, isNot(isA<GitMergeUpToDate>()));
    expect(await oidAt(repo, copyPath, 'HEAD'), newTip);
  });
}
