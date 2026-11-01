import 'git_exception.dart';

/// An operation the package implements but the backend cannot run.
///
/// The method exists and works on a capable backend; only this one lacks the
/// command or the option it needs. It is distinct from a backend's own
/// explicit version gate, which answers the caller's request for a minimum
/// version instead of answering one operation.
///
/// A backend incapable of running an operation raises it; the process backend
/// raises it when the installed git is too old, e.g. for `mergeTree`.
/// {@category Errors}
class GitFeatureUnavailableException extends GitException {
  /// Operation that the backend cannot run, e.g. `mergeTree`.
  final String operation;

  /// Lowest capability the operation needs; for the process backend, the
  /// lowest git version that supports [operation].
  final String requiredVersion;

  /// Fact about the installed backend: for the process backend, the version
  /// string reported by `git --version`.
  final String installedVersion;

  /// Alias of [installedVersion], spelled as the traditional version checks
  /// name it.
  String get actualVersion => installedVersion;

  /// Creates the refusal for [operation], which needs [requiredVersion] but
  /// runs on [installedVersion].
  GitFeatureUnavailableException({
    required this.operation,
    required this.requiredVersion,
    required this.installedVersion,
  }) : super(
          '$operation requires git $requiredVersion or newer; '
          'the installed git reports $installedVersion',
        );
}
