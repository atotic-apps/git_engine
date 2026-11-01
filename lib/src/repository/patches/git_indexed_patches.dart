import 'dart:typed_data';

import '../../models/git_change_kind.dart';
import '../../models/git_oid.dart';
import 'git_patches.dart';

/// Differences between a tree and the index of one repository, plus applying
/// a patch to the index alone.
///
/// It builds on [GitPatches], so the tree-to-tree comparisons remain
/// available, and adds comparisons against the active index view. No parameter
/// selects the index: being an indexed repository is what exposes these
/// methods. The index is the repository's own, or the explicit one a
/// repository view is bound to.
/// {@category Getting started}
abstract interface class GitIndexedPatches implements GitPatches {
  /// Paths that differ between [tree] and the index.
  ///
  /// {@macro git_patches_kinds}
  ///
  /// {@macro git_patches_sorted_paths}
  Future<List<String>> changedPathsAgainstIndex(
    GitOid tree, {
    Set<GitChangeKind>? kinds,
  });

  /// A unified text diff between [tree] and the index, decoded as UTF-8, for
  /// display.
  ///
  /// {@macro git_patches_literal_paths}
  ///
  /// {@macro git_patches_text_diff_shape}
  Future<String> textDiffAgainstIndex(
    GitOid tree, {
    List<String> paths = const <String>[],
  });

  /// A binary patch that reproduces the change between [tree] and the index,
  /// never decoded.
  ///
  /// {@macro git_patches_binary_diff_format}
  Future<Uint8List> binaryDiffAgainstIndex(GitOid tree);

  /// Applies [patch] to the index only, leaving the work tree untouched.
  ///
  /// With [check], the patch is only verified and nothing changes. With
  /// [reverse], the patch is undone instead. With [threeWay], a patch that no
  /// longer applies cleanly falls back on a three-way merge and may leave
  /// unmerged entries in the index: that outcome is reported as
  /// [GitApplyConflicted], listing the affected files, while any other refusal
  /// is [GitApplyRefused], carrying a human-readable description of the
  /// refusal.
  ///
  /// On a repository without a work tree, call it through a repository view
  /// bound to an explicit index file, so the patch never touches an implicit
  /// index.
  Future<GitApplyResult> applyToIndex(
    List<int> patch, {
    bool check = false,
    bool reverse = false,
    bool threeWay = false,
  });
}
