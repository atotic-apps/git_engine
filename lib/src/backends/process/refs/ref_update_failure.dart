import '../git_command_exception.dart';

/// Whether [error] is git refusing a ref update because the reference held a
/// value other than the expected one.
///
/// Git words the refusal as `is at <oid> but expected <oid>` (some versions:
/// `unexpected object ID <oid>`); every other failure — an unknown ref, a
/// locked ref — is a different problem.
bool isExpectedValueMismatch(GitCommandException error) {
  final String stderr = error.stderr.toLowerCase();
  return stderr.contains('but expected') ||
      stderr.contains('unexpected object');
}
