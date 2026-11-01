import 'git_repository.dart';
import 'gitdir/git_directory_files.dart';

/// A [GitRepository] stored on disk.
///
/// Everything that assumes a filesystem lives here: the repository path, its
/// git directory, and the plain files of the git directory itself. A
/// repository held in memory or in an abstract store is never a file
/// repository.
/// {@category Getting started}
abstract interface class GitFileRepository implements GitRepository {
  /// Absolute path of the repository directory commands run in.
  String get path;

  /// Absolute path of the repository's git directory (its `.git` for a
  /// repository with a work tree, its own directory for a bare one), as git
  /// reports it.
  Future<String> gitDir();

  /// The plain files of the git directory: capture, drift report and
  /// restore, all through this repository.
  GitDirectoryFiles get gitDirectoryFiles;
}
