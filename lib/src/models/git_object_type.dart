/// Kind of an object stored in a git repository.
/// {@category Getting started}
enum GitObjectType {
  /// File content.
  blob,

  /// Directory listing.
  tree,

  /// Snapshot of the repository with its parents and message.
  commit,

  /// Annotated tag.
  tag;

  /// Parses [name] as git spells it (`blob`, `tree`, `commit`, `tag`),
  /// returning null for any other name.
  static GitObjectType? tryParse(String name) {
    for (final GitObjectType type in GitObjectType.values) {
      if (type.name == name) {
        return type;
      }
    }
    return null;
  }
}
