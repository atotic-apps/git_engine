import 'git_oid.dart';

/// A branch: its short name, the commit it points at, whether `HEAD` points
/// at it, and the branch it tracks.
/// {@category Getting started}
class GitBranch {
  /// Branch name without the `refs/heads/` prefix, e.g. `main`.
  final String name;

  /// Commit the branch points at.
  final GitOid oid;

  /// Whether `HEAD` currently points at this branch.
  final bool isCurrent;

  /// Short name of the branch this one tracks, e.g. `origin/main`, or null
  /// when it tracks none.
  final String? upstream;

  /// Creates a branch named [name] pointing at [oid], current on behalf of
  /// `HEAD` when [isCurrent] holds and tracking [upstream] when given.
  const GitBranch({
    required this.name,
    required this.oid,
    required this.isCurrent,
    this.upstream,
  });

  @override
  bool operator ==(Object other) =>
      other is GitBranch &&
      other.name == name &&
      other.oid == oid &&
      other.isCurrent == isCurrent &&
      other.upstream == upstream;

  @override
  int get hashCode => Object.hash(name, oid, isCurrent, upstream);

  @override
  String toString() =>
      upstream == null ? '$name -> $oid' : '$name -> $oid (tracks $upstream)';
}
