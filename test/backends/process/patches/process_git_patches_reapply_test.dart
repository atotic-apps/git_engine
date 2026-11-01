@Tags(['git'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../../../contract/repository/patches_contract_support.dart';
import '../support/test_repository.dart';

const String _dataPath = 'data.dat';
const String _initialContent = 'original data\n';
const String _finalContent = 'updated data\n';

typedef _Configure = Future<void> Function(TestRepository repository);

/// A repository setting that changes what `git diff` prints unless the patch
/// commands neutralise it.
final class _Scenario {
  const _Scenario(this.description, this.configure, {this.textconv = false});

  /// Name of the setting, used in the test group title.
  final String description;

  /// Applies the setting to a fresh repository.
  final _Configure configure;

  /// Whether the setting routes the file through a textconv filter whose
  /// output must stay out of the patch.
  final bool textconv;
}

final List<_Scenario> _scenarios = <_Scenario>[
  _Scenario(
    'a textconv driver',
    _configureTextconv,
    textconv: true,
  ),
  _Scenario('diff.noprefix', _configureNoPrefix),
  _Scenario('diff.external', _configureExternalDiff),
];

void main() {
  for (final _Scenario scenario in _scenarios) {
    group('patches with ${scenario.description}', () {
      late TestRepository testRepository;
      late ProcessGitWorkingRepository repository;

      setUp(() async {
        testRepository = await createTestRepository();
        repository = await ProcessGitEngine(runner: testRepository.runner)
                .openWorking(testRepository.directory.path)
            as ProcessGitWorkingRepository;
        await scenario.configure(testRepository);
      });

      test('binaryDiff produces a reapplyable patch', () async {
        final GitOid base = await commitFiles(
          repository,
          <String, Object>{_dataPath: _initialContent},
          'base',
        );
        final GitOid target = await commitFiles(
          repository,
          <String, Object>{_dataPath: _finalContent},
          'target',
        );

        final Uint8List patch =
            await repository.patches.binaryDiff(base, target);
        _expectReapplyablePatch(patch, scenario);

        await _restore(repository, base);
        expect(readRepoText(repository, _dataPath), _initialContent);
        expect(await repository.patches.apply(patch), isA<GitApplyApplied>());
        expect(readRepoText(repository, _dataPath), _finalContent);
      });

      test('binaryDiffAgainstIndex produces a reapplyable patch', () async {
        final GitOid base = await commitFiles(
          repository,
          <String, Object>{_dataPath: _initialContent},
          'base',
        );
        writeRepoFile(repository.path, _dataPath, _finalContent);
        await repository.worktree.addAll();

        final Uint8List patch =
            await repository.patches.binaryDiffAgainstIndex(base);
        _expectReapplyablePatch(patch, scenario);

        await _restore(repository, base);
        expect(readRepoText(repository, _dataPath), _initialContent);
        expect(await repository.patches.apply(patch), isA<GitApplyApplied>());
        expect(readRepoText(repository, _dataPath), _finalContent);
      });

      test('binaryDiffAgainstWorkTree produces a reapplyable patch', () async {
        final GitOid base = await commitFiles(
          repository,
          <String, Object>{_dataPath: _initialContent},
          'base',
        );
        writeRepoFile(repository.path, _dataPath, _finalContent);

        final Uint8List patch =
            await repository.patches.binaryDiffAgainstWorkTree();
        _expectReapplyablePatch(patch, scenario);

        await _restore(repository, base);
        expect(readRepoText(repository, _dataPath), _initialContent);
        expect(await repository.patches.apply(patch), isA<GitApplyApplied>());
        expect(readRepoText(repository, _dataPath), _finalContent);
      });

      test('binaryDiffFromTree produces a reapplyable patch', () async {
        final GitOid base = await commitFiles(
          repository,
          <String, Object>{_dataPath: _initialContent},
          'base',
        );
        writeRepoFile(repository.path, _dataPath, _finalContent);

        final Uint8List patch =
            await repository.patches.binaryDiffFromTree(base);
        _expectReapplyablePatch(patch, scenario);

        await _restore(repository, base);
        expect(readRepoText(repository, _dataPath), _initialContent);
        expect(await repository.patches.apply(patch), isA<GitApplyApplied>());
        expect(readRepoText(repository, _dataPath), _finalContent);
      });
    });
  }
}

/// Puts the index and the work tree back on [tree].
Future<void> _restore(GitWorkingRepository repository, GitOid tree) {
  return repository.worktree.reset(mode: GitResetMode.hard, target: tree.value);
}

/// Checks [patch] carries the `a/` and `b/` prefixes, and for a textconv
/// scenario the file contents rather than the filter's output.
void _expectReapplyablePatch(Uint8List patch, _Scenario scenario) {
  final String text = utf8.decode(patch);
  expect(
    text,
    contains('diff --git a/$_dataPath b/$_dataPath'),
    reason: 'the patch must name the file with the standard prefixes',
  );
  if (!scenario.textconv) {
    return;
  }
  expect(text, contains(_initialContent.trim()));
  expect(text, contains(_finalContent.trim()));
  for (final String line in const LineSplitter().convert(text)) {
    if (line.startsWith('---') || line.startsWith('+++')) {
      continue;
    }
    expect(
      RegExp(r'^[+-][0-9a-f]{40}$').hasMatch(line),
      isFalse,
      reason: 'the textconv filter output must not reach the patch: $line',
    );
  }
}

/// Marks `*.dat` with a diff driver whose filter prints the content hash.
Future<void> _configureTextconv(TestRepository testRepository) async {
  testRepository.writeFile('.gitattributes', '*.dat diff=audit\n');
  await testRepository.runGit(const <String>['add', '.gitattributes']);
  await testRepository.runGit(
    const <String>['commit', '-m', 'attributes'],
  );
  await testRepository.runGit(
    const <String>['config', 'diff.audit.textconv', 'git hash-object'],
  );
}

/// Turns off the `a/` and `b/` prefixes.
Future<void> _configureNoPrefix(TestRepository testRepository) {
  return testRepository.runGit(
    const <String>['config', 'diff.noprefix', 'true'],
  );
}

/// Replaces every diff with the output of another command.
Future<void> _configureExternalDiff(TestRepository testRepository) {
  return testRepository.runGit(
    const <String>['config', 'diff.external', 'git version'],
  );
}
