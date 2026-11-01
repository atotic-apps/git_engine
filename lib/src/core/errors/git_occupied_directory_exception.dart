import 'git_exception.dart';

/// A creation call refused the directory it was given because the directory
/// already holds files.
///
/// [path] is the directory whose content blocks the creation. The content is
/// untouched, and the refusal happens before git runs, so it carries no
/// cause — like `GitUnsupportedUrlException`.
/// {@category Errors}
class GitOccupiedDirectoryException extends GitException {
  /// Path of the directory whose content blocks the creation.
  final String path;

  /// Creates the failure for [path].
  GitOccupiedDirectoryException(this.path)
      : super('Cannot initialize into "$path": '
            'the directory already holds files');
}
