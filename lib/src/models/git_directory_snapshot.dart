import 'dart:typed_data';

/// Why [path] is not a relative path spelled with `/`, or null when it is one.
///
/// A valid path is non-empty, spells its segments separated by `/`, and holds
/// no empty, `.` or `..` segment, no backslash, no NUL character and no
/// absolute prefix: a leading `/` or `\`, a drive (`C:`) or a UNC share
/// (`\\server`).
///
/// With [windows], the naming rules of Windows apply to every segment as
/// well: no colon, no trailing dot or space, and no reserved device name
/// (`CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `LPT1` to `LPT9`, with or
/// without an extension, in any case).
String? relativePathError(String path, {bool windows = false}) {
  if (path.isEmpty) {
    return 'is empty';
  }
  if (path.startsWith('/') || path.startsWith('\\')) {
    return 'is absolute';
  }
  if (RegExp(r'^[A-Za-z]:').hasMatch(path)) {
    return 'is absolute';
  }
  if (path.contains('\\')) {
    return 'contains a backslash';
  }
  if (path.contains('\u0000')) {
    return 'contains a NUL character';
  }
  for (final String segment in path.split('/')) {
    if (segment.isEmpty) {
      return 'contains an empty segment';
    }
    if (segment == '.' || segment == '..') {
      return 'contains a "." or ".." segment';
    }
    if (!windows) {
      continue;
    }
    if (segment.contains(':')) {
      return 'contains a ":" character';
    }
    if (segment.endsWith('.') || segment.endsWith(' ')) {
      return 'ends with a dot or a space';
    }
    if (_reservedWindowsNames
        .contains(segment.split('.').first.toUpperCase())) {
      return 'names a reserved Windows device';
    }
  }
  return null;
}

/// Names Windows reserves for devices, whatever extension follows them.
const Set<String> _reservedWindowsNames = <String>{
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

/// A capture of the plain files of a git directory.
///
/// The files are keyed by their path relative to the git directory, spelled
/// with forward slashes whatever the platform: the segments are separated by
/// `/`, none is empty, `.` or `..`, and a key has no leading `/` or `\`, no
/// drive (`C:`) or UNC share (`\\server`) prefix, no backslash and no NUL
/// character. Any other key makes the constructor throw an [ArgumentError]
/// that names it. This keeps a capture to the files of the git directory, so
/// it moves between machines and compares against any clone of the same
/// shape. A capture holds every regular file the git directory contains at
/// the moment it was taken; what a caller keeps from it — configuration,
/// hooks, a fingerprint of the clone — is its own decision.
///
/// A capture contains the configuration and the hooks of the git directory.
/// Restoring one therefore lets the snapshot's source choose code git will
/// execute: restore only a snapshot from a trusted source, for example one
/// this application captured itself.
/// {@category Getting started}
final class GitDirectorySnapshot {
  final Map<String, Uint8List> _files;

  /// Creates a capture of [files], keyed by git-directory relative path.
  ///
  /// Throws an [ArgumentError] naming the key when one of them is not a valid
  /// git-directory relative path.
  GitDirectorySnapshot(Map<String, Uint8List> files)
      : _files = Map<String, Uint8List>.unmodifiable(files) {
    for (final String key in files.keys) {
      final String? problem = relativePathError(key);
      if (problem != null) {
        throw ArgumentError.value(
          key,
          'files',
          'Invalid git-directory relative path: the key $problem.',
        );
      }
    }
  }

  /// The captured files, keyed by git-directory relative path.
  ///
  /// The view is unmodifiable; the byte lists are the captured content.
  Map<String, Uint8List> get files => _files;
}
