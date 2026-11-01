import 'git_commit.dart';
import 'git_oid.dart';

/// One commit of a history walk: its object name and the complete commit.
///
/// Unlike [GitLogEntry], which keeps only the subject, this carries the whole
/// [GitCommit] — tree, parents, identities, dates and the exact message.
/// {@category Getting started}
final class GitLogCommit {
  /// Object name of the commit.
  final GitOid oid;

  /// The commit object [oid] names.
  final GitCommit commit;

  /// Creates an entry of [oid] carrying [commit].
  const GitLogCommit({required this.oid, required this.commit});

  @override
  bool operator ==(Object other) =>
      other is GitLogCommit && other.oid == oid && other.commit == commit;

  @override
  int get hashCode => Object.hash(oid, commit);

  @override
  String toString() =>
      'GitLogCommit(${oid.short()}: ${commit.message.split('\n').first})';
}
