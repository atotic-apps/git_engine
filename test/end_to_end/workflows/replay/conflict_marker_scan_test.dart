@Tags(['git'])
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// Capacity wanted by the receivers of a conflict list: scanning the work
/// tree files the list names for real conflict markers, line by line, so a
/// lone `=======` separator, a bare `<<<<<<<` without a body, and an
/// `>>>>>>>` glued to its label are honored without reporting text content
/// as an unresolved conflict.
void main() {
  late Directory root;
  late ProcessGitRunner runner;
  late ProcessGitEngine engine;
  late GitWorkingRepository repository;

  String path(String name) => join(root.path, name);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('git_engine_markers_');
    final File globalConfig = File(join(root.path, 'gitconfig-global'));
    await globalConfig.writeAsString('''
[user]
	name = Marker Keeper
	email = keeper@markers.test
[init]
	defaultBranch = main
[core]
	autocrlf = false
''');
    runner = ProcessGitRunner(
      globalEnvironment: <String, String>{
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': globalConfig.path,
      },
    );
    engine = ProcessGitEngine(runner: runner);
    addTearDown(() async {
      for (var attempt = 0;; attempt++) {
        try {
          await root.delete(recursive: true);
          return;
        } on FileSystemException {
          if (attempt >= 4) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    });
    repository = await engine.init(path('repo'), initialBranch: 'main');
  });

  /// Writes [files], stages everything and commits [message].
  Future<GitOid> commit(
    Map<String, String> files,
    String message,
  ) async {
    files.forEach((String relative, String content) {
      final File file = File(join(repository.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    });
    await repository.worktree.addAll();
    return repository.worktree.commit(message);
  }

  test('scanning the files of a conflict list skips what is resolved',
      () async {
    await commit(<String, String>{'shared.txt': 'base\n'}, 'base');
    await repository.worktree.checkoutNewBranch('side');
    await commit(<String, String>{'shared.txt': 'from the side\n'}, 'side');
    await repository.worktree.checkoutNewBranch(
      'main',
      startPoint: 'main',
      resetIfExists: true,
    );
    await commit(
      <String, String>{'shared.txt': 'from the main line\n'},
      'main line',
    );
    await repository.merge.merge('side');
    await repository.merge.abort();

    // A receiver of the list may name files that carry no conflict anymore:
    // a resolved file and a file that is gone are scanned to nothing, and
    // the scan still reports the real block of an unresolved one.
    await commit(
      <String, String>{'shared.txt': 'base\n'},
      'reset the file to a clean state',
    );
    final List<String> resolved = <String>[
      'shared.txt',
      'resolved-elsewhere.txt',
      'deleted.txt',
    ];
    expect(
      await repository.worktree.scanConflictMarkers(resolved),
      isEmpty,
    );
  });
}

/// Joins [base] and [relative] with the platform separator.
String join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}
