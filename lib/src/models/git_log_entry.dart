import 'git_oid.dart';

/// One commit of a history walk: its object name and its subject.
///
/// The subject is what git reports as the subject of the commit message: the
/// first paragraph, with the line breaks it spans folded to spaces.
/// {@category Getting started}
final class GitLogEntry {
  /// Object name of the commit.
  final GitOid oid;

  /// Subject of the commit message.
  final String subject;

  /// Creates an entry of [oid] and [subject].
  const GitLogEntry({required this.oid, required this.subject});

  @override
  bool operator ==(Object other) =>
      other is GitLogEntry && other.oid == oid && other.subject == subject;

  @override
  int get hashCode => Object.hash(oid, subject);

  @override
  String toString() => 'GitLogEntry(${oid.short()}: $subject)';
}
