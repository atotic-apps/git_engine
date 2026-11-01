/// Format of an archive streamed by `GitObjects.archive`.
///
/// The enum name is the format name the archive is written with (`tar`,
/// `zip`).
/// {@category Getting started}
enum GitArchiveFormat {
  /// Uncompressed POSIX tar archive.
  tar,

  /// Zip archive.
  zip,
}
