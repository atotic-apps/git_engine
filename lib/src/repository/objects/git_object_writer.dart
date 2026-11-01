import '../../models/git_object_type.dart';
import '../../models/git_oid.dart';
import 'git_invalid_object_exception.dart';

/// Writes any object to a repository from its type and serialized content.
///
/// This is a capacity contract: implementations outside the library are
/// expected. Its single primitive covers blobs, trees, commits and annotated
/// tags; it validates the serialized format the way `git hash-object` does
/// without `--literally`, and stores nothing when the content is refused.
/// {@category Getting started}
/// {@category Compatibility}
abstract interface class GitObjectWriter {
  /// Writes [content] as an object of [type] and returns its object name.
  ///
  /// [content] is the serialized object itself — the bytes git stores after
  /// its `<type> <size>\0` header — so a blob is its raw bytes, a tree is its
  /// sequence of entries, and a commit or tag is its header block followed by
  /// its message. The content is hashed verbatim, including non-ASCII bytes.
  ///
  /// Throws [GitInvalidObjectException] when the content does not form a
  /// valid object of [type]; nothing is written in that case.
  Future<GitOid> writeObject(GitObjectType type, List<int> content);
}
