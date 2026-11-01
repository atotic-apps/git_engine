import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

const String _commitContent = 'tree $syntheticTreeOid\n'
    'parent $syntheticFirstParentOid\n'
    'parent $syntheticSecondParentOid\n'
    'author Ada Lovelace <ada@example.com> 1700000000 +0000\n'
    'committer Grace Hopper <grace@example.com> 1700000100 +0200\n'
    '\n'
    'Merge the branches\n'
    '\n'
    'Details.\n';

void main() {
  group('raw objects', () {
    test('parses a commit with two parents and its identities', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['cat-file', 'commit', syntheticCommitOid],
          GitRunResult.fromStrings(_commitContent),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitCommit commit =
          await repository.objects.readCommit(GitOid.parse(syntheticCommitOid));

      expect(commit.tree, GitOid.parse(syntheticTreeOid));
      expect(
        commit.parents,
        <GitOid>[
          GitOid.parse(syntheticFirstParentOid),
          GitOid.parse(syntheticSecondParentOid),
        ],
      );
      expect(
        commit.author,
        GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com'),
      );
      expect(
        commit.committer,
        GitIdentity(name: 'Grace Hopper', email: 'grace@example.com'),
      );
      expect(commit.authorDate, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(commit.committerDate, DateTime.utc(2023, 11, 14, 22, 15));
      expect(commit.message, 'Merge the branches\n\nDetails.');
      expect(
        runner.requests.single.arguments,
        const <String>['cat-file', 'commit', syntheticCommitOid],
      );
    });

    test('parses a tree listing with files, a subtree and a link', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>[
            'ls-tree',
            '-z',
            '--full-tree',
            syntheticTreeOid,
          ],
          GitRunResult.fromStrings(
            '100644 blob $syntheticBlobOid\tREADME.md\u0000'
            '040000 tree $syntheticSubtreeOid\tsrc\u0000'
            '120000 blob $syntheticLinkOid\tlink.txt\u0000',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitTree tree =
          await repository.objects.readTree(GitOid.parse(syntheticTreeOid));

      expect(tree.oid, GitOid.parse(syntheticTreeOid));
      expect(
        tree.entries,
        <GitTreeEntry>[
          GitTreeEntry(
            mode: '100644',
            type: GitObjectType.blob,
            oid: GitOid.parse(syntheticBlobOid),
            path: 'README.md',
          ),
          GitTreeEntry(
            mode: '040000',
            type: GitObjectType.tree,
            oid: GitOid.parse(syntheticSubtreeOid),
            path: 'src',
          ),
          GitTreeEntry(
            mode: '120000',
            type: GitObjectType.blob,
            oid: GitOid.parse(syntheticLinkOid),
            path: 'link.txt',
          ),
        ],
      );
      expect(
        runner.requests.single.arguments,
        const <String>['ls-tree', '-z', '--full-tree', syntheticTreeOid],
      );
    });

    test('refuses a commit without a tree', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['cat-file', 'commit', syntheticCommitOid],
          GitRunResult.fromStrings(
            'author Ada Lovelace <ada@example.com> 1700000000 +0000\n'
            'committer Ada Lovelace <ada@example.com> 1700000000 +0000\n'
            '\n'
            'No tree here.\n',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.objects.readCommit(GitOid.parse(syntheticCommitOid)),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('commit without a tree'),
          ),
        ),
      );
    });
  });
}
