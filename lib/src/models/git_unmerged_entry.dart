import 'git_oid.dart';

/// One stage of a path left unmerged in the index.
///
/// A conflicted path normally appears once per stage: `1` for the common
/// ancestor, `2` for the current branch and `3` for the other branch.
/// {@category Getting started}
class GitUnmergedEntry {
  /// Octal file mode as git prints it, e.g. `100644`.
  final String mode;

  /// Object name recorded for this stage.
  final GitOid oid;

  /// Merge stage: 1 (base), 2 (ours) or 3 (theirs).
  final int stage;

  /// Path of the entry relative to the repository root, `/`-separated.
  final String path;

  /// Creates one stage of [path]: [oid] at [mode] for [stage].
  const GitUnmergedEntry({
    required this.mode,
    required this.oid,
    required this.stage,
    required this.path,
  });

  @override
  bool operator ==(Object other) =>
      other is GitUnmergedEntry &&
      other.mode == mode &&
      other.oid == oid &&
      other.stage == stage &&
      other.path == path;

  @override
  int get hashCode => Object.hash(mode, oid, stage, path);

  @override
  String toString() => '$mode $oid $stage\t$path';
}
