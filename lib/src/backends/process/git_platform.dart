/// Operating system a [GitPlatform] describes.
/// {@category Testing}
enum GitOperatingSystem {
  /// Microsoft Windows.
  windows,

  /// Linux.
  linux,

  /// Apple macOS.
  macos,
}

/// Path spelling of a platform: Windows or POSIX.
///
/// It tells how absolute paths are recognized and written: the separator
/// between segments, whether a path is absolute, and the root a path hangs
/// from. Windows paths carry drive letters and UNC shares and accept both
/// separators; POSIX paths root at `/`.
/// {@category Testing}
final class GitPathStyle {
  const GitPathStyle._(this._windows);

  /// Windows spelling: `\` separator, drives and UNC shares.
  static const GitPathStyle windows = GitPathStyle._(true);

  /// POSIX spelling: `/` separator, a single root.
  static const GitPathStyle posix = GitPathStyle._(false);

  final bool _windows;

  /// Joins [relative] onto [base], rewriting each `/` of [relative] to this
  /// spelling's separator.
  ///
  /// A [relative] that is absolute per this spelling is returned as is; an
  /// empty [relative] returns [base].
  String join(String base, String relative) {
    if (relative.isEmpty) {
      return base;
    }
    if (isAbsolute(relative)) {
      return relative;
    }
    final String tail =
        _windows ? relative.replaceAll('/', separator) : relative;
    return base.endsWith(separator) ? '$base$tail' : '$base$separator$tail';
  }

  /// The directory holding [path], or null when [path] has no directory
  /// component: a drive root, a bare root or a relative path without an
  /// ancestor.
  String? parentOf(String path) {
    final String prefix = driveRoot(path) ?? '';
    final String rest = path.substring(prefix.length);
    final int cut = rest.lastIndexOf(separator);
    if (cut < 0) {
      return prefix.isEmpty ? null : prefix;
    }
    final String parent = rest.substring(0, cut);
    if (parent.isEmpty) {
      return prefix.isEmpty ? null : prefix;
    }
    return prefix + parent;
  }

  /// Whether this is the Windows spelling.
  bool get isWindows => _windows;

  /// Whether this is the POSIX spelling.
  bool get isPosix => !_windows;

  /// Separator between the segments of a path.
  String get separator => _windows ? r'\' : '/';

  /// Whether [path] is absolute: on Windows a drive (`C:\...`), a UNC share
  /// (`\\server\share\...`) or a rooted path (`\...` or `/...`), on POSIX a
  /// leading `/`.
  bool isAbsolute(String path) {
    if (!_windows) {
      return path.startsWith('/');
    }
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      return true;
    }
    return path.startsWith('/') || path.startsWith('\\');
  }

  /// The root [path] hangs from: a drive (`C:\`), a UNC share
  /// (`\\server\share\`), or the plain root (`\` or `/`). Returns null when
  /// [path] is relative.
  String? driveRoot(String path) {
    if (!_windows) {
      return path.startsWith('/') ? '/' : null;
    }
    final RegExpMatch? unc =
        RegExp(r'^(\\\\+[^\\]+\\+[^\\]+)\\?').firstMatch(path);
    if (unc != null) {
      return '${unc.group(1)!}\\';
    }
    final RegExpMatch? drive = RegExp(r'^[A-Za-z]:[\\/]').firstMatch(path);
    if (drive != null) {
      return drive.group(0)!;
    }
    if (path.startsWith('\\')) {
      return '\\';
    }
    if (path.startsWith('/')) {
      return '/';
    }
    return null;
  }

  /// [path] normalized to an absolute spelling: every separator becomes
  /// [separator] and every `.` and `..` segment is resolved against the root
  /// [driveRoot] gives. Excess `..` at the root are dropped; the spelling of
  /// the root itself is kept.
  String normalize(String path) {
    final String? root = driveRoot(path);
    final String head = root == null ? path : path.substring(root.length);
    final List<String> result = <String>[];
    for (final String segment in head.split(RegExp(r'[/\\]'))) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (result.isNotEmpty) {
          result.removeLast();
        }
        continue;
      }
      result.add(segment);
    }
    if (root == null) {
      return result.join(separator);
    }
    final String tail = result.join(separator);
    final bool rooted = root.endsWith(r'\') || root.endsWith('/');
    return rooted ? '$root$tail' : '$root$separator$tail';
  }
}

/// The platform facts the process backend adapts to: the operating system,
/// the path spelling, the environment variables commands receive and the
/// directory relative paths hang from.
///
/// [windows], [linux] and [macos] describe those systems explicitly, with an
/// empty environment and no current directory. Tests build their own — a
/// custom [environment] and [currentDirectory] run Windows or POSIX behavior
/// on any machine without touching the host.
/// {@category Testing}
class GitPlatform {
  /// Creates a platform of [operatingSystem], with the [pathStyle] derived
  /// from it unless given, [environment] copied and made unmodifiable, and
  /// [currentDirectory] as the anchor relative paths hang from.
  GitPlatform({
    required this.operatingSystem,
    GitPathStyle? pathStyle,
    Map<String, String>? environment,
    String? currentDirectory,
  })  : pathStyle = pathStyle ??
            (operatingSystem == GitOperatingSystem.windows
                ? GitPathStyle.windows
                : GitPathStyle.posix),
        environment = Map.unmodifiable(environment ?? const <String, String>{}),
        currentDirectory = currentDirectory;

  /// Microsoft Windows, with the Windows path style and an empty
  /// environment.
  static final GitPlatform windows =
      GitPlatform(operatingSystem: GitOperatingSystem.windows);

  /// Linux, with the POSIX path style and an empty environment.
  static final GitPlatform linux =
      GitPlatform(operatingSystem: GitOperatingSystem.linux);

  /// Apple macOS, with the POSIX path style and an empty environment.
  static final GitPlatform macos =
      GitPlatform(operatingSystem: GitOperatingSystem.macos);

  /// Operating system commands run on.
  final GitOperatingSystem operatingSystem;

  /// Spelling of the paths commands exchange with this platform.
  final GitPathStyle pathStyle;

  /// Environment variables commands receive, unmodifiable.
  final Map<String, String> environment;

  /// Directory relative paths resolve against, or null when this platform
  /// stands for no working directory.
  final String? currentDirectory;
}
