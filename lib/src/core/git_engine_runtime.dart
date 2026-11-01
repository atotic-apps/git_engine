/// Facts about the version of an engine, independent of any backend.
///
/// A backend may have no notion of a version, for example an in-memory or a
/// protocol-level engine. Such a backend says so explicitly instead of
/// exposing this contract: it does not report a made-up version and does not
/// pretend to check a minimum.
/// {@category Getting started}
abstract interface class GitEngineRuntime {
  /// Version text of the engine, with no promise about its format.
  ///
  /// The text is meant for display and diagnostics; code never parses it to
  /// decide a behavior.
  Future<String> engineVersion();

  /// Ensures the engine is at least [minimumVersion], written as
  /// `major[.minor[.patch]]`.
  ///
  /// Throws `GitVersionException` when the engine is older than
  /// [minimumVersion], `FormatException` when the version cannot be read, and
  /// `ArgumentError` when [minimumVersion] itself is malformed.
  Future<void> ensureMinimumVersion(String minimumVersion);
}
