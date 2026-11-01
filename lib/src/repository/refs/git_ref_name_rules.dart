import 'git_invalid_ref_name_exception.dart';
import 'git_unknown_revision_exception.dart';

/// The one-level references git itself maintains, which the write operations
/// of `GitRefs` and `GitRefTransaction` accept beside `refs/...` names.
///
/// Every other one-level name is refused: a written reference must carry the
/// `refs/` namespace or be one of these well-known pseudo-references.
const Set<String> specialRefNames = <String>{
  'HEAD',
  'FETCH_HEAD',
  'MERGE_HEAD',
  'ORIG_HEAD',
  'CHERRY_PICK_HEAD',
  'REVERT_HEAD',
};

/// The rule of reference format [name] breaks, in a short sentence, or null
/// when [name] is a valid name.
///
/// The rules follow the reference-format documentation of
/// `git check-ref-format`:
///
/// - no component starting with `.` and no component ending with `.lock`;
/// - no `..` anywhere, no `@{` anywhere, no `@` alone;
/// - no ASCII control character (0x00 to 0x1F and 0x7F), no space, and none
///   of `~ ^ : ? * [ \` anywhere;
/// - no `/` at the start, at the end or doubled;
/// - no `.` at the end;
/// - a library rule: no `-` at the start, so a name can never read like a
///   git option.
String? invalidRefNameReason(String name) {
  if (name.isEmpty) {
    return 'it is empty';
  }
  if (name.startsWith('-')) {
    return 'it starts with the option marker `-`';
  }
  for (final int unit in name.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) {
      return 'it holds the control character 0x${unit.toRadixString(16)}';
    }
    if (unit == 0x20) {
      return 'it holds a space';
    }
    switch (unit) {
      case 0x7e: // ~
      case 0x5e: // ^
      case 0x3a: // :
      case 0x3f: // ?
      case 0x2a: // *
      case 0x5b: // [
      case 0x5c: // \
        return 'it holds one of ~ ^ : ? * [ \\';
    }
  }
  if (name.contains('..')) {
    return 'it holds ".."';
  }
  if (name.contains('@{')) {
    return 'it holds "@{"';
  }
  if (name == '@') {
    return 'it is the lone "@"';
  }
  if (name.endsWith('.')) {
    return 'it ends with "."';
  }
  final List<String> components = name.split('/');
  if (components.any((String component) => component.isEmpty)) {
    return 'it begins, ends or doubles the slash "/"';
  }
  for (final String component in components) {
    if (component.startsWith('.')) {
      return 'the component "$component" starts with "."';
    }
    if (component.endsWith('.lock')) {
      return 'the component "$component" ends with ".lock"';
    }
  }
  return null;
}

/// Raises [GitInvalidRefNameException] when [name] breaks the rules of
/// [invalidRefNameReason].
void checkRefName(String name) {
  final String? reason = invalidRefNameReason(name);
  if (reason != null) {
    throw GitInvalidRefNameException(name: name, reason: reason);
  }
}

/// Raises [GitInvalidRefNameException] when [ref] cannot be the name of a
/// reference the write operations of `GitRefs` and `GitRefTransaction`
/// accept: a `refs/...` name, the rules of [invalidRefNameReason] applying
/// to it, or one reference of [specialRefNames]. Any other one-level name is
/// refused.
void checkWritableRefName(String ref) {
  if (specialRefNames.contains(ref)) {
    return;
  }
  if (!ref.startsWith('refs/')) {
    throw GitInvalidRefNameException(
      name: ref,
      reason: 'a written reference is a refs/... name or a well-known '
          'pseudo-reference',
    );
  }
  checkRefName(ref);
}

/// Raises [GitInvalidRefNameException] when [name] cannot be a short branch
/// name: the rules of [invalidRefNameReason], and `HEAD` is refused as well —
/// a branch is never named `HEAD`, which names the checked-out branch itself.
void checkBranchName(String name) {
  if (name == 'HEAD') {
    throw GitInvalidRefNameException(
      name: name,
      reason: 'a branch is never named "HEAD"',
    );
  }
  checkRefName(name);
}

/// Raises [GitInvalidRefNameException] when [name] cannot be a short tag
/// name: the rules of [invalidRefNameReason] alone.
void checkTagName(String name) {
  checkRefName(name);
}

/// Whether git, launched without a shell, would read [token] as one of its
/// own options because it starts with the `-` marker.
///
/// Revision expressions handed to an operation go through this gate before
/// git runs: one that starts with `-` names no revision and the operation
/// refuses before any command runs — a `GitUnknownRevisionException` where
/// the operation raises that exception, null where it documents a null
/// result.
bool readsAsOption(String token) => token.startsWith('-');

/// Raises [GitUnknownRevisionException] when [expression] names no revision
/// because git would read it as an option: it starts with the `-` marker.
///
/// Every operation that takes a revision expression and maps git's refusal
/// of an unknown name to [GitUnknownRevisionException] runs this gate before
/// its first command, so an expression like `--output=x` can never reach git
/// as an option argument.
void refuseOptionLikeRevision(String expression) {
  if (readsAsOption(expression)) {
    throw GitUnknownRevisionException(expression: expression);
  }
}
