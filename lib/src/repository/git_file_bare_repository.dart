import 'git_bare_repository.dart';
import 'git_file_repository.dart';

/// A bare [GitBareRepository] stored on disk.
///
/// It combines the two durable capabilities: no work tree, and the disk
/// access of [GitFileRepository]. This is the type of a repository served
/// from disk.
/// {@category Getting started}
abstract interface class GitFileBareRepository
    implements GitBareRepository, GitFileRepository {}
