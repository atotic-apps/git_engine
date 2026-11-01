import '../../core/errors/git_exception.dart';

/// A reference name an operation refuses before any git command runs.
///
/// Raised by the operations that receive a reference name to write —
/// `GitBranches.create`, `GitBranches.rename` (old and new name),
/// `GitBranches.delete`, `GitBranches.setUpstream`, `GitTags.create`,
/// `GitTags.delete`, `GitRefs.updateRef`, `GitRefs.deleteRef`,
/// `GitRefs.setHead` and `GitRefTransaction.create`, `update` and `delete`
/// at staging time, before `commit` runs. Nothing is admitted to a command
/// line either: with such a name rejected up front, a name can never be
/// interpreted by git as one of its options.
///
/// The rules are the reference-format rules of `git check-ref-format`, plus
/// one library rule:
///
/// - no component starting with `.` and no component ending with `.lock`;
/// - no `..` anywhere, no `@{` anywhere, no `@` alone;
/// - no ASCII control character (0x00 to 0x1F and 0x7F), no space, and none
///   of `~`, `^`, `:`, `?`, `*`, `[` or `\` anywhere;
/// - no `/` at the start, at the end or doubled;
/// - no `.` at the end;
/// - a library rule: no `-` at the start of the name, so a name can never
///   read like a git option.
///
/// Short branch names refuse `HEAD` on top: a branch is never named
/// `HEAD`, which names the checked-out branch itself. The full names the
/// write operations of `GitRefs` and `GitRefTransaction` take are
/// `refs/...` names under these rules, or one of the pseudo-references git
/// maintains at the top level: `HEAD`, `FETCH_HEAD`, `MERGE_HEAD`,
/// `ORIG_HEAD`, `CHERRY_PICK_HEAD` and `REVERT_HEAD`. Every other one-level
/// name is refused.
/// {@category Errors}
class GitInvalidRefNameException extends GitException {
  /// Name the operation was handed.
  final String name;

  /// The rule the name broke, in a short sentence.
  final String reason;

  /// Creates the refusal of [name], broken by [reason].
  GitInvalidRefNameException({
    required this.name,
    required this.reason,
  }) : super('the name "$name" is not a valid reference name: $reason');
}
