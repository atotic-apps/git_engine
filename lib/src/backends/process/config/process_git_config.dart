import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_runner.dart';
import '../process_git_repository.dart';

/// Exit code `git config` reports when a key, a section or a pattern matches
/// nothing.
const int _configNothingFoundExitCode = 1;

/// [GitConfig] implementation running git through the owning process
/// repository, so every command inherits the repository context — working
/// directory and environment variables — instead of talking to the runner
/// alone, and is always limited to the local configuration (`--local`).
class ProcessGitConfig implements GitConfig {
  /// Repository whose context every command runs in.
  final ProcessGitRepository repository;

  /// Creates the implementation reading and writing the local configuration
  /// through [repository]'s context.
  ProcessGitConfig({required this.repository});

  @override
  Future<String?> get(String key) async {
    try {
      final GitRunResult result = await repository.runCommand(
        <String>['config', '--local', '--get', '--', key],
      );
      return stripTrailingNewline(result.stdout);
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException catch (error) {
      // Exit code 1 without any message: the local configuration does not
      // hold the key. Any other exit is a real failure — shell refusals,
      // malformed keys — and is reported as is.
      if (_foundNothing(error)) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<List<GitConfigEntry>> getAll({String prefix = ''}) async {
    try {
      final GitRunResult result = await repository.runCommand(
        <String>['config', '--local', '--null', '--list'],
      );
      return _parseNullSeparated(result.stdout)
          .where((GitConfigEntry entry) => entry.key.startsWith(prefix))
          .toList(growable: false);
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException catch (error) {
      if (_foundNothing(error)) {
        return const <GitConfigEntry>[];
      }
      rethrow;
    }
  }

  @override
  Future<void> set(String key, String value) {
    return repository.runCommand(
      <String>['config', '--local', '--', key, value],
    );
  }

  @override
  Future<void> unset(String key) {
    return repository.runCommand(
      <String>['config', '--local', '--unset', '--', key],
    );
  }

  @override
  Future<void> removeSection(String name) {
    return repository.runCommand(
      <String>['config', '--local', '--remove-section', '--', name],
    );
  }

  /// Whether git reported that nothing matches instead of failing.
  ///
  /// A miss is a bare exit code 1 with no output; a malformed key, a locked
  /// file or any other problem comes with a message and stays an error.
  static bool _foundNothing(GitCommandException error) {
    return error.exitCode == _configNothingFoundExitCode &&
        error.stderr.trim().isEmpty;
  }

  /// Reads git's null-separated output: one `key LF value NUL` record per
  /// entry; the value keeps any later newline it holds.
  List<GitConfigEntry> _parseNullSeparated(String output) {
    final List<GitConfigEntry> entries = <GitConfigEntry>[];
    for (final String record in output.split('\x00')) {
      if (record.isEmpty) {
        continue;
      }
      final int separator = record.indexOf('\n');
      if (separator < 0) {
        entries.add(GitConfigEntry(key: record, value: ''));
        continue;
      }
      entries.add(
        GitConfigEntry(
          key: record.substring(0, separator),
          value: record.substring(separator + 1),
        ),
      );
    }
    return entries;
  }

  /// The output without the single newline git prints after a value.
  static String stripTrailingNewline(String output) {
    if (output.endsWith('\n')) {
      return output.substring(0, output.length - 1);
    }
    return output;
  }
}
