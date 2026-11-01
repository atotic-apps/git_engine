import '../../models/git_oid.dart';
import '../../models/git_ref.dart';

/// Read access to the references of one repository.
///
/// This is a capability contract: a backend implements it only when it can
/// honour every operation.
/// {@category Getting started}
/// {@category Compatibility}
abstract interface class GitRefReader {
  /// Resolves the exact reference [refName] to the object it points at.
  ///
  /// [refName] is a full reference name such as `HEAD`, `refs/heads/main` or
  /// `refs/tags/v1`. Unlike a revision expression, it is never interpreted:
  /// `HEAD~1`, `main^{tree}` and a short branch name are not reference names
  /// and yield null. Returns null when [refName] does not exist, including
  /// `HEAD` in a repository without commits.
  Future<GitOid?> resolveRef(String refName);

  /// Target of the symbolic reference [refName], e.g.
  /// `refs/heads/main` for `HEAD`.
  ///
  /// Returns null when [refName] is not symbolic — a direct reference such as
  /// `refs/heads/main` — or does not exist. The target does not have to
  /// exist: in a repository without commits, `HEAD` still points at the
  /// branch it is set to create.
  Future<String?> symbolicTarget(String refName);

  /// Every reference whose full name starts with [prefix], ordered by full
  /// name.
  ///
  /// With a null [prefix], every reference of the repository is returned. A
  /// prefix such as `refs/heads/` selects one namespace; it is matched
  /// literally, not as a glob.
  Future<List<GitRef>> listRefs({String? prefix});
}
