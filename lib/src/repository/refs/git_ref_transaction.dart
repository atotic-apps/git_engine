import '../../models/git_oid.dart';
import 'git_invalid_ref_name_exception.dart';

/// A set of reference updates applied together, all or nothing.
///
/// Staging methods only record what to change; nothing reaches the repository
/// before [commit]. A transaction is meant to be used once: staging a change
/// or calling [commit] again after [commit] has been called throws a
/// `StateError`.
///
/// The contract is a capability interface, implementable outside the library.
///
/// Refusals are reported as `GitException`; a reference that no longer holds
/// the expected value raises `GitRefMismatchException`. A failed transaction
/// applies none of its staged updates.
///
/// The reference names the staging methods take are full reference names,
/// rejected at the call itself — not at [commit] — when they cannot name a
/// reference: a `refs/...` name under the rules documented on
/// [GitInvalidRefNameException], or one of the pseudo-references git
/// maintains at the top level (`HEAD`, `FETCH_HEAD`, `MERGE_HEAD`,
/// `ORIG_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`); any other one-level name
/// is refused. A violating name raises [GitInvalidRefNameException] before
/// any git call.
/// {@category Getting started}
/// {@category Compatibility}
abstract interface class GitRefTransaction {
  /// Sets [ref] to [newOid].
  ///
  /// Without [expectedOld] the update is unconditional and creates the
  /// reference when it does not exist. With [expectedOld] the reference must
  /// currently point at it; otherwise [commit] fails and no update in the
  /// transaction is applied.
  void update(String ref, GitOid newOid, {GitOid? expectedOld});

  /// Creates [ref] pointing at [oid].
  ///
  /// Unlike [update], creation fails when the reference already exists, and
  /// that failure applies none of the transaction's updates.
  void create(String ref, GitOid oid);

  /// Deletes [ref].
  ///
  /// Without [expectedOld] the deletion is unconditional. With [expectedOld]
  /// the reference must currently point at it; otherwise [commit] fails and no
  /// update in the transaction is applied.
  void delete(String ref, {GitOid? expectedOld});

  /// Applies every staged change atomically.
  ///
  /// Either all updates are applied or none is. When a reference does not hold
  /// the expected value, the whole transaction is refused with a
  /// `GitRefMismatchException`.
  Future<void> commit();
}
