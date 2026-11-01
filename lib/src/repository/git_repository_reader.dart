import 'history/git_history_reader.dart';
import 'objects/git_object_reader.dart';
import 'refs/git_ref_reader.dart';

/// Read-only view of one repository's stored data.
///
/// It exposes exactly the capabilities a server-side reader needs: object
/// reads addressed by object name, reference reads addressed by reference
/// name, and the commit graph. It carries no configuration, no remote, no work
/// tree, no revision expression and no way to write anything.
///
/// This is a capability contract: a backend implements it only when it can
/// honour every operation of all three accessors.
/// {@category Getting started}
/// {@category Compatibility}
abstract interface class GitRepositoryReader {
  /// Objects of this repository, addressed by object name.
  GitObjectReader get objects;

  /// References of this repository, addressed by reference name.
  GitRefReader get refs;

  /// Commit-graph history of this repository.
  GitHistoryReader get history;
}
