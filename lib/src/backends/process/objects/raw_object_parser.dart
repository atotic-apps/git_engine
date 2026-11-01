import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';

/// Parses the serialized content of the commit object named [oid].
///
/// The content is read as git stores it: header lines (`tree`, `parent`,
/// `author`, `committer`, and uninterpreted extras such as `gpgsig`), a blank
/// line, then the message. The trailing newline git appends to the message is
/// removed, matching the message the caller handed to `commit-tree`.
///
/// Throws a [FormatException] when a required header is missing or malformed.
GitCommit parseCommitObject(GitOid oid, Uint8List content) {
  final _ObjectText text = _ObjectText.decode(content);
  GitOid? tree;
  final List<GitOid> parents = <GitOid>[];
  _Signature? author;
  _Signature? committer;
  for (final String line in text.headerLines) {
    if (line.startsWith('tree ')) {
      tree = _parseOid(line.substring(5), oid, 'tree');
    } else if (line.startsWith('parent ')) {
      parents.add(_parseOid(line.substring(7), oid, 'parent'));
    } else if (line.startsWith('author ')) {
      author = _parseSignature('author', line.substring(7), oid);
    } else if (line.startsWith('committer ')) {
      committer = _parseSignature('committer', line.substring(10), oid);
    }
  }
  if (tree == null) {
    throw _malformed(oid, 'commit without a tree');
  }
  if (author == null) {
    throw _malformed(oid, 'commit without an author');
  }
  if (committer == null) {
    throw _malformed(oid, 'commit without a committer');
  }
  return GitCommit(
    tree: tree,
    parents: parents,
    author: author.identity,
    authorDate: author.date,
    committer: committer.identity,
    committerDate: committer.date,
    message: text.message,
  );
}

/// Parses the serialized content of the annotated tag object named [oid].
///
/// The content is read as git stores it: the `object`, `type`, `tag` and
/// `tagger` headers, a blank line, then the message. The trailing newline git
/// appends to the message is removed.
///
/// Throws a [FormatException] when a required header is missing or malformed.
GitTag parseTagObject(GitOid oid, Uint8List content) {
  final _ObjectText text = _ObjectText.decode(content);
  GitOid? target;
  GitObjectType? targetType;
  String? name;
  _Signature? tagger;
  for (final String line in text.headerLines) {
    if (line.startsWith('object ')) {
      target = _parseOid(line.substring(7), oid, 'tag target');
    } else if (line.startsWith('type ')) {
      targetType = GitObjectType.tryParse(line.substring(5).trim());
      if (targetType == null) {
        throw _malformed(oid, 'tag with an unknown target type');
      }
    } else if (line.startsWith('tag ')) {
      name = line.substring(4);
    } else if (line.startsWith('tagger ')) {
      tagger = _parseSignature('tagger', line.substring(7), oid);
    }
  }
  if (target == null) {
    throw _malformed(oid, 'tag without a target');
  }
  if (targetType == null) {
    throw _malformed(oid, 'tag without a target type');
  }
  if (name == null || name.isEmpty) {
    throw _malformed(oid, 'tag without a name');
  }
  if (tagger == null) {
    throw _malformed(oid, 'tag without a tagger');
  }
  return GitTag(
    target: target,
    targetType: targetType,
    name: name,
    tagger: tagger.identity,
    taggerDate: tagger.date,
    message: text.message,
  );
}

/// Header lines and message of a serialized commit or tag.
class _ObjectText {
  const _ObjectText(this.headerLines, this.message);

  final List<String> headerLines;
  final String message;

  static _ObjectText decode(Uint8List content) {
    final String decoded = utf8.decode(content, allowMalformed: true);
    final int separator = decoded.indexOf('\n\n');
    if (separator < 0) {
      return _ObjectText(decoded.split('\n'), '');
    }
    final String message =
        decoded.substring(separator + 2).replaceAll(RegExp(r'[\r\n]+$'), '');
    return _ObjectText(decoded.substring(0, separator).split('\n'), message);
  }
}

/// Identity and instant of one `author`, `committer` or `tagger` header.
class _Signature {
  const _Signature(this.identity, this.date);

  final GitIdentity identity;
  final DateTime date;
}

/// Parses `<name> <email> <seconds> <offset>` into an identity and a UTC
/// instant. The offset is part of git's format but a [DateTime] cannot retain
/// it, so only the instant is kept.
_Signature _parseSignature(String header, String value, GitOid oid) {
  final int emailEnd = value.lastIndexOf('> ');
  final int emailStart = emailEnd < 0 ? -1 : value.lastIndexOf('<', emailEnd);
  if (emailStart < 0) {
    throw _malformed(oid, '$header line without an identity');
  }
  final String name = value.substring(0, emailStart).trimRight();
  final String email = value.substring(emailStart + 1, emailEnd);
  final List<String> fields =
      value.substring(emailEnd + 2).trim().split(RegExp(r'\s+'));
  if (fields.length < 2) {
    throw _malformed(oid, '$header line without a date');
  }
  final int? seconds = int.tryParse(fields.first);
  if (seconds == null) {
    throw _malformed(oid, '$header line with a malformed date');
  }
  if (name.isEmpty || email.isEmpty) {
    throw _malformed(oid, '$header line with an empty identity');
  }
  return _Signature(
    GitIdentity(name: name, email: email),
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
  );
}

/// Parses [value] as an object name, naming [what] in the error.
GitOid _parseOid(String value, GitOid oid, String what) {
  final GitOid? parsed = GitOid.tryParse(value.trim());
  if (parsed == null) {
    throw _malformed(oid, '$what header with a malformed object name');
  }
  return parsed;
}

/// A format failure in the object named [oid].
FormatException _malformed(GitOid oid, String reason) {
  return FormatException('Malformed object ${oid.value}: $reason');
}
