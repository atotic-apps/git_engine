import 'git_repository.dart';

/// A bare [GitRepository], typed explicitly.
///
/// It adds no operation: it lets a signature require a bare repository, and
/// its contract carries no work-tree operation and no default index. Index
/// work on a bare repository always goes through an explicit index view.
/// {@category Getting started}
abstract interface class GitBareRepository implements GitRepository {}
