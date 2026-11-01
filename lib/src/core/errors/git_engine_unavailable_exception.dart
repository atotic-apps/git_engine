import 'git_exception.dart';

/// A git backend cannot be used on this host.
///
/// The engine cannot start the backend at all: the process backend raises it
/// when its executable cannot be found, a native backend raises it when its
/// native library cannot be loaded. The subtype tells the backend-specific
/// reason. Code portable between backends catches this type instead of the
/// exception types of one backend.
///
/// The host reports the reason it could not start the backend as an arbitrary
/// object, not necessarily an engine failure, so this type does not override
/// [cause]: the base getter stays null and the raw start error is available as
/// [spawnError].
/// {@category Errors}
class GitEngineUnavailableException extends GitException {
  /// Underlying error that kept the backend from starting, when available.
  final Object? spawnError;

  /// Creates the failure described by [message], carrying the underlying
  /// error as [spawnError] when the host reported one.
  GitEngineUnavailableException(super.message, {Object? cause})
      : spawnError = cause;
}
