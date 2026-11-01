import '../redact_url_userinfo.dart';

/// Maximum number of failures a diagnostic follows through their causes.
///
/// The bound keeps a diagnostic finite even when a failure chain is longer
/// than expected or loops back on itself.
const int maxDiagnosticChainLength = 16;

/// Base class of the git engine's domain refusals and command failures.
///
/// Catch this type to handle that error hierarchy; catch a subclass to handle
/// one specific failure. The base class itself is also used for the rare
/// failures that happen before a command can run, e.g. a working directory
/// that does not exist, and for the refusals no caller is expected to treat.
///
/// Every operation of the facades names, in its documentation, the exceptions
/// it throws for the refusals a caller can treat. Other command failures use
/// [GitException], with no further promise about their concrete type.
/// Argument and value validation may throw standard Dart errors or
/// exceptions, and underlying platform failures may propagate unwrapped.
/// Catching `GitException` does not catch those failures.
///
/// Domain exceptions derive from [GitException] through backend-independent
/// types, so a caller can catch a domain refusal without catching every
/// failure of one backend. They carry the underlying failure in [cause] when
/// there is one — always null on a backend that runs no git command.
///
/// [diagnostic] gives the complete technical text of a failure, with every
/// URL userinfo masked. Other sensitive data can remain in arguments and
/// output; apply any additional redaction needed before logging it. Code
/// never reads it to decide a behaviour: it catches the exception type instead.
///
/// A timeout (`GitTimeoutException`) and an engine older than the minimum
/// (`GitVersionException`) are domain refusals: every backend can report them,
/// and code portable between backends catches them. The type that names how
/// the process backend starts git is not portable; code portable between
/// backends catches its portable supertype instead.
/// {@category Errors}
class GitException implements Exception {
  /// Human-readable description of what went wrong.
  final String message;

  /// Creates a failure described by [message].
  GitException(this.message);

  /// The engine failure that produced this one, when there is one.
  ///
  /// The base failure has no cause; a subclass carries the underlying failure
  /// by overriding this getter, usually with a final field.
  GitException? get cause => null;

  /// Complete technical text of the failure.
  ///
  /// It starts with [message] and, when [cause] is not null, appends the
  /// cause's own diagnostic after a blank line, following at most
  /// [maxDiagnosticChainLength] failures so an abnormal chain never loops.
  /// URL userinfo is masked as `***` (`https://user:token@host/repo` reads as
  /// `https://***@host/repo`); nothing else is redacted, so scrub query
  /// parameters, arguments and output before logging.
  ///
  /// The text has no promised format and no promised language: it may change
  /// between versions and is meant for a human reader. Never use it to decide
  /// a behaviour; catch the exception type instead. The diagnostic formatter
  /// does not truncate command output, so a logger applies its own size limit.
  String get diagnostic => diagnosticAtDepth(0);

  /// Builds [diagnostic] starting [depth] failures into the cause chain.
  ///
  /// A subclass that adds its own detail overrides this method, masks the
  /// result, and overrides [diagnostic] to delegate to it, so its detail stays
  /// in the text when another failure follows it as a cause.
  String diagnosticAtDepth(int depth) {
    final StringBuffer buffer = StringBuffer(message);
    final GitException? next = cause;
    if (next != null && depth + 1 < maxDiagnosticChainLength) {
      buffer
        ..write('\n\n')
        ..write(next.diagnosticAtDepth(depth + 1));
    }
    return redactUrlUserinfo(buffer.toString());
  }

  @override
  String toString() => '$runtimeType: $message';
}
