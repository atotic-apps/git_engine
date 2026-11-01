import 'package:git_engine/git_engine.dart';
import '../git_runner.dart';
import '../process_git_indexed_repository.dart';

/// [GitIndex] implementation running git through the owning process
/// repository, so every command inherits the repository context — working
/// directory, alternate index and environment variables — instead of talking
/// to the runner alone.
class ProcessGitIndex implements GitIndex {
  /// Repository whose context every command runs in.
  final ProcessGitIndexedRepository repository;

  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitIndex({required this.repository});

  @override
  Future<GitOid> writeTree() async {
    final GitRunResult result =
        await repository.runCommand(const <String>['write-tree']);
    return _parseSingleOid(result.stdout, 'write-tree');
  }

  @override
  Future<void> readTree(GitOid tree) async {
    await _requireTree(tree);
    await repository.runCommand(<String>['read-tree', tree.value]);
  }

  /// Refuses [oid] unless it names an existing tree.
  Future<void> _requireTree(GitOid oid) async {
    final GitObjectType? type = await repository.objects.objectType(oid);
    if (type == null) {
      throw GitException('Object ${oid.value} does not exist');
    }
    if (type != GitObjectType.tree) {
      throw GitException(
        'Object ${oid.value} is a ${type.name}, not a tree',
      );
    }
  }

  @override
  Future<List<GitUnmergedEntry>> unmergedEntries() async {
    final GitRunResult result = await repository.runCommand(const <String>[
      'ls-files',
      '--unmerged',
      '-z',
    ]);
    final List<GitUnmergedEntry> entries = <GitUnmergedEntry>[];
    for (final String record in result.stdout.split('\x00')) {
      if (record.isEmpty) {
        continue;
      }
      entries.add(_parseUnmergedEntry(record));
    }
    return entries;
  }

  @override
  Future<void> remove(List<String> paths, {bool recursive = false}) async {
    if (paths.isEmpty) {
      return;
    }
    await repository.runCommand(<String>[
      'rm',
      '--cached',
      '--ignore-unmatch',
      if (recursive) '-r',
      '--',
      ...paths,
    ]);
  }

  /// Parses the object name printed on its own line by plumbing commands.
  static GitOid _parseSingleOid(String output, String command) {
    final String trimmed = output.trim();
    final GitOid? oid = GitOid.tryParse(trimmed);
    if (oid == null) {
      throw FormatException(
        'Unexpected $command output: "$trimmed"',
        output,
      );
    }
    return oid;
  }

  /// Parses one NUL-terminated record of `ls-files --unmerged -z`:
  /// `<mode> SP <oid> SP <stage> TAB <path>`.
  static GitUnmergedEntry _parseUnmergedEntry(String record) {
    final int tab = record.indexOf('\t');
    if (tab < 0) {
      throw FormatException('Unexpected ls-files record: "$record"', record);
    }
    final List<String> fields = record.substring(0, tab).split(' ');
    if (fields.length != 3) {
      throw FormatException('Unexpected ls-files record: "$record"', record);
    }
    final GitOid? oid = GitOid.tryParse(fields[1]);
    final int? stage = int.tryParse(fields[2]);
    if (oid == null || stage == null) {
      throw FormatException('Unexpected ls-files record: "$record"', record);
    }
    return GitUnmergedEntry(
      mode: fields[0],
      oid: oid,
      stage: stage,
      path: record.substring(tab + 1),
    );
  }
}
