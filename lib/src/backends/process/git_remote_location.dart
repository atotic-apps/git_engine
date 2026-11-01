import 'package:git_engine/backend.dart';

/// The URI schemes the process backend accepts for remote locations.
///
/// Local paths and the scp-like `user@host:path` spelling carry no scheme
/// and are accepted beside these; see [classifyRemoteLocation].
const List<String> supportedRemoteSchemes = <String>[
  'file',
  'http',
  'https',
  'ssh',
];

/// The transport git uses to reach a remote location.
enum GitRemoteTransport {
  /// A path of the local disk, including drive-prefixed Windows paths.
  localPath,

  /// A `file://` URL.
  file,

  /// An `http://` URL.
  http,

  /// An `https://` URL.
  https,

  /// An `ssh://` URL or the scp-like `user@host:path` spelling.
  ssh,
}

/// Scheme, the `//` separator and the rest of a URL, e.g. `https` and
/// `//example.com/repo`.
final RegExp _schemePattern = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*)://(.*)$');

/// The transport of each scheme of [supportedRemoteSchemes].
const Map<String, GitRemoteTransport> _transportByScheme =
    <String, GitRemoteTransport>{
  'file': GitRemoteTransport.file,
  'http': GitRemoteTransport.http,
  'https': GitRemoteTransport.https,
  'ssh': GitRemoteTransport.ssh,
};

/// Validates [location] as a remote location and returns the transport git
/// uses for it.
///
/// Accepted forms:
/// - a path of the local disk (`/srv/repo.git`, `../repo`, `C:\repo`,
///   `C:repo`), including a Windows UNC share;
/// - a `file://`, `http://`, `https://` or `ssh://` URL, spelled in lower
///   case exactly as git recognizes it;
/// - the scp-like spelling `user@host:path`.
///
/// Everything else is refused by [checkRemoteLocation] without running git:
/// an empty value, a value spelled like an option (a leading `-`), a remote
/// helper invocation (`<transport>::`, including `ext::` and `fd::`), and a
/// scheme-shaped URL whose scheme is not one of [supportedRemoteSchemes]
/// spelled in lower case.
GitRemoteTransport classifyRemoteLocation(String location) {
  checkRemoteLocation(location, schemes: supportedRemoteSchemes);
  if (_isDrivePath(location)) {
    return GitRemoteTransport.localPath;
  }
  final RegExpMatch? scheme = _schemePattern.firstMatch(location);
  if (scheme != null) {
    return _transportByScheme[scheme.group(1)!]!;
  }
  return _isScpLike(location)
      ? GitRemoteTransport.ssh
      : GitRemoteTransport.localPath;
}

/// Whether [transport] can open an SSH connection, so the caller must keep
/// that connection from waiting on a prompt.
bool transportMayUseSsh(GitRemoteTransport transport) {
  return transport == GitRemoteTransport.ssh;
}

/// Whether [location] is the scp-like syntax: a colon before the first
/// slash, and no drive prefix.
bool _isScpLike(String location) {
  final int colon = location.indexOf(':');
  if (colon < 0) {
    return false;
  }
  final int slash = location.indexOf('/');
  return slash < 0 || colon < slash;
}

/// Whether [location] starts with a Windows drive prefix, e.g. `C:\repo` or
/// `C:repo`; such a value is always a path of the local disk.
bool _isDrivePath(String location) {
  return location.length >= 2 &&
      _isAsciiLetter(location.codeUnitAt(0)) &&
      location.codeUnitAt(1) == 0x3a; // ':'
}

bool _isAsciiLetter(int codeUnit) {
  return (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7a);
}
