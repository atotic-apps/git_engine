import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

void main() {
  final GitOid oid = GitOid.parse(syntheticCommitOid);
  final GitOid expected = GitOid.parse(syntheticTreeOid);

  /// Whether [runner] received no request at all.
  bool untouched(ScriptedGitRunner runner) => runner.requests.isEmpty;

  group('GitRefs name checks run before any command', () {
    test('a branch-creation name is checked first, without git', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.branches.create('--delete', startPoint: 'victim'),
        throwsA(isA<GitInvalidRefNameException>().having(
          (GitInvalidRefNameException error) => error.name,
          'name',
          '--delete',
        )),
      );
      expect(untouched(runner), isTrue);
    });

    test('a tag name is checked first, without git', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.tags.create('-force', oid),
        throwsA(isA<GitInvalidRefNameException>()),
      );
      expect(untouched(runner), isTrue);
    });

    test('ref writes are checked first, without git', () async {
      final List<String> mergeHeadCommand = <String>[
        'update-ref',
        '--',
        'MERGE_HEAD',
        oid.value,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(mergeHeadCommand, GitRunResult.fromStrings(''));
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(
        () => repository.refs.updateRef('-update-ref', oid),
        throwsA(isA<GitInvalidRefNameException>()),
      );
      expect(
        () => repository.refs.deleteRef('refs/heads/.stealth'),
        throwsA(isA<GitInvalidRefNameException>()),
      );
      expect(
        () => repository.refs.setHead('HEAD~slip'),
        throwsA(isA<GitInvalidRefNameException>()),
      );
      await repository.refs.updateRef('MERGE_HEAD', oid);
      expect(runner.requests.single.arguments, mergeHeadCommand);
    });

    test('staged names are checked when they are staged, not at commit',
        () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);
      final GitRefTransaction transaction = repository.beginRefTransaction();

      expect(
        () => transaction.create('refs/heads/ok ${oid.value}', oid),
        throwsA(isA<GitInvalidRefNameException>()),
      );
      expect(
        () => transaction.delete('-delete'),
        throwsA(isA<GitInvalidRefNameException>()),
      );
      expect(untouched(runner), isTrue);
    });
  });

  group('the transaction script is NUL-framed', () {
    test('every command and field travels closed by NUL, -z format', () async {
      final List<String> command = <String>['update-ref', '--stdin', '-z'];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 1,
            stderr: 'fatal: is at ${syntheticFirstParentOid} but expected '
                '${expected.value}\n',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitRefTransaction transaction = repository.beginRefTransaction();
      transaction.update('refs/heads/main', oid, expectedOld: expected);
      transaction.create('refs/heads/topic', oid);
      transaction.delete('refs/heads/stale');

      await expectLater(
        transaction.commit(),
        throwsA(isA<GitRefMismatchException>()),
      );
      final GitRunRequest request = runner.requests.single;
      final List<int> script = <int>[];
      script.addAll('start'.codeUnits);
      script.add(0);
      script.addAll('update'.codeUnits);
      script.add(0x20);
      script.addAll('refs/heads/main'.codeUnits);
      script.add(0);
      script.addAll(oid.value.codeUnits);
      script.add(0);
      script.addAll(expected.value.codeUnits);
      script.add(0);
      script.addAll('create'.codeUnits);
      script.add(0x20);
      script.addAll('refs/heads/topic'.codeUnits);
      script.add(0);
      script.addAll(oid.value.codeUnits);
      script.add(0);
      script.addAll('delete'.codeUnits);
      script.add(0x20);
      script.addAll('refs/heads/stale'.codeUnits);
      script.add(0);
      script.add(0);
      script.addAll('prepare'.codeUnits);
      script.add(0);
      script.addAll('commit'.codeUnits);
      script.add(0);
      expect(request.arguments, command);
      expect(request.stdin!.length, script.length);
      for (var index = 0; index < script.length; index++) {
        expect(
          request.stdin![index],
          script[index],
          reason: 'byte $index of the update-ref script',
        );
      }
    });
  });

  group('revisions that read like options name nothing', () {
    test('resolveRevision answers null without running git', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(
        await repository.revisions.resolveRevision('--output=/tmp/stolen'),
        isNull,
      );
      expect(untouched(runner), isTrue);
    });

    test('resetSoft refuses before any command', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.refs.resetSoft('--reference=x'),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(untouched(runner), isTrue);
    });

    test('symbolicFullName refuses before any command', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.revisions.symbolicFullName('--short'),
        throwsA(isA<GitUnknownRevisionException>()),
      );
      expect(untouched(runner), isTrue);
    });
  });
}
