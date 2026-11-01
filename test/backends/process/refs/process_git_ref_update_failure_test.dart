import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

/// Whether [stdin] holds exactly the [bytes] of the expected script.
void _expectStdin(Uint8List? stdin, List<int> bytes) {
  expect(stdin, isNotNull);
  expect(stdin!.length, bytes.length);
  for (var index = 0; index < bytes.length; index++) {
    expect(stdin[index], bytes[index], reason: 'byte $index of the script');
  }
}

void main() {
  final GitOid newOid = GitOid.parse(syntheticCommitOid);
  final GitOid expectedOid = GitOid.parse(syntheticTreeOid);

  group('ref update failures', () {
    test('types a rejected expected value as a ref mismatch', () async {
      final List<String> command = <String>[
        'update-ref',
        '--',
        'refs/heads/main',
        newOid.value,
        expectedOid.value,
      ];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 1,
        stderr: "error: cannot lock ref 'refs/heads/main': is at "
            '${syntheticFirstParentOid} but expected ${expectedOid.value}\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.refs.updateRef(
          'refs/heads/main',
          newOid,
          expectedOld: expectedOid,
        ),
        throwsA(
          isA<GitRefMismatchException>().having(
            (GitRefMismatchException error) => error.cause,
            'cause',
            same(failure),
          ),
        ),
      );
      expect(runner.requests.single.arguments, command);
    });

    test('recognises the unexpected-object wording variant', () async {
      final List<String> command = <String>[
        'update-ref',
        '--',
        'refs/heads/main',
        newOid.value,
        expectedOid.value,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 1,
            stderr: 'fatal: unexpected object ID ${expectedOid.value}\n',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.refs.updateRef(
          'refs/heads/main',
          newOid,
          expectedOld: expectedOid,
        ),
        throwsA(isA<GitRefMismatchException>()),
      );
    });

    test('leaves an unrelated refusal as a command failure', () async {
      final List<String> command = <String>[
        'update-ref',
        '--',
        'refs/heads/main',
        newOid.value,
      ];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 128,
        stderr: 'fatal: refs/heads/main: cannot lock ref\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.refs.updateRef('refs/heads/main', newOid),
        throwsA(same(failure)),
      );
    });

    test('classifies a rejected deletion like a rejected update', () async {
      final List<String> command = <String>[
        'update-ref',
        '-d',
        '--',
        'refs/heads/main',
        expectedOid.value,
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 1,
            stderr: 'fatal: is at ${syntheticFirstParentOid} '
                'but expected ${expectedOid.value}\n',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.refs.deleteRef(
          'refs/heads/main',
          expectedOld: expectedOid,
        ),
        throwsA(isA<GitRefMismatchException>()),
      );
    });

    test('classifies a rejected transaction and sends the staged script',
        () async {
      final List<String> command = <String>['update-ref', '--stdin', '-z'];
      final GitCommandException failure = GitCommandException(
        arguments: command,
        exitCode: 1,
        stderr: 'fatal: is at ${syntheticFirstParentOid} '
            'but expected ${expectedOid.value}\n',
      );
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(command, failure);
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitRefTransaction transaction = repository.beginRefTransaction()
        ..update('refs/heads/main', newOid, expectedOld: expectedOid);

      await expectLater(
        transaction.commit(),
        throwsA(
          isA<GitRefMismatchException>().having(
            (GitRefMismatchException error) => error.cause,
            'cause',
            same(failure),
          ),
        ),
      );
      final GitRunRequest request = runner.requests.single;
      expect(request.arguments, command);
      _expectStdin(request.stdin, <int>[
        ...'start'.codeUnits,
        0,
        ...'update'.codeUnits,
        0x20,
        ...'refs/heads/main'.codeUnits,
        0,
        ...newOid.value.codeUnits,
        0,
        ...expectedOid.value.codeUnits,
        0,
        ...'prepare'.codeUnits,
        0,
        ...'commit'.codeUnits,
        0,
      ]);
    });
  });
}
