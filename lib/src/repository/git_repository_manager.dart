import '../core/errors/git_not_a_bare_repository_exception.dart';
import '../core/errors/git_not_a_repository_exception.dart';
import '../core/errors/git_not_a_working_repository_exception.dart';
import '../core/errors/git_occupied_directory_exception.dart';
import 'git_file_bare_repository.dart';
import 'git_file_repository.dart';
import 'git_working_repository.dart';

/// Manager role over repositories stored on disk: it opens and creates them.
///
/// Opening returns a [GitFileRepository]: it works on paths, so it always
/// produces a repository stored on disk. The precise type — working or bare —
/// is fixed when the repository is opened, from git's own answer.
/// [openWorking] and [openBare] return that precise type when the caller
/// already knows which one to expect.
///
/// Cloning is not a manager operation: it belongs to the client role, exposed
/// by `GitFileClient` in `lib/src/client/`.
/// {@category Getting started}
abstract interface class GitRepositoryManager {
  /// Opens the repository living at [path] (its work tree, or its `.git`
  /// directory for bare repositories).
  ///
  /// The returned value is a [GitWorkingRepository] when the repository has a
  /// work tree and a [GitFileBareRepository] when it is bare. Opening reads
  /// the kind of repository from git, so a directory that is not a repository
  /// fails immediately with [GitNotARepositoryException] instead of on the
  /// first later command.
  Future<GitFileRepository> open(String path);

  /// Opens [path] and returns it as a [GitWorkingRepository].
  ///
  /// Fails with [GitNotAWorkingRepositoryException] when the repository is
  /// bare, and with [GitNotARepositoryException] when [path] is not a
  /// repository at all.
  Future<GitWorkingRepository> openWorking(String path);

  /// Opens [path] and returns it as a [GitFileBareRepository].
  ///
  /// Fails with [GitNotABareRepositoryException] when the repository has a
  /// work tree, and with [GitNotARepositoryException] when [path] is not a
  /// repository at all.
  Future<GitFileBareRepository> openBare(String path);

  /// Creates a new repository with a work tree at [path] and opens it.
  ///
  /// [path] is a directory: git creates it, missing parents included, and an
  /// existing empty directory is used as it stands. A directory that already
  /// holds files is refused with [GitOccupiedDirectoryException], its content
  /// untouched, before git runs; [allowOccupied] hands such a directory to
  /// git instead, which reinitializes an existing repository and keeps its
  /// data. [initialBranch] makes `HEAD` point at that branch; without it
  /// git's own default applies.
  ///
  /// A path is always treated as a path, even when it is spelled like an
  /// option.
  Future<GitWorkingRepository> init(
    String path, {
    String? initialBranch,
    bool allowOccupied = false,
  });

  /// Creates a new bare repository at [path] and opens it.
  ///
  /// The repository has no work tree: its files live directly in [path].
  /// [path] is a directory: git creates it, missing parents included, and an
  /// existing empty directory is used as it stands. A directory that already
  /// holds files is refused with [GitOccupiedDirectoryException], its content
  /// untouched, before git runs; [allowOccupied] hands such a directory to
  /// git instead, which reinitializes an existing repository and keeps its
  /// data. [initialBranch] makes `HEAD` point at that branch; without it
  /// git's own default applies.
  ///
  /// A path is always treated as a path, even when it is spelled like an
  /// option.
  Future<GitFileBareRepository> initBare(
    String path, {
    String? initialBranch,
    bool allowOccupied = false,
  });
}
