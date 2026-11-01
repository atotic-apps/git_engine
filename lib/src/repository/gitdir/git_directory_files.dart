import '../../models/git_directory_drift.dart';
import '../../models/git_directory_snapshot.dart';

/// Plain files of the git directory of one repository: capturing them,
/// reporting what drifted since a capture, and writing a capture back.
///
/// A capture fingerprints the clone as it stands — its configuration, its
/// hooks, every administrative file of the git directory. Comparing it later
/// reports file by file what was modified, added or deleted; restoring writes
/// the captured files that no longer match verbatim back into place. Files
/// that are not part of the capture are never touched: restoring adds and
/// repairs, it never removes.
///
/// Paths are git-directory relative and spelled with forward slashes, so a
/// capture travels between platforms. A path whose directory or file is a
/// symbolic link, or a Windows junction, that leads outside the git directory
/// is refused by the operations that read or write it.
///
/// A capture contains the configuration and the hooks of the git directory.
/// Restoring one therefore lets the snapshot's source choose code git will
/// execute: restore only a snapshot from a trusted source, for example one
/// this application captured itself.
///
/// ```dart
/// final GitDirectorySnapshot capture = await repo.gitDirectoryFiles.capture();
/// final GitDirectoryDrift drift = await repo.gitDirectoryFiles.drift(capture);
/// print('${drift.modified} ${drift.added} ${drift.deleted}');
/// final List<String> restored =
///     await repo.gitDirectoryFiles.restore(capture);
/// ```
/// {@category Getting started}
abstract interface class GitDirectoryFiles {
  /// Captures every regular file of the repository's git directory, nested
  /// directories included, keyed by git-directory relative path.
  ///
  /// Symbolic links and Windows junctions are not followed, so a capture
  /// never holds the content of a file outside the git directory.
  Future<GitDirectorySnapshot> capture();

  /// Compares [snapshot] with the git directory as it stands now.
  ///
  /// A captured file whose content changed is reported in
  /// [GitDirectoryDrift.modified], a file created since the capture in
  /// [GitDirectoryDrift.added], and a captured file that is gone in
  /// [GitDirectoryDrift.deleted].
  ///
  /// Every key is checked again, and a key whose path would leave the git
  /// directory once symbolic links and Windows junctions are resolved is
  /// refused with a `GitException` naming it.
  Future<GitDirectoryDrift> drift(GitDirectorySnapshot snapshot);

  /// Writes every file of [snapshot] whose content no longer matches back
  /// into the git directory, creating missing parent directories, and
  /// returns the git-directory relative paths written, sorted. A file that
  /// already holds the captured content is left untouched, so restoring is
  /// safe to repeat and never rewrites a file git keeps read-only.
  ///
  /// Files created in the git directory since the capture are kept; only the
  /// captured paths are written.
  ///
  /// Every key is checked before anything is written, and a key whose path
  /// would leave the git directory once symbolic links and Windows junctions
  /// are resolved is refused with a `GitException` naming it. One refused key
  /// aborts the whole restore: no file of the snapshot is written, including
  /// the keys that were accepted.
  ///
  /// A capture contains the configuration and the hooks of the git directory,
  /// so restoring one lets the snapshot's source choose code git will
  /// execute. Restore only a snapshot from a trusted source, for example one
  /// this application captured itself.
  Future<List<String>> restore(GitDirectorySnapshot snapshot);
}
