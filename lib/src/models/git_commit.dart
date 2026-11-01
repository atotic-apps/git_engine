import 'git_identity.dart';
import 'git_oid.dart';

/// A commit object: its tree, parents, identities and message.
///
/// The dates are the instants git recorded, expressed in UTC. A git commit
/// also records the time zone its author and committer were in; a [DateTime]
/// cannot carry an arbitrary offset, so that offset is not kept here.
/// {@category Getting started}
class GitCommit {
  /// Tree object the commit snapshots.
  final GitOid tree;

  /// Parent commits in order; empty for a root commit and two entries for an
  /// ordinary merge commit.
  final List<GitOid> parents;

  /// Identity that authored the commit.
  final GitIdentity author;

  /// Instant the commit was authored, in UTC.
  final DateTime authorDate;

  /// Identity that committed the commit.
  final GitIdentity committer;

  /// Instant the commit was created, in UTC.
  final DateTime committerDate;

  /// Commit message, subject and body, without git's trailing newline.
  final String message;

  /// Creates a commit of [tree], [parents], [author], [committer] and
  /// [message].
  GitCommit({
    required this.tree,
    required List<GitOid> parents,
    required this.author,
    required this.authorDate,
    required this.committer,
    required this.committerDate,
    required this.message,
  }) : parents = List<GitOid>.unmodifiable(parents);

  @override
  bool operator ==(Object other) =>
      other is GitCommit &&
      other.tree == tree &&
      _sameParents(other.parents) &&
      other.author == author &&
      other.authorDate == authorDate &&
      other.committer == committer &&
      other.committerDate == committerDate &&
      other.message == message;

  @override
  int get hashCode => Object.hash(
        tree,
        Object.hashAll(parents),
        author,
        authorDate,
        committer,
        committerDate,
        message,
      );

  /// Whether [other] lists the same parents in the same order.
  bool _sameParents(List<GitOid> other) {
    if (other.length != parents.length) {
      return false;
    }
    for (var index = 0; index < parents.length; index++) {
      if (other[index] != parents[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => 'commit $tree (${parents.length} parents) '
      'by $author: ${message.split('\n').first}';
}
