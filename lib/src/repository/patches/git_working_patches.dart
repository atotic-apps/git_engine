import 'dart:typed_data';

import '../../models/git_apply_result.dart';
import '../../models/git_change_kind.dart';
import '../../models/git_oid.dart';
import 'git_indexed_patches.dart';

/// Differences between the index and the work tree of one repository, plus
/// applying a patch to the work tree.
///
/// It builds on [GitIndexedPatches], so tree-to-tree and tree-to-index
/// comparisons, as well as [GitIndexedPatches.applyToIndex], remain available,
/// and adds the comparisons that read working-tree files. No parameter selects
/// the work tree: being a working repository is what exposes these methods.
/// {@category Getting started}
abstract interface class GitWorkingPatches implements GitIndexedPatches {
  /// Paths that differ between the index and the work tree.
  ///
  /// {@macro git_patches_kinds}
  ///
  /// Untracked files do not appear.
  ///
  /// {@macro git_patches_sorted_paths}
  Future<List<String>> changedPathsAgainstWorkTree({
    Set<GitChangeKind>? kinds,
  });

  /// A unified text diff between the index and the work tree, decoded as
  /// UTF-8, for display.
  ///
  /// {@macro git_patches_literal_paths}
  ///
  /// {@macro git_patches_text_diff_shape}
  Future<String> textDiffAgainstWorkTree({
    List<String> paths = const <String>[],
  });

  /// A binary patch that reproduces the change between the index and the work
  /// tree, never decoded.
  ///
  /// {@macro git_patches_binary_diff_format}
  Future<Uint8List> binaryDiffAgainstWorkTree();

  /// Paths that differ between the tree [tree] and the work tree.
  ///
  /// This is the whole work-tree comparison, staged and unstaged changes
  /// included, not only the index-to-work-tree one.
  ///
  /// {@macro git_patches_kinds}
  ///
  /// {@macro git_patches_sorted_paths}
  Future<List<String>> changedPathsFromTree(
    GitOid tree, {
    Set<GitChangeKind>? kinds,
  });

  /// A unified text diff between the tree [tree] and the work tree, decoded as
  /// UTF-8, for display.
  ///
  /// {@macro git_patches_literal_paths}
  ///
  /// {@macro git_patches_text_diff_shape}
  Future<String> textDiffFromTree(
    GitOid tree, {
    List<String> paths = const <String>[],
  });

  /// A binary patch that reproduces the change between the tree [tree] and the
  /// work tree, never decoded.
  ///
  /// {@macro git_patches_binary_diff_format}
  Future<Uint8List> binaryDiffFromTree(GitOid tree);

  /// Applies [patch] to the work tree, leaving the index untouched.
  ///
  /// With [check], the patch is only verified and nothing changes. With
  /// [reverse], the patch is undone instead. With [threeWay], a patch that no
  /// longer applies cleanly falls back on a three-way merge and may leave
  /// conflict markers: that outcome is reported as [GitApplyConflicted],
  /// listing the affected files, while any other refusal is [GitApplyRefused],
  /// carrying a human-readable description of the refusal.
  Future<GitApplyResult> apply(
    List<int> patch, {
    bool check = false,
    bool reverse = false,
    bool threeWay = false,
  });
}
