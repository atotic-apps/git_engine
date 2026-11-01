/// Creates a temporary local repository, writes and commits a file, and
/// prints the branch. The temporary directory is removed at the end.
///
///     dart run example/git_engine_example.dart
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main() async {
  final Directory sandbox =
      await Directory.systemTemp.createTemp('git_engine_example_');
  try {
    final File globalConfig = File('${sandbox.path}/gitconfig');
    await globalConfig.writeAsString('');
    final ProcessGitEngine engine = ProcessGitEngine(
      globalEnvironment: <String, String>{
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': globalConfig.path,
      },
    );
    final GitWorkingRepository repository = await engine.init(
      '${sandbox.path}/repository',
      initialBranch: 'main',
    );
    await File('${repository.path}/notes.txt').writeAsString('First note\n');
    await repository.worktree.add(<String>['notes.txt']);
    final GitOid commit = await repository.worktree.commit(
      'Add the first note',
      identity: GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com'),
    );
    print('committed ${commit.short()} on '
        '${await repository.branches.current()}');
  } finally {
    await sandbox.delete(recursive: true);
  }
}
