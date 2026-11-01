/// Parsed form of a `git --version` output, as a (major, minor, patch)
/// record used for version comparisons.
typedef GitVersionTriple = (int, int, int);

/// Extracts the version numbers from a `git --version` output, e.g.
/// `git version 2.41.0.windows.1` or `git version 2.39.2 (Apple Git-143)`.
///
/// Returns null when no version can be found.
GitVersionTriple? parseGitVersion(String versionOutput) {
  final RegExpMatch? match = RegExp(
    r'git version (\d+)(?:\.(\d+))?(?:\.(\d+))?',
  ).firstMatch(versionOutput.trim());
  if (match == null) {
    return null;
  }
  return (
    int.parse(match.group(1)!),
    int.parse(match.group(2) ?? '0'),
    int.parse(match.group(3) ?? '0'),
  );
}

/// Parses a version constraint of the form `major[.minor[.patch]]`.
///
/// Returns null when [constraint] is not such a version.
GitVersionTriple? parseVersionConstraint(String constraint) {
  final List<String> parts = constraint.trim().split('.');
  if (parts.isEmpty || parts.length > 3) {
    return null;
  }
  final List<int> numbers = <int>[];
  for (final String part in parts) {
    final int? value = int.tryParse(part);
    if (value == null || value < 0) {
      return null;
    }
    numbers.add(value);
  }
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return (numbers[0], numbers[1], numbers[2]);
}

/// Orders two versions: negative when [a] is older than [b], positive when
/// newer, zero when equal.
int compareGitVersions(GitVersionTriple a, GitVersionTriple b) {
  if (a.$1 != b.$1) {
    return a.$1.compareTo(b.$1);
  }
  if (a.$2 != b.$2) {
    return a.$2.compareTo(b.$2);
  }
  return a.$3.compareTo(b.$3);
}
