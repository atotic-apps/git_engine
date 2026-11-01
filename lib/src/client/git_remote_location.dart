import 'git_unsupported_url_exception.dart';

/// Scheme, the `//` separator and the rest of a URL, e.g. `https` and
/// `//example.com/repo`.
final RegExp _schemePattern = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*)://(.*)$');

/// A remote helper invocation, e.g. `ext::git upload-pack /repo`.
final RegExp _remoteHelperPattern = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*)::');

/// Refuses [location] unless it is a remote location the engine accepts.
///
/// [schemes] are the URI schemes the calling engine accepts, spelled in lower
/// case exactly as git recognizes them. The other accepted forms carry no
/// scheme: a path of the local disk (`/srv/repo.git`, `../repo`, `C:\repo`,
/// `C:repo`), including a Windows UNC share, and the scp-like
/// `user@host:path` spelling.
///
/// Everything else raises [GitUnsupportedUrlException] without running git:
/// an empty value, a value spelled like an option (a leading `-`), a remote
/// helper invocation (`<transport>::`, including `ext::` and `fd::`), and a
/// scheme-shaped URL whose scheme is not one of [schemes].
///
/// A Windows drive prefix wins over the scheme reading, so `C://repo` is a
/// local path rather than a URL served over a scheme named `C`.
void checkRemoteLocation(String location, {required List<String> schemes}) {
  if (location.isEmpty) {
    throw GitUnsupportedUrlException(location, reason: 'it is empty');
  }
  if (location.startsWith('-')) {
    throw GitUnsupportedUrlException(
      location,
      reason: 'it is spelled like an option',
    );
  }
  final RegExpMatch? helper = _remoteHelperPattern.firstMatch(location);
  if (helper != null) {
    throw GitUnsupportedUrlException(
      location,
      reason: 'the remote helper "${helper.group(1)}::" is not supported',
    );
  }
  if (_isDrivePath(location)) {
    return;
  }
  final RegExpMatch? scheme = _schemePattern.firstMatch(location);
  if (scheme == null) {
    return;
  }
  final String name = scheme.group(1)!;
  if (!schemes.contains(name)) {
    throw GitUnsupportedUrlException(
      location,
      reason: '"$name" is not one of the supported schemes: '
          '${schemes.join(", ")}',
    );
  }
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
