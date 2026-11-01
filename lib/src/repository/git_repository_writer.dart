import 'git_repository_reader.dart';
import 'objects/git_object_store.dart';
import 'refs/git_ref_transaction.dart';

/// Read and write view of the stored data of one repository.
///
/// On top of [GitRepositoryReader] it can write objects and apply reference
/// updates atomically through a [GitRefTransaction]. That is the whole write
/// surface server-side code needs: no configuration, no remote, no work tree,
/// no revision expression and no single-reference shortcut that would bypass a
/// transaction.
///
/// This is a capability contract: a backend implements it only when it can
/// honour every operation.
/// {@category Getting started}
/// {@category Compatibility}
abstract interface class GitRepositoryWriter implements GitRepositoryReader {
  /// Objects of this repository: reads and writes, addressed by object name.
  @override
  GitObjectStore get objects;

  /// A transaction that updates several references at once, all or nothing.
  GitRefTransaction beginRefTransaction();
}
