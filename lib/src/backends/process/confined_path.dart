import 'package:git_engine/backend.dart';
import 'package:git_engine/git_engine.dart';

import 'git_file_system.dart';
import 'git_platform.dart';

/// How a confinement walk treats a symbolic link or Windows junction found
/// among the segments of a relative path.
enum ConfinedPathLinkPolicy {
  /// Follows the link and requires its target to stay under the root.
  resolve,

  /// Reports the path as ignored, so its content is never read.
  ignore,
}

/// The platform path of [relativePath] under [root], or null when the path
/// must be ignored.
///
/// The path must satisfy [relativePathError]; with [windows] the Windows
/// naming rules apply too. A refused path throws a [GitException] naming it
/// before any file system call. Every existing segment is then walked: with
/// [ConfinedPathLinkPolicy.ignore] the first segment that is a symbolic link
/// or a Windows junction makes the result null, while with
/// [ConfinedPathLinkPolicy.resolve] the segment is resolved and a target
/// outside [rootReal] throws a [GitException] naming the path.
///
/// [rootReal] is [root] with its own links resolved; it is resolved here when
/// omitted and is only used by [ConfinedPathLinkPolicy.resolve].
///
/// Checking and reading cannot be one atomic operation: a work tree changed
/// between them can turn a checked path into a link, which the later read
/// follows. A caller of [ConfinedPathLinkPolicy.ignore] therefore documents
/// that residual race rather than claiming the read cannot cross a link.
Future<String?> confineRelativePath(
  GitFileSystem fileSystem,
  GitPathStyle pathStyle, {
  required String root,
  required String relativePath,
  required ConfinedPathLinkPolicy linkPolicy,
  String? rootReal,
  String subject = 'file',
  bool windows = false,
}) async {
  final String? problem = relativePathError(relativePath, windows: windows);
  if (problem != null) {
    throw GitException(
      'Refused $subject "$relativePath": the path $problem.',
    );
  }
  String? base;
  if (linkPolicy == ConfinedPathLinkPolicy.resolve) {
    base = rootReal ?? await _resolved(fileSystem, root, relativePath, subject);
  }
  String current = root;
  for (final String segment in relativePath.split('/')) {
    current = pathStyle.join(current, segment);
    final bool link = await fileSystem.isLink(current);
    if (link && linkPolicy == ConfinedPathLinkPolicy.ignore) {
      return null;
    }
    if (!link && !await fileSystem.exists(current)) {
      break;
    }
    if (linkPolicy == ConfinedPathLinkPolicy.resolve) {
      final String resolved =
          await _resolved(fileSystem, current, relativePath, subject);
      if (!_isWithin(pathStyle, base!, resolved)) {
        throw GitException(
          'Refused $subject "$relativePath": "$current" resolves outside '
          'the root.',
        );
      }
    }
  }
  return pathStyle.join(root, relativePath);
}

/// [path] with every symbolic link and Windows junction resolved, or a
/// [GitException] naming [relativePath] when it cannot be resolved.
Future<String> _resolved(
  GitFileSystem fileSystem,
  String path,
  String relativePath,
  String subject,
) async {
  try {
    return await fileSystem.resolveSymbolicLinks(path);
  } on Exception {
    throw GitException(
      'Refused $subject "$relativePath": "$path" cannot be resolved.',
    );
  }
}

/// Whether [candidate] is [base] or sits under it, on [style]'s spelling.
bool _isWithin(GitPathStyle style, String base, String candidate) {
  final String root = _canonical(base, style);
  final String path = _canonical(candidate, style);
  final String prefix =
      root.endsWith(style.separator) ? root : '$root${style.separator}';
  return path == root || path.startsWith(prefix);
}

/// [path] normalized to an absolute spelling, compared case-insensitively
/// on Windows.
String _canonical(String path, GitPathStyle style) {
  final String normalized = style.normalize(path);
  return style.isWindows ? normalized.toLowerCase() : normalized;
}
