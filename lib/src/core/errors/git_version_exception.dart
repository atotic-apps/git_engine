import 'git_exception.dart';

/// The engine is older than the version required by the caller.
/// {@category Errors}
class GitVersionException extends GitException {
  /// Minimum version that was required, as given by the caller.
  final String requiredVersion;

  /// Version string reported by the engine.
  final String actualVersion;

  /// Creates the failure raised when [actualVersion] — the version string of
  /// the engine — is older than [requiredVersion].
  GitVersionException({
    required this.requiredVersion,
    required this.actualVersion,
  }) : super(
          'git $actualVersion is older than the required version '
          '$requiredVersion',
        );
}
