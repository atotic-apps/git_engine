import 'dart:typed_data';

import '../../models/git_change_kind.dart';
import '../../models/git_oid.dart';

export '../../models/git_apply_result.dart'
    show GitApplyApplied, GitApplyConflicted, GitApplyRefused, GitApplyResult;

/// Differences between two trees of one repository: changed paths, unified
/// text diffs for display, and portable binary diffs.
///
/// This is the first of three patch facades, one per repository level:
/// [GitIndexedPatches] compares a tree with the index and applies to the
/// index, while [GitWorkingPatches] compares with the work tree and applies
/// there. No method here selects a level through a parameter.
///
/// Every comparison takes [GitOid]s, never revision expressions: resolve an
/// expression first, then hand the object names here. Every command runs
/// inside the owning repository's context, so a derived view (an alternate
/// index file, extra environment variables) applies here too. A patch produced
/// by [binaryDiff] can be handed back to an apply operation byte for byte.
///
/// ```dart
/// final List<String> betweenTrees =
///     await repo.patches.changedPaths(base, head);
/// final String shown = await repo.patches.textDiff(base, head);
/// final List<int> raw = await indexed.patches.binaryDiff(base, head);
/// final GitApplyResult applied =
///     await indexed.patches.applyToIndex(raw, threeWay: true);
/// ```
/// {@category Getting started}
abstract interface class GitPatches {
  /// Paths that differ between the trees [from] and [to].
  ///
  /// {@template git_patches_kinds}
  /// [kinds] keeps only changes of those kinds; null keeps every change and an
  /// empty set is refused with an [ArgumentError].
  /// {@endtemplate}
  ///
  /// {@template git_patches_sorted_paths}
  /// Paths are relative to the repository root, without duplicates, sorted by
  /// the UTF-8 bytes of the full path.
  /// {@endtemplate}
  Future<List<String>> changedPaths(
    GitOid from,
    GitOid to, {
    Set<GitChangeKind>? kinds,
  });

  /// A unified text diff between the trees [from] and [to], decoded as UTF-8,
  /// for display.
  ///
  /// {@template git_patches_literal_paths}
  /// [paths] holds literal paths relative to the repository root: a directory
  /// path covers everything below it and `.` covers the whole repository. It
  /// accepts no glob and no magic `:(...)` syntax.
  /// {@endtemplate}
  ///
  /// {@template git_patches_text_diff_shape}
  /// The exact shape of the returned diff — headers, context lines, hunk
  /// boundaries — is not guaranteed and may differ between backends.
  /// {@endtemplate}
  ///
  /// Use [binaryDiff] when the diff must be applied.
  Future<String> textDiff(
    GitOid from,
    GitOid to, {
    List<String> paths = const <String>[],
  });

  /// A binary patch that reproduces the change between the trees [from] and
  /// [to], never decoded.
  ///
  /// {@template git_patches_binary_diff_format}
  /// Applying it with an apply operation reproduces binary files and line
  /// endings byte for byte. The bytes are a portable patch, not the output of
  /// any specific tool.
  /// {@endtemplate}
  Future<Uint8List> binaryDiff(GitOid from, GitOid to);
}
