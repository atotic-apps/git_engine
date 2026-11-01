import 'package:git_engine/git_engine.dart';

import 'git_command_exception.dart';

/// Diagnostics git prints, in English, when a revision expression names
/// nothing.
///
/// Every formulation of the supported git releases (2.28 to 2.5x): the
/// ambiguous-argument refusal of the plumbing commands, the reference
/// refusal of a checkout start point, the pathspec refusal of an older
/// `git checkout`, the path-argument refusal of `checkout --detach`, the
/// unresolvable start point of `checkout -b`, the unresolvable target of a
/// tag creation, the merge refusal, and the `rev-parse` refusals of an
/// unknown name and of an upstream that was never set.
const List<String> unknownRevisionPhrases = <String>[
  'unknown revision or path not in the working tree',
  'invalid reference: ',
  'did not match any file(s) known to git',
  'does not take a path argument',
  'cannot be created from it',
  'not something we can merge',
  'invalid object name',
  'not a valid object name',
  'as a valid ref',
  'nonexistent object',
  'no upstream configured for branch',
  'the requested upstream branch',
  'bad revision',
];

/// Diagnostics git prints when a checkout or a merge would overwrite the
/// local state of the work tree.
const String overwrittenByPhrase = 'would be overwritten by ';

/// Diagnostics git prints when a branch deleted without force is not fully
/// merged: `the branch` in the newer releases, `the branch` spelled with a
/// capital `T` in some older ones.
const String notFullyMergedPhrase = 'is not fully merged';

/// Diagnostics git prints when no merge is in progress: "no merge to abort"
/// under `merge --abort`, "no merge in progress" on the same state without a
/// started merge.
const Set<String> noMergePhrases = <String>{
  'no merge to abort',
  'no merge in progress',
};

/// Diagnostics git prints when two histories share no common ancestor.
const String unrelatedHistoriesPhrase = 'refusing to merge unrelated histories';

/// The failure a revision of [expression] raises: the
/// [GitUnknownRevisionException] git's refusal describes, or [error]
/// unchanged when it is another refusal.
GitException unknownRevisionFailure(
  GitCommandException error,
  String expression,
) {
  final String stderr = _normalized(error.stderr);
  for (final String phrase in unknownRevisionPhrases) {
    if (_contains(stderr, phrase)) {
      return GitUnknownRevisionException(expression: expression, cause: error);
    }
  }
  return error;
}

/// The failure a checkout raises (a branch switch, a detached checkout or a
/// new-branch checkout): the [GitLocalChangesOverwrittenException] when git
/// refuses because it would overwrite local changes or untracked files —
/// naming the paths it lists — a [GitUnknownRevisionException] when the
/// [expression] names nothing, or [error] unchanged when it is another
/// refusal.
GitException checkoutFailure(GitCommandException error, String expression) {
  final String stderr = _normalized(error.stderr);
  if (_contains(stderr, overwrittenByPhrase)) {
    return GitLocalChangesOverwrittenException(
      paths: _overwrittenPaths(_normalizedLineEndings(error.stderr)),
      cause: error,
    );
  }
  return unknownRevisionFailure(error, expression);
}

/// The failure a merge into the work tree of [rev] raises: the
/// [GitLocalChangesOverwrittenException] when git refuses because it would
/// overwrite local changes or untracked files — naming the paths it lists —
/// the [GitUnrelatedHistoriesException] of histories without a common
/// ancestor, a [GitUnknownRevisionException] when [rev] names nothing, or
/// [error] unchanged when it is another refusal.
GitException mergeFailure(GitCommandException error, String rev) {
  final String stderr = _normalized(error.stderr);
  if (_contains(stderr, overwrittenByPhrase)) {
    return GitLocalChangesOverwrittenException(
      paths: _overwrittenPaths(_normalizedLineEndings(error.stderr)),
      cause: error,
    );
  }
  if (_contains(stderr, unrelatedHistoriesPhrase)) {
    return GitUnrelatedHistoriesException(cause: error);
  }
  return unknownRevisionFailure(error, rev);
}

/// The failure a plain `git branch -d` raises: the
/// [GitBranchNotMergedException] of [branch] when git would lose its
/// commits, the [GitRefNotFoundException] of [branch] when it has none by
/// that name, or [error] unchanged when it is another refusal.
GitException branchDeletionFailure(GitCommandException error, String branch) {
  final String stderr = _normalized(error.stderr);
  if (_contains(stderr, notFullyMergedPhrase)) {
    return GitBranchNotMergedException(branch: branch, cause: error);
  }
  return branchNotFoundFailure(error, branch);
}

/// Diagnostics git prints when a branch or a tag name is already taken:
/// `fatal: a branch named 'x' already exists`, `fatal: tag 'x' already
/// exists`.
const String refExistsPhrase = 'already exists';

/// Diagnostics git prints when a branch administration command names a
/// branch that has no such name: the refusals of a deletion, of a rename in
/// the supported releases, and of an upstream assignment.
List<String> branchNotFoundPhrases(String branch) {
  final String name = branch.toLowerCase();
  return <String>[
    "branch '$name' not found",
    "branch '$name' does not exist",
    "no branch named '$name'",
    'refname refs/heads/$name not found',
  ];
}

/// Diagnostics git prints when a tag administration command names a tag
/// that has no such name: `error: tag 'x' not found.`.
String tagNotFoundPhrase(String tag) => "tag '${tag.toLowerCase()}' not found";

/// The failure creating or renaming a branch or a tag raises: the
/// [GitRefExistsException] of [name] when git refuses because the name is
/// taken, or [error] unchanged when it is another refusal.
GitException refExistsFailure(GitCommandException error, String name) {
  if (!_contains(_normalized(error.stderr), refExistsPhrase)) {
    return error;
  }
  return GitRefExistsException(name: name, cause: error);
}

/// The failure a branch administration command raises for a branch that has
/// no such name: the [GitRefNotFoundException] of [branch], or [error]
/// unchanged when it is another refusal.
GitException branchNotFoundFailure(GitCommandException error, String branch) {
  final String stderr = _normalized(error.stderr);
  for (final String phrase in branchNotFoundPhrases(branch)) {
    if (_contains(stderr, phrase)) {
      return GitRefNotFoundException(name: branch, cause: error);
    }
  }
  return error;
}

/// The failure a tag administration command raises for a tag that has no
/// such name: the [GitRefNotFoundException] of [tag], or [error] unchanged
/// when it is another refusal.
GitException tagNotFoundFailure(GitCommandException error, String tag) {
  if (!_contains(_normalized(error.stderr), tagNotFoundPhrase(tag))) {
    return error;
  }
  return GitRefNotFoundException(name: tag, cause: error);
}

/// The failure `git merge --abort` raises: the [GitNoMergeInProgressException]
/// the refusal describes, or [error] unchanged when it is another refusal.
GitException mergeAbortFailure(GitCommandException error) {
  final String stderr = _normalized(error.stderr);
  for (final String phrase in noMergePhrases) {
    if (_contains(stderr, phrase)) {
      return GitNoMergeInProgressException(cause: error);
    }
  }
  return error;
}

/// The failure a merge of unrelated histories raises: the
/// [GitUnrelatedHistoriesException] `refusing to merge unrelated histories`
/// describes, or [error] unchanged when it is another refusal.
GitException unrelatedHistoriesFailure(GitCommandException error) {
  if (!_contains(_normalized(error.stderr), unrelatedHistoriesPhrase)) {
    return error;
  }
  return GitUnrelatedHistoriesException(cause: error);
}

/// [stderr] with the line endings normalized, the case preserved.
String _normalizedLineEndings(String stderr) {
  return stderr.replaceAll('\r\n', '\n');
}

/// [stderr] with the line endings normalized and folded to lower case, so
/// one spelling covers the cases of every version.
String _normalized(String stderr) {
  return _normalizedLineEndings(stderr).toLowerCase();
}

/// Whether [stderr] holds [phrase].
bool _contains(String stderr, String phrase) {
  return stderr.contains(phrase);
}

/// Paths git names after its "would be overwritten" diagnostic, in the order
/// git lists them and in the case git wrote them: the lines indented with a
/// tab from the diagnostic to the advice line (blank lines some versions
/// insert are skipped).
List<String> _overwrittenPaths(String stderr) {
  final List<String> lines = stderr.split('\n');
  var index = 0;
  while (index < lines.length) {
    final String lowered = lines[index].toLowerCase();
    index++;
    if (lowered.startsWith('error: ') &&
        lowered.contains(overwrittenByPhrase)) {
      break;
    }
  }
  final List<String> paths = <String>[];
  while (index < lines.length) {
    final String line = lines[index];
    if (line.startsWith('\t')) {
      paths.add(line.substring(1).trim());
      index++;
      continue;
    }
    if (line.isEmpty) {
      index++;
      continue;
    }
    break;
  }
  return paths;
}
