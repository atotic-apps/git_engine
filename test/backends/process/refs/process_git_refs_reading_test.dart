import 'package:git_engine/git_engine.dart';
import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

import '../support/scripted_git_runner.dart';
import '../support/synthetic_git_support.dart';

const List<String> _listRefsCommand = <String>[
  'for-each-ref',
  '--format=%(refname)%09%(objectname)',
];

void main() {
  group('reading refs', () {
    test('lists refs and filters them by prefix', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _listRefsCommand,
          GitRunResult.fromStrings(
            'refs/heads/main\t$syntheticCommitOid\n'
            'refs/tags/v1.0.0\t$syntheticTagOid\n'
            'refs/remotes/origin/main\t$syntheticTreeOid\n',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final List<GitRef> all = await repository.refs.listRefs();
      final List<GitRef> heads =
          await repository.refs.listRefs(prefix: 'refs/heads/');

      expect(
        all,
        <GitRef>[
          GitRef(
            name: 'refs/heads/main',
            oid: GitOid.parse(syntheticCommitOid),
          ),
          GitRef(
            name: 'refs/tags/v1.0.0',
            oid: GitOid.parse(syntheticTagOid),
          ),
          GitRef(
            name: 'refs/remotes/origin/main',
            oid: GitOid.parse(syntheticTreeOid),
          ),
        ],
      );
      expect(heads, <GitRef>[all.first]);
      expect(
        runner.requests.map((GitRunRequest request) => request.arguments),
        <List<String>>[_listRefsCommand, _listRefsCommand],
      );
    });

    test('resolves a full reference through show-ref', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>[
            'show-ref',
            '--verify',
            '--hash',
            'refs/heads/main',
          ],
          GitRunResult.fromStrings('$syntheticCommitOid\n'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitOid? oid = await repository.refs.resolveRef('refs/heads/main');

      expect(oid, GitOid.parse(syntheticCommitOid));
      expect(
        runner.requests.single.arguments,
        const <String>['show-ref', '--verify', '--hash', 'refs/heads/main'],
      );
    });

    test('resolves HEAD through rev-parse', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['rev-parse', '--verify', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('$syntheticTreeOid\n'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      final GitOid? oid = await repository.refs.resolveRef('HEAD');

      expect(oid, GitOid.parse(syntheticTreeOid));
      expect(
        runner.requests.single.arguments,
        const <String>['rev-parse', '--verify', '--quiet', 'HEAD'],
      );
    });

    test('returns null for a name that is not a full reference', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner();
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(await repository.refs.resolveRef('main'), isNull);
      expect(runner.requests, isEmpty);
    });

    test('returns null when a full reference does not exist', () async {
      final List<String> command = <String>[
        'show-ref',
        '--verify',
        '--hash',
        'refs/heads/missing',
      ];
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..failWith(
          command,
          GitCommandException(
            arguments: command,
            exitCode: 1,
            stderr: 'fatal: refs/heads/missing: not a valid ref\n',
          ),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(await repository.refs.resolveRef('refs/heads/missing'), isNull);
    });

    test('reads the symbolic target of HEAD', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          const <String>['symbolic-ref', '--quiet', 'HEAD'],
          GitRunResult.fromStrings('refs/heads/main\n'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      expect(
        await repository.refs.symbolicTarget('HEAD'),
        'refs/heads/main',
      );
      expect(
        runner.requests.single.arguments,
        const <String>['symbolic-ref', '--quiet', 'HEAD'],
      );
    });

    test('refuses a malformed for-each-ref line', () async {
      final ScriptedGitRunner runner = ScriptedGitRunner()
        ..replyTo(
          _listRefsCommand,
          GitRunResult.fromStrings('refs/heads/main without a tab\n'),
        );
      final ProcessGitWorkingRepository repository =
          syntheticWorkingRepository(runner);

      await expectLater(
        repository.refs.listRefs(),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
