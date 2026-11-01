import '../../models/git_log_commit.dart';
import '../../models/git_log_entry.dart';
import '../../models/git_oid.dart';
import '../refs/git_unknown_revision_exception.dart';
import 'git_history_reader.dart';

/// History of one repository: ancestry, merge bases and path history.
///
/// The revision expressions of its parameters follow the grammar documented
/// on `GitRevisionResolver`: an expression that reads like an option — it
/// starts with `-` — names no revision, and the operations refuse with
/// [GitUnknownRevisionException] before any command runs. Paths are literal
/// and always travel after git's `--` marker, so a path can never be read as
/// an option either.
///
/// ```dart
/// final GitOid? forkPoint = await repo.history.mergeBase(head, base);
/// final bool contained = await repo.history.isAncestor(base, head);
/// final List<GitOid> touching =
///     await repo.history.commitsTouching('README.md');
/// final List<GitLogEntry> carried =
///     await repo.history.commitsSince(base.value, 'refs/heads/topic');
/// final List<GitLogCommit> recent = await repo.history.log(limit: 20);
/// ```
/// {@category Getting started}
abstract interface class GitHistory implements GitHistoryReader {
  /// Whether [ancestor] is an ancestor of [descendant]; see
  /// [GitHistoryReader.isAncestor].
  @override
  Future<bool> isAncestor(GitOid ancestor, GitOid descendant);

  /// Best common ancestor of [first] and [second]; see
  /// [GitHistoryReader.mergeBase].
  @override
  Future<GitOid?> mergeBase(GitOid first, GitOid second);

  /// Complete commits reachable from [to] but not from [from].
  ///
  /// [to] and [from] are revision expressions of the grammar documented on
  /// `GitRevisionResolver`; [from] defaults to null, which leaves the walk
  /// unbounded below. When [from] is given, everything it makes reachable is
  /// excluded from the result.
  ///
  /// [path] restricts the walk to the commits that change that literal path
  /// relative to the repository root; no glob (`*`, `?`, `[...]`) and no magic
  /// `:(...)` syntax is interpreted. A directory covers its content and `.`
  /// covers the whole repository.
  ///
  /// [limit] caps the result at that many commits; zero or a negative value
  /// raises an [ArgumentError].
  ///
  /// [firstParent] follows only the first parent of a merge.
  ///
  /// The order is the library's, not git's default: every commit comes before
  /// all of its parents, and between independent commits the one with the
  /// newest commit date comes first. The process backend asks git for the
  /// equivalent of `--date-order`, so the order does not depend on git's
  /// default traversal.
  ///
  /// A repository with no commit and [to] left at its default `HEAD` yields an
  /// empty list. Raises [GitUnknownRevisionException] when [to] or [from]
  /// names no revision.
  ///
  /// Prefer this to [commitsSince] whenever the full commit is needed: it
  /// avoids reading the object separately for each entry.
  Future<List<GitLogCommit>> log({
    String to = 'HEAD',
    String? from,
    String? path,
    int? limit,
    bool firstParent = false,
  });

  /// Most recent commit that touched [path], or null when none did.
  ///
  /// [path] is a literal path relative to the repository root; no glob (`*`,
  /// `?`, `[...]`) and no magic `:(...)` syntax is interpreted. [rev] is a
  /// revision expression of the grammar documented on `GitRevisionResolver`
  /// and defaults to `HEAD`.
  ///
  /// With [rev] given, raises [GitUnknownRevisionException] when it names no
  /// revision.
  ///
  /// Prefer [log] with a `limit` of 1 when the full commit is needed.
  Future<GitOid?> lastCommitTouching(String path, {String? rev});

  /// Commits reachable from [to] but not from [from] that touched [path],
  /// newest first.
  ///
  /// [path] is a literal path relative to the repository root; no glob (`*`,
  /// `?`, `[...]`) and no magic `:(...)` syntax is interpreted. [from] and
  /// [to] are revision expressions of the grammar documented on
  /// `GitRevisionResolver` and both default to `HEAD`, so without them the
  /// whole history of [path] is returned. A path touched by none of the commits
  /// in the range yields an empty list.
  ///
  /// Raises [GitUnknownRevisionException] when [from] or [to] names no
  /// revision.
  ///
  /// Prefer [log] with `path: path` when the full commits are needed.
  Future<List<GitOid>> commitsTouching(String path, {String? from, String? to});

  /// Commits reachable from [tip] but not from [base], newest first, each
  /// named with its subject.
  ///
  /// [base] and [tip] are revision expressions of the grammar documented on
  /// `GitRevisionResolver` — an object name, a branch, a range end like
  /// `origin/main`. Unlike [commitsTouching], the walk is not
  /// restricted to a path: every commit the range carries is returned, so a
  /// branch is listed by what it carries since a recorded base. The subject
  /// of an entry is git's own: the first paragraph of the commit message,
  /// line breaks folded to spaces. A range that carries nothing — [tip] equal
  /// to [base], or [base] already containing everything — yields an empty
  /// list.
  ///
  /// Raises [GitUnknownRevisionException] when [base] or [tip] names no
  /// revision.
  ///
  /// Prefer [log] with `from: base, to: tip` when the full commit is needed:
  /// this walk keeps only the object name and the subject.
  Future<List<GitLogEntry>> commitsSince(String base, String tip);
}
