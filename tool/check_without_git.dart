/// Runs the machine-independent test suites with a `PATH` that cannot reach
/// the installed git.
///
/// The suites are the model, server, architecture and public surface tests:
/// they describe the contracts the process backend shares, so they must pass
/// without a git executable at all. The check builds a restricted `PATH` from
/// the Dart SDK directory and the essential system directories, refuses to run
/// when git is still reachable through it, and exits with the test suite's own
/// status.
///
///     dart run tool/check_without_git.dart
library;

import 'dart:io';

/// The test paths the check runs.
const List<String> _testPaths = <String>[
  'test/models',
  'test/server',
  'test/architecture',
  'test/public_api_test.dart',
  'test/public_surface_test.dart',
];

/// Runs the machine-independent test suites without git on the `PATH`.
Future<void> main() async {
  final String path = _restrictedPath();
  stdout.writeln('restricted PATH: $path');

  final String? git = _findExecutable('git', _directoriesOf(path));
  if (git != null) {
    stderr.writeln(
      'git is still reachable on the restricted PATH: $git',
    );
    stderr.writeln(
      'the core suites must run without git; move git out of the restricted '
      'directories or adjust the check',
    );
    exit(1);
  }

  final Process process = await Process.start(
    Platform.resolvedExecutable,
    <String>['test', ..._testPaths],
    workingDirectory: _packageRoot().path,
    environment: _environmentWithPath(path),
    includeParentEnvironment: false,
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await process.exitCode);
}

/// The `PATH` of the check: the Dart SDK directory and the essential system
/// directories only.
String _restrictedPath() {
  final List<String> directories = <String>[
    File(Platform.resolvedExecutable).parent.path,
  ];
  if (Platform.isWindows) {
    final String? systemRoot =
        Platform.environment['SystemRoot'] ?? Platform.environment['WINDIR'];
    if (systemRoot != null) {
      directories.add(_join(systemRoot, 'System32'));
      directories.add(systemRoot);
    }
  } else {
    directories.addAll(<String>['/usr/bin', '/bin']);
  }
  return directories.join(Platform.isWindows ? ';' : ':');
}

/// [path] split into the directories it lists.
List<String> _directoriesOf(String path) {
  return path
      .split(Platform.isWindows ? ';' : ':')
      .where((String directory) => directory.isNotEmpty)
      .toList();
}

/// The inherited environment with every `PATH` spelling replaced by [path].
Map<String, String> _environmentWithPath(String path) {
  final Map<String, String> environment = <String, String>{};
  Platform.environment.forEach((String name, String value) {
    if (name.toUpperCase() != 'PATH') {
      environment[name] = value;
    }
  });
  environment['PATH'] = path;
  return environment;
}

/// The first spelling of [name] found in [directories], or null.
String? _findExecutable(String name, List<String> directories) {
  final List<String> extensions = Platform.isWindows
      ? <String>['.exe', '.com', '.bat', '.cmd', '']
      : <String>[''];
  for (final String directory in directories) {
    for (final String extension in extensions) {
      final File candidate = File(_join(directory, '$name$extension'));
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
  }
  return null;
}

/// The package root: the parent of the directory holding this script, falling
/// back to the current directory when the script has no repository beside it.
Directory _packageRoot() {
  final Directory tool = File.fromUri(Platform.script).parent;
  final Directory root = tool.parent;
  return File(_join(root.path, 'pubspec.yaml')).existsSync()
      ? root
      : Directory.current;
}

/// Joins [base] and [relative] with the platform separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}
