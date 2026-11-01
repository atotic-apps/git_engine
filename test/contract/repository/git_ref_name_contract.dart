import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../backend_factory.dart';

/// Declares the reference-name rule and the option-shaped refusal contract
/// against [factory].
///
/// No string handed to a facade may be read by git as an option: names are
/// rejected before any command runs, revision expressions starting with `-`
/// name nothing, and the reference transaction never mixes a second command
/// into a name. Every group runs the same suite on a bare repository and on
/// a clone; the side effects the audit reproductions relied on — a deleted
/// branch, an overwritten file, a created reference — are asserted absent.
void defineGitRefNameContract(BackendFactory factory) {
  const List<ScenarioCommit> scenario = <ScenarioCommit>[
    ScenarioCommit(
      message: 'Base',
      files: <String, String>{'tracked.txt': 'one\n'},
    ),
  ];

  group('GitRefNameRule contract', () {
    for (final _RepositoryKind kind in _RepositoryKind.values) {
      group(kind.label, () {
        test('a branch creation that names an option writes nothing', () async {
          final ScenarioRepository built =
              await _repository(factory, kind, scenario);
          final GitRepository repository = built.repository;
          await repository.branches.create('victim');

          await expectLater(
            repository.branches.create(
              '--delete',
              startPoint: 'victim',
              force: true,
            ),
            throwsA(isA<GitInvalidRefNameException>().having(
              (GitInvalidRefNameException error) => error.name,
              'name',
              '--delete',
            )),
          );

          expect(await repository.refs.exists('refs/heads/victim'), isTrue);
        });

        test('a history call with an option-shaped revision writes no file',
            () async {
          final ScenarioRepository built =
              await _repository(factory, kind, scenario);
          final GitRepository repository = built.repository;
          final Directory sandbox =
              await Directory.systemTemp.createTemp('git_engine_ref_name_');
          addTearDown(() => sandbox.delete(recursive: true));
          final File victim = File(Platform.isWindows
              ? '${sandbox.path}\\stolen.txt'
              : '${sandbox.path}/stolen.txt');

          await expectLater(
            repository.history.lastCommitTouching(
              'tracked.txt',
              rev: '--output=${victim.path}',
            ),
            throwsA(
              isA<GitUnknownRevisionException>().having(
                (GitUnknownRevisionException error) => error.expression,
                'expression',
                '--output=${victim.path}',
              ),
            ),
          );

          expect(victim.existsSync(), isFalse);
          expect(
            await repository.history.lastCommitTouching('tracked.txt'),
            built.commits.last,
            reason: 'the ordinary call keeps working',
          );
        });

        test('a transaction refuses a scripted second command at staging',
            () async {
          final ScenarioRepository built =
              await _repository(factory, kind, scenario);
          final GitRepository repository = built.repository;
          final GitRefTransaction transaction =
              repository.beginRefTransaction();

          final String scripted =
              'refs/heads/intended ${built.commits.last.value}\n'
              'create refs/heads/unexpected';
          expect(
            () => transaction.create(scripted, built.commits.last),
            throwsA(isA<GitInvalidRefNameException>().having(
              (GitInvalidRefNameException error) => error.name,
              'name',
              scripted,
            )),
          );

          expect(
              await repository.refs.exists('refs/heads/unexpected'), isFalse);
        });

        test('a transaction refuses an option-shaped name at staging',
            () async {
          final ScenarioRepository built =
              await _repository(factory, kind, scenario);
          final GitRepository repository = built.repository;
          final GitOid oid = built.commits.last;

          final GitRefTransaction updateRunner =
              repository.beginRefTransaction();
          expect(
            () => updateRunner.update('--output=x', oid),
            throwsA(isA<GitInvalidRefNameException>()),
          );

          final GitRefTransaction deleteRunner =
              repository.beginRefTransaction();
          expect(
            () => deleteRunner.delete('-d'),
            throwsA(isA<GitInvalidRefNameException>()),
          );
          expect(await repository.refs.exists('refs/heads/stego'), isFalse);
        });

        test('every refused rule raises before any git call', () async {
          final ScenarioRepository built =
              await _repository(factory, kind, scenario);
          final GitRepository repository = built.repository;
          await repository.branches.create('supervisor');

          const List<ScenarioCommit> refused = <ScenarioCommit>[];
          final List<String> rules = <String>[
            'a/b/.dot/name',
            'refs/heads/name.lock',
            'a..b',
            'name@{head}',
            '@',
            'a\x01b',
            'a b',
            'a~b',
            'a^b',
            'a:b',
            'a?b',
            'a*b',
            'a[b',
            'a\\b',
            '/name',
            'name/',
            'a//b',
            'name.',
            '-branchy',
          ];
          for (final String name in rules) {
            await expectLater(
              repository.branches.create(name),
              throwsA(isA<GitInvalidRefNameException>().having(
                (GitInvalidRefNameException error) => error.name,
                'name',
                name,
              )),
            );
          }

          expect(refused, isEmpty);
          expect(
            await repository.refs.exists('refs/heads/supervisor'),
            isTrue,
          );
        });

        test('HEAD is refused as a branch short name, kept for tags', () async {
          final ScenarioRepository built =
              await _repository(factory, kind, scenario);
          final GitRepository repository = built.repository;
          final GitOid oid = built.commits.last;

          await expectLater(
            repository.branches.create('HEAD'),
            throwsA(isA<GitInvalidRefNameException>().having(
              (GitInvalidRefNameException error) => error.name,
              'name',
              'HEAD',
            )),
          );
          await expectLater(
            repository.branches.rename('HEAD', 'renamed'),
            throwsA(isA<GitInvalidRefNameException>()),
          );
          await expectLater(
            repository.refs.setHead('HEAD'),
            throwsA(isA<GitInvalidRefNameException>()),
          );

          await repository.tags.create('HEAD', oid);
          final List<String> afterCreate =
              _tagNames(await repository.tags.list());
          expect(afterCreate, contains('HEAD'));
          await repository.tags.delete('HEAD');
          final List<String> afterDelete =
              _tagNames(await repository.tags.list());
          expect(afterDelete, isNot(contains('HEAD')));
        });

        test('unicode, slashes and mid dashes are accepted', () async {
          final ScenarioRepository built =
              await _repository(factory, kind, scenario);
          final GitRepository repository = built.repository;
          final GitOid oid = built.commits.last;

          await repository.branches.create('feature/sub-fix');
          await repository.branches.create('a-branch-with-mid-dash');
          await repository.branches.create('système/locale-é.task_2');

          final List<String> names =
              _branchNames(await repository.branches.list());
          expect(
              names,
              containsAll(<String>[
                'feature/sub-fix',
                'a-branch-with-mid-dash',
                'système/locale-é.task_2',
              ]));
          await repository.tags.create('release/système-é.fix', oid);
          expect(
            _tagNames(await repository.tags.list()),
            contains('release/système-é.fix'),
          );
        });

        test('the writable full names follow the same rule', () async {
          final ScenarioRepository built =
              await _repository(factory, kind, scenario);
          final GitRepository repository = built.repository;
          final GitOid oid = built.commits.last;

          await repository.refs.updateRef('refs/heads/full/with-slash', oid);
          expect(
            await repository.refs.resolveRef('refs/heads/full/with-slash'),
            oid,
          );

          expect(
            () => repository.refs.updateRef('.hidden-name', oid),
            throwsA(isA<GitInvalidRefNameException>()),
          );
          expect(
            () => repository.refs.deleteRef('-armored'),
            throwsA(isA<GitInvalidRefNameException>()),
          );
          await repository.refs.updateRef('MERGE_HEAD', oid);
          expect(
            () => repository.refs.updateRef('ARBITRARY_HEAD', oid),
            throwsA(isA<GitInvalidRefNameException>()),
          );
        });
      });
    }

    group('option-shaped revisions in every refusing operation', () {
      test('branch creation refuses an option start point', () async {
        final GitWorkingRepository repository =
            await _workingRepository(factory);
        await expectLater(
          repository.branches.create('topic', startPoint: '--output=x'),
          throwsA(
            isA<GitUnknownRevisionException>().having(
              (GitUnknownRevisionException error) => error.expression,
              'expression',
              '--output=x',
            ),
          ),
        );
        expect(await repository.refs.exists('refs/heads/topic'), isFalse);
      });

      test('setUpstream refuses an option-shaped upstream', () async {
        final GitWorkingRepository repository =
            await _workingRepository(factory);
        await expectLater(
          repository.branches.setUpstream('main', '--print-main'),
          throwsA(
            isA<GitUnknownRevisionException>().having(
              (GitUnknownRevisionException error) => error.expression,
              'expression',
              '--print-main',
            ),
          ),
        );
      });

      test('resetSoft refuses an option-shaped target', () async {
        final GitWorkingRepository repository =
            await _workingRepository(factory);
        await expectLater(
          repository.refs.resetSoft('--reference=x'),
          throwsA(isA<GitUnknownRevisionException>()),
        );
      });

      test('worktree reset refuses an option-shaped target', () async {
        final GitWorkingRepository repository =
            await _workingRepository(factory);
        await expectLater(
          repository.worktree.reset(target: '--refile=x'),
          throwsA(isA<GitUnknownRevisionException>()),
        );
      });

      test('checkout refuses an option-shaped branch', () async {
        final GitWorkingRepository repository =
            await _workingRepository(factory);
        await expectLater(
          repository.worktree.checkout('-b-escape'),
          throwsA(isA<GitUnknownRevisionException>()),
        );
      });

      test('checkoutDetached refuses an option-shaped revision', () async {
        final GitWorkingRepository repository =
            await _workingRepository(factory);
        await expectLater(
          repository.worktree.checkoutDetached('--dry-run'),
          throwsA(isA<GitUnknownRevisionException>()),
        );
      });

      test('checkoutNewBranch refuses both option shapes', () async {
        final GitWorkingRepository repository =
            await _workingRepository(factory);
        await expectLater(
          repository.worktree.checkoutNewBranch('--optionrush'),
          throwsA(isA<GitUnknownRevisionException>()),
        );
        await expectLater(
          repository.worktree.checkoutNewBranch(
            'topic',
            startPoint: '-checkout-escape',
          ),
          throwsA(isA<GitUnknownRevisionException>()),
        );
      });

      test('merge refuses an option-shaped revision', () async {
        final GitWorkingRepository repository =
            await _workingRepository(factory);
        await expectLater(
          repository.merge.merge('--onto=x'),
          throwsA(isA<GitUnknownRevisionException>()),
        );
        expect(await repository.merge.isMerging(), isFalse);
      });

      test('history refuses option-shaped range ends', () async {
        final GitWorkingRepository repository =
            await _workingRepository(factory);
        await expectLater(
          repository.history.log(from: '--output=x'),
          throwsA(isA<GitUnknownRevisionException>()),
        );
        await expectLater(
          repository.history.log(to: '--numstat'),
          throwsA(isA<GitUnknownRevisionException>()),
        );
        await expectLater(
          repository.history.commitsTouching(
            'tracked.txt',
            from: '-diff-filter=x',
          ),
          throwsA(isA<GitUnknownRevisionException>()),
        );
        await expectLater(
          repository.history.commitsTouching(
            'tracked.txt',
            to: '-diff-filter=x',
          ),
          throwsA(isA<GitUnknownRevisionException>()),
        );
        await expectLater(
          repository.history.commitsSince('-stat', 'HEAD'),
          throwsA(isA<GitUnknownRevisionException>()),
        );
        await expectLater(
          repository.history.commitsSince('HEAD', '--output=x'),
          throwsA(isA<GitUnknownRevisionException>()),
        );
        await expectLater(
          repository.history.lastCommitTouching(
            'tracked.txt',
            rev: '-grep=x',
          ),
          throwsA(isA<GitUnknownRevisionException>()),
        );
      });

      test('symbolicFullName refuses an option-shaped revision', () async {
        final GitWorkingRepository repository =
            await _workingRepository(factory);
        await expectLater(
          repository.revisions.symbolicFullName('--short'),
          throwsA(isA<GitUnknownRevisionException>()),
        );
      });

      test('resolveRevision names nothing as well', () async {
        final GitWorkingRepository repository =
            await _workingRepository(factory);
        expect(
          await repository.revisions.resolveRevision('--output=x'),
          isNull,
        );
        expect(await repository.revisions.resolveRevision('-1'), isNull);
      });
    });
  });
}

/// The two repository shapes the rule applies on; every group runs on each.
enum _RepositoryKind {
  /// A bare repository, where no work tree shields the references.
  bare('bare repository'),

  /// A clone with a work tree, as a caller normally holds.
  clone('clone with a work tree');

  const _RepositoryKind(this.label);

  /// Human-readable name used in the test groups.
  final String label;
}

/// Builds a repository of [kind] over [scenario] through [factory].
Future<ScenarioRepository> _repository(
  BackendFactory factory,
  _RepositoryKind kind,
  List<ScenarioCommit> scenario,
) async {
  switch (kind) {
    case _RepositoryKind.bare:
      return factory.createBareRepositoryFromScenario(scenario);
    case _RepositoryKind.clone:
      return factory.createRepositoryFromScenario(scenario);
  }
}

/// A fresh working repository with the scenario applied once.
Future<GitWorkingRepository> _workingRepository(
  BackendFactory factory,
) async {
  final ScenarioRepository built = await factory.createRepositoryFromScenario(
    const <ScenarioCommit>[
      ScenarioCommit(
        message: 'Base',
        files: <String, String>{'tracked.txt': 'one\n'},
      ),
    ],
  );
  return built.repository as GitWorkingRepository;
}

/// Short names of the branch listing.
List<String> _branchNames(List<GitBranch> branches) {
  return branches.map((GitBranch branch) => branch.name).toList();
}

/// Short names of the tag listing.
List<String> _tagNames(List<GitTagRef> tags) {
  return tags.map((GitTagRef tag) => tag.name).toList();
}
