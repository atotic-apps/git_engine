import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

const List<String> _unmergedCommand = <String>[
  'ls-files',
  '--unmerged',
  '-z',
];

void main() {
  group('unmerged index entries', () {
    test('parses the three stages of a conflicted path', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _unmergedCommand,
          GitRunResult.fromStrings(
            '100644 $syntheticFirstParentOid 1\tsrc/main.dart\u0000'
            '100644 $syntheticSecondParentOid 2\tsrc/main.dart\u0000'
            '100644 $syntheticCommitOid 3\tsrc/main.dart\u0000',
          ),
        );
      final ProcessGitIndexedRepository repository =
          syntheticIndexedRepository(runner);

      final List<GitUnmergedEntry> entries =
          await repository.index.unmergedEntries();

      expect(
        entries,
        <GitUnmergedEntry>[
          GitUnmergedEntry(
            mode: '100644',
            oid: GitOid.parse(syntheticFirstParentOid),
            stage: 1,
            path: 'src/main.dart',
          ),
          GitUnmergedEntry(
            mode: '100644',
            oid: GitOid.parse(syntheticSecondParentOid),
            stage: 2,
            path: 'src/main.dart',
          ),
          GitUnmergedEntry(
            mode: '100644',
            oid: GitOid.parse(syntheticCommitOid),
            stage: 3,
            path: 'src/main.dart',
          ),
        ],
      );
      expect(runner.requests.single.arguments, _unmergedCommand);
      expect(
        runner.requests.single.workingDirectory,
        repository.context.path,
      );
    });

    test('keeps paths with spaces intact', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _unmergedCommand,
          GitRunResult.fromStrings(
            '100644 $syntheticFirstParentOid 2\tdocs/a file.md\u0000',
          ),
        );
      final ProcessGitIndexedRepository repository =
          syntheticIndexedRepository(runner);

      final GitUnmergedEntry entry =
          (await repository.index.unmergedEntries()).single;

      expect(entry.path, 'docs/a file.md');
      expect(entry.stage, 2);
    });

    test('returns nothing for an empty output', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(_unmergedCommand, GitRunResult.fromStrings(''));
      final ProcessGitIndexedRepository repository =
          syntheticIndexedRepository(runner);

      expect(await repository.index.unmergedEntries(), isEmpty);
    });
  });
}
