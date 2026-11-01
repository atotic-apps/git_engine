import 'package:git_engine/git_engine.dart';
import 'package:git_engine/src/backends/process/git_command_timeout_exception.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

const List<String> _statusCommand = <String>[
  'status',
  '--porcelain=v1',
  '-z',
];

void main() {
  group('porcelain status parsing', () {
    test('reports an indexed modification', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _statusCommand,
          GitRunResult.fromStrings('M  src/main.dart\u0000'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final List<GitStatusEntry> entries = await repository.worktree.status();

      expect(entries, hasLength(1));
      final GitStatusEntry entry = entries.single;
      expect(entry.code, 'M ');
      expect(entry.path, 'src/main.dart');
      expect(entry.indexState, GitFileState.modified);
      expect(entry.workTreeState, GitFileState.unchanged);
      expect(entry.isIndexed, isTrue);
      expect(entry.isModified, isFalse);
      expect(runner.requests.single.arguments, _statusCommand);
      expect(
        runner.requests.single.workingDirectory,
        repository.context.path,
      );
    });

    test('reports an unstaged modification', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _statusCommand,
          GitRunResult.fromStrings(' M src/main.dart\u0000'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitStatusEntry entry = (await repository.worktree.status()).single;

      expect(entry.code, ' M');
      expect(entry.indexState, GitFileState.unchanged);
      expect(entry.workTreeState, GitFileState.modified);
      expect(entry.isIndexed, isFalse);
      expect(entry.isModified, isTrue);
    });

    test('reports a rename with its source path', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _statusCommand,
          GitRunResult.fromStrings(
            'R  docs/new.md\u0000docs/old.md\u0000',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final List<GitStatusEntry> entries = await repository.worktree.status();

      expect(entries, hasLength(1));
      final GitStatusEntry entry = entries.single;
      expect(entry.code, 'R ');
      expect(entry.path, 'docs/new.md');
      expect(entry.originalPath, 'docs/old.md');
      expect(entry.indexState, GitFileState.renamed);
      expect(entry.workTreeState, GitFileState.unchanged);
      expect(entry.isRenamed, isTrue);
    });

    test('reports an untracked file', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _statusCommand,
          GitRunResult.fromStrings('?? notes.txt\u0000'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitStatusEntry entry = (await repository.worktree.status()).single;

      expect(entry.code, '??');
      expect(entry.path, 'notes.txt');
      expect(entry.indexState, GitFileState.untracked);
      expect(entry.workTreeState, GitFileState.untracked);
      expect(entry.isUntracked, isTrue);
    });

    test('reports an untracked directory as one entry', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _statusCommand,
          GitRunResult.fromStrings('?? drafts/\u0000'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final List<GitStatusEntry> entries = await repository.worktree.status();

      expect(entries, hasLength(1));
      expect(entries.single.path, 'drafts/');
      expect(entries.single.isUntracked, isTrue);
    });

    test('reports a conflict as unmerged on both sides', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _statusCommand,
          GitRunResult.fromStrings('UU src/main.dart\u0000'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitStatusEntry entry = (await repository.worktree.status()).single;

      expect(entry.code, 'UU');
      expect(entry.indexState, GitFileState.unmerged);
      expect(entry.workTreeState, GitFileState.unmerged);
      expect(entry.isConflicted, isTrue);
      expect(entry.isIndexed, isFalse);
    });

    test('reads several NUL-separated entries in one output', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _statusCommand,
          GitRunResult.fromStrings(
            'A  added.txt\u0000 M changed.txt\u0000?? later.txt\u0000',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final List<GitStatusEntry> entries = await repository.worktree.status();

      expect(
        entries.map((GitStatusEntry entry) => entry.path).toList(),
        <String>['added.txt', 'changed.txt', 'later.txt'],
      );
    });
  });

  group('status failures', () {
    test('propagates a timeout from the runner', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);
      final GitTimeoutException timeout = GitTimeoutException(
        timeout: const Duration(seconds: 2),
        cause: GitCommandTimeoutException(
          arguments: _statusCommand,
          workingDirectory: repository.context.path,
          stdout: 'partial output',
        ),
      );
      runner.failWith(_statusCommand, timeout);

      await expectLater(
        repository.worktree.status(),
        throwsA(
          isA<GitTimeoutException>()
              .having(
                (GitTimeoutException error) => error.timeout,
                'timeout',
                const Duration(seconds: 2),
              )
              .having(
                (GitTimeoutException error) => error.cause,
                'cause',
                isA<GitCommandTimeoutException>()
                    .having(
                      (GitCommandTimeoutException cause) => cause.arguments,
                      'arguments',
                      _statusCommand,
                    )
                    .having(
                      (GitCommandTimeoutException cause) => cause.stdout,
                      'stdout',
                      'partial output',
                    )
                    .having(
                      (GitCommandTimeoutException cause) =>
                          cause.workingDirectory,
                      'workingDirectory',
                      repository.context.path,
                    ),
              ),
        ),
      );
    });
  });
}
