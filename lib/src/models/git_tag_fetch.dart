/// Which tags a fetch brings into the repository.
/// {@category Getting started}
enum GitTagFetch {
  /// The tags that designate commits the fetch retrieves anyway: a tag
  /// arrives when its commit is downloaded, and no other tag does. This is
  /// the default.
  follow,

  /// Every tag the remote holds, whatever commits the fetch retrieves.
  all,

  /// No tag at all, not even a tag designating a retrieved commit.
  none,
}
