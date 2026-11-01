import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

/// Joins [base] and [relative] with the platform separator.
String joinPath(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

/// Writes [content] to [relativePath] under [root], creating parent
/// directories as needed.
///
/// A [String] is encoded as UTF-8; a [List] of bytes is written verbatim.
File writeRepoFile(String root, String relativePath, Object content) {
  final File file = File(joinPath(root, relativePath));
  file.parent.createSync(recursive: true);
  final List<int> bytes =
      content is String ? utf8.encode(content) : content as List<int>;
  file.writeAsBytesSync(bytes);
  return file;
}

/// Writes [files] into [repository], stages every change and commits them as
/// [message]; returns the new commit's object name.
Future<GitOid> commitFiles(
  GitWorkingRepository repository,
  Map<String, Object> files,
  String message,
) async {
  for (final MapEntry<String, Object> entry in files.entries) {
    writeRepoFile(repository.path, entry.key, entry.value);
  }
  await repository.worktree.addAll();
  return repository.worktree.commit(message, allowEmpty: true);
}

/// Content of [path] inside [repository], decoded as UTF-8.
String readRepoText(GitWorkingRepository repository, String path) {
  return File(joinPath(repository.path, path)).readAsStringSync();
}

/// Raw bytes of [path] inside [repository].
Uint8List readRepoBytes(GitWorkingRepository repository, String path) {
  return File(joinPath(repository.path, path)).readAsBytesSync();
}

/// UTF-8 bytes of [text], for comparing file content with written strings.
Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// Leaves [repository] in a conflicted merge state on `conflict.txt`.
Future<void> createMergeConflict(GitWorkingRepository repository) async {
  await commitFiles(
    repository,
    <String, Object>{'conflict.txt': 'base\n'},
    'base',
  );
  await repository.worktree.checkoutNewBranch('side');
  await commitFiles(
    repository,
    <String, Object>{'conflict.txt': 'side\n'},
    'side',
  );
  await repository.worktree.checkout('main');
  await commitFiles(
    repository,
    <String, Object>{'conflict.txt': 'main\n'},
    'main',
  );
  final GitMergeResult result = await repository.merge.merge('side');
  if (result is! GitMergeConflicts) {
    fail('expected a conflicted merge, got $result');
  }
}
