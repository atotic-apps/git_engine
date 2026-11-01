import 'package:git_engine/git_engine.dart';

import 'git_command_exception.dart';

/// Environment bounding clone, fetch and push to the transports the client
/// accepts.
///
/// Git reads `GIT_ALLOW_PROTOCOL` in preference to every `protocol.*`
/// configuration, so no configuration file — global, system or of the
/// repository — can widen the set: only local paths and the `file`, `http`,
/// `https` and `ssh` transports are reachable.
const Map<String, String> transportEnvironment = <String, String>{
  'GIT_ALLOW_PROTOCOL': 'file:http:https:ssh',
};

/// Arguments of the command reading one configuration value, used to learn
/// whether the user chose their own SSH command in a configuration file.
const List<String> sshCommandProbe = <String>[
  'config',
  '--get',
  'core.sshCommand',
];

/// The connection failures git reports on its standard error, classified
/// into the typed failures of the client layer.
class GitRemoteFailure {
  /// The client-layer failure [error] reports, or null when git's stderr
  /// names none of the classified connection failures.
  static GitException? classify(GitCommandException error) {
    final String stderr = error.stderr;
    if (isAuthenticationFailure(stderr)) {
      return GitAuthenticationException(cause: error);
    }
    if (isRemoteRepositoryMissing(stderr)) {
      return GitRemoteRepositoryNotFoundException(cause: error);
    }
    if (isRemoteUnreachable(stderr)) {
      return GitRemoteUnreachableException(cause: error);
    }
    return null;
  }

  /// Whether git reported that the remote refused the offered credentials or
  /// demanded credentials the environment did not provide.
  static bool isAuthenticationFailure(String stderr) {
    final String text = stderr.toLowerCase();
    return _contains(text, const <String>[
      'authentication failed',
      'could not read username',
      'could not read password',
      'permission denied',
      'terminal prompts disabled',
      'returned error: 401',
      'returned error: 403',
    ]);
  }

  /// Whether git reported that no repository exists at the remote location.
  static bool isRemoteRepositoryMissing(String stderr) {
    final String text = stderr.toLowerCase();
    return _contains(text, const <String>[
          'repository not found',
          'does not appear to be a git repository',
          'returned error: 404',
        ]) ||
        _missingRepositoryLine.hasMatch(text);
  }

  /// The whole line git prints when a local clone source does not exist; a
  /// longer line, such as one naming a missing index entry, does not match.
  static final RegExp _missingRepositoryLine = RegExp(
    r"^fatal: repository '[^\r\n]+' does not exist\r?$",
    multiLine: true,
  );

  /// Whether git reported that the remote host could not be reached: an
  /// unknown host, a refused or timed out connection, or an SSH host key
  /// that could not be verified.
  static bool isRemoteUnreachable(String stderr) {
    final String text = stderr.toLowerCase();
    return _contains(text, const <String>[
      'could not resolve host',
      'could not resolve hostname',
      'connection refused',
      'connection timed out',
      'timed out',
      'network is unreachable',
      'no route to host',
      'host key verification failed',
    ]);
  }

  /// Whether [text] contains any of [markers].
  static bool _contains(String text, List<String> markers) {
    return markers.any(text.contains);
  }
}
