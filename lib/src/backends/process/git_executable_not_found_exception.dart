import 'package:git_engine/git_engine.dart';

/// The git executable could not be started because it was not found.
///
/// The platform reports the spawn failure as an arbitrary object, not as an
/// engine failure, so this type does not override [cause]: the base getter
/// stays null and the raw spawn error is available as [spawnError].
/// {@category Errors}
class GitExecutableNotFoundException extends GitEngineUnavailableException {
  /// Executable path or name that could not be resolved.
  final String executable;

  /// Creates the failure for [executable], carrying the spawn error [cause]
  /// when the platform reported one.
  GitExecutableNotFoundException(this.executable, {Object? cause})
      : super(
          'git executable not found: "$executable"'
          '${cause == null ? '' : ' ($cause)'}',
          cause: cause,
        );
}
