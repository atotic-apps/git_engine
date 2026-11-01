/// How a path changed between the two sides of a comparison.
///
/// A backend that cannot tell one kind apart from another never reports the
/// kinds it cannot distinguish.
/// {@category Getting started}
enum GitChangeKind {
  /// The path appeared.
  added,

  /// The path appeared as a copy of another path.
  copied,

  /// The path disappeared.
  deleted,

  /// The content of the path changed.
  modified,

  /// The path moved to another name.
  renamed,

  /// The kind of entry changed, for example between a file and a symbolic
  /// link.
  typeChanged,

  /// The path is left unmerged by a conflict.
  unmerged,
}
