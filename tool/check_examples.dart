/// Runs the executable examples in order and stops at the first failure.
///
///     dart run tool/check_examples.dart
///
/// The remote examples are left out because they need internet access.
library;

import 'dart:io';

/// The examples this check runs, in order.
const List<String> _examples = <String>[
  'example/git_engine_example.dart',
  'example/local_repository.dart',
  'example/client.dart',
  'example/bare_repository.dart',
];

Future<void> main() async {
  final Directory root = _packageRoot();
  for (final String example in _examples) {
    stdout.writeln('running $example');
    final Process process = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', example],
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final int code = await process.exitCode;
    if (code != 0) {
      stderr.writeln('$example failed with exit code $code');
      exit(code);
    }
  }
  stdout.writeln('all examples passed');
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
