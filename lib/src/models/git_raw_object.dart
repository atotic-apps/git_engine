import 'dart:typed_data';

import 'git_object_type.dart';

/// A git object read as stored: its type and its serialized content.
///
/// [content] is the object payload without the `<type> <size>\0` header git
/// prepends when it stores the object. For a blob it is the file content
/// itself; for a tree, a commit or a tag it is the object's own format,
/// left uninterpreted.
/// {@category Getting started}
class GitRawObject {
  /// Kind of the object.
  final GitObjectType type;

  /// Serialized content of the object.
  final Uint8List content;

  /// Creates a raw object of [type] holding [content].
  GitRawObject({required this.type, required Uint8List content})
      : content = Uint8List.fromList(content);

  @override
  bool operator ==(Object other) =>
      other is GitRawObject && other.type == type && _bytesEqual(other.content);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(content));

  @override
  String toString() => '${type.name} (${content.length} bytes)';

  bool _bytesEqual(Uint8List other) {
    if (other.length != content.length) {
      return false;
    }
    for (int index = 0; index < content.length; index++) {
      if (other[index] != content[index]) {
        return false;
      }
    }
    return true;
  }
}
