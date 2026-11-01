import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/backend.dart';
import 'package:git_engine/git_engine.dart';
import '../confined_path.dart';
import '../git_command_exception.dart';
import '../git_refusal.dart';
import '../git_runner.dart';
import '../process_git_working_repository.dart';

/// [GitWorktree] implementation running git through the owning process
/// repository, so every command inherits the repository context — working
/// directory and environment variables — instead of talking to the runner
/// alone.
class ProcessGitWorktree implements GitWorktree {
  /// Repository whose context every command runs in.
  final ProcessGitWorkingRepository repository;

  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitWorktree({required this.repository});

  @override
  Future<List<GitStatusEntry>> status() async {
    final GitRunResult result = await repository.runCommand(
      const <String>['status', '--porcelain=v1', '-z'],
    );
    return _parseStatus(result.stdout);
  }

  @override
  Future<bool> isClean() async => (await status()).isEmpty;

  @override
  Future<void> add(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    await repository.runCommand(<String>['add', '--', ...paths]);
  }

  @override
  Future<void> addAll() {
    return repository.runCommand(const <String>['add', '-A']);
  }

  @override
  Future<void> intentToAdd(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    await repository.runCommand(<String>['add', '-N', '--', ...paths]);
  }

  @override
  Future<void> reset({
    GitResetMode mode = GitResetMode.mixed,
    String? target,
  }) async {
    if (mode == GitResetMode.soft) {
      throw ArgumentError.value(
        mode,
        'mode',
        'use GitRefs.resetSoft to move HEAD without the index or work tree',
      );
    }
    if (target != null) {
      refuseOptionLikeRevision(target);
    }
    try {
      await repository.runCommand(<String>[
        'reset',
        mode == GitResetMode.hard ? '--hard' : '--mixed',
        if (target != null) target,
      ]);
    } on GitCommandException catch (error) {
      if (target == null) {
        rethrow;
      }
      throw unknownRevisionFailure(error, target);
    }
  }

  @override
  Future<void> clean({bool directories = false}) {
    return repository.runCommand(<String>[
      'clean',
      '-f',
      if (directories) '-d',
    ]);
  }

  @override
  Future<void> checkout(String branch) async {
    refuseOptionLikeRevision(branch);
    try {
      await repository.runCommand(<String>['checkout', branch, '--']);
    } on GitCommandException catch (error) {
      throw checkoutFailure(error, branch);
    }
  }

  @override
  Future<void> checkoutDetached(String rev) async {
    refuseOptionLikeRevision(rev);
    try {
      await repository.runCommand(<String>['checkout', '--detach', rev]);
    } on GitCommandException catch (error) {
      throw checkoutFailure(error, rev);
    }
  }

  @override
  Future<void> checkoutNewBranch(
    String name, {
    String? startPoint,
    bool resetIfExists = false,
  }) async {
    refuseOptionLikeRevision(name);
    if (startPoint != null) {
      refuseOptionLikeRevision(startPoint);
    }
    final String expression = startPoint ?? name;
    try {
      await repository.runCommand(<String>[
        'checkout',
        resetIfExists ? '-B' : '-b',
        name,
        if (startPoint != null) startPoint,
      ]);
    } on GitCommandException catch (error) {
      throw checkoutFailure(error, expression);
    }
  }

  @override
  Future<bool> isIgnored(String path, {bool noIndex = false}) async {
    // check-ignore rejects the literal pathspec magic as unsupported, while it
    // already treats each pathname it receives as literal. Run this one
    // command without the repository-wide setting.
    final ProcessGitWorkingRepository target = repository.withEnvironment(
      const <String, String>{'GIT_LITERAL_PATHSPECS': '0'},
    );
    try {
      await target.runCommand(<String>[
        'check-ignore',
        '--quiet',
        if (noIndex) '--no-index',
        '--',
        path,
      ]);
      return true;
    } on GitCommandException catch (error) {
      if (error.exitCode == 1) {
        return false;
      }
      rethrow;
    }
  }

  @override
  Future<List<GitConflictRegion>> scanConflictMarkers(
    List<String> paths,
  ) async {
    if (paths.isEmpty) {
      return const <GitConflictRegion>[];
    }
    final bool windows = repository.platform.pathStyle.isWindows;
    // Refuse the whole call before the first file system access, so a list
    // holding one refused path reads nothing at all.
    for (final String path in paths) {
      final String? problem = relativePathError(path, windows: windows);
      if (problem != null) {
        throw GitException(
          'Refused work-tree file "$path": the path $problem.',
        );
      }
    }
    final String root = await repository.toplevel();
    final List<GitConflictRegion> regions = <GitConflictRegion>[];
    for (final String path in paths) {
      final String? filePath = await confineRelativePath(
        repository.fileSystem,
        repository.platform.pathStyle,
        root: root,
        relativePath: path,
        linkPolicy: ConfinedPathLinkPolicy.ignore,
        subject: 'work-tree file',
        windows: windows,
      );
      if (filePath == null || !await repository.fileSystem.exists(filePath)) {
        continue;
      }
      regions.addAll(
        scanConflictRegions(
            path, await repository.fileSystem.readBytes(filePath)),
      );
    }
    return regions;
  }

  /// The conflict blocks of one file held as [bytes], named [path].
  ///
  /// Lines are matched one by one: a `<<<<<<<` start opens a candidate, the
  /// next `=======` line is its separator, the next `>>>>>>>` line closes
  /// the block. A candidate without a closing tail reports nothing. The walk
  /// stops at the first start that no separator, or no closing tail, follows:
  /// no later start can complete a block either, and one pass over the lines
  /// is enough.
  static List<GitConflictRegion> scanConflictRegions(
    String path,
    Uint8List bytes,
  ) {
    final RegExp start = RegExp(r'^<{7}( .*)?$');
    final RegExp separator = RegExp(r'^={7}$');
    final RegExp end = RegExp(r'^>{7}( .*)?$');
    final List<String> lines = utf8
        .decode(bytes, allowMalformed: true)
        .split('\n')
        .map(_withoutCarriageReturn)
        .toList();
    final List<GitConflictRegion> regions = <GitConflictRegion>[];
    var index = 0;
    while (index < lines.length) {
      if (!start.hasMatch(lines[index])) {
        index++;
        continue;
      }
      var separatorLine = index + 1;
      while (separatorLine < lines.length &&
          !separator.hasMatch(lines[separatorLine])) {
        separatorLine++;
      }
      if (separatorLine >= lines.length) {
        break;
      }
      var endLine = separatorLine + 1;
      while (endLine < lines.length && !end.hasMatch(lines[endLine])) {
        endLine++;
      }
      if (endLine >= lines.length) {
        break;
      }
      regions.add(GitConflictRegion(
        path: path,
        startLine: index + 1,
        separatorLine: separatorLine + 1,
        endLine: endLine + 1,
      ));
      index = endLine + 1;
    }
    return regions;
  }

  /// [line] without one trailing carriage return.
  static String _withoutCarriageReturn(String line) {
    return line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
  }

  @override
  Future<GitOid> commit(
    String message, {
    GitIdentity? identity,
    bool allowEmpty = false,
  }) async {
    final ProcessGitWorkingRepository target = identity == null
        ? repository
        : repository.withEnvironment(identity.toEnvironment());
    await target.runCommand(<String>[
      'commit',
      '-m',
      message,
      if (allowEmpty) '--allow-empty',
    ]);
    final GitRunResult head =
        await target.runCommand(const <String>['rev-parse', 'HEAD']);
    return GitOid.parse(head.stdout.trim());
  }

  /// Parses NUL-separated porcelain v1 output.
  ///
  /// Each entry starts with a two-letter code and a space, then the path. A
  /// rename or copy is followed by a second field holding the source path: in
  /// `-z` mode the destination comes first, unlike the human-readable form
  /// which reads `source -> destination`.
  static List<GitStatusEntry> _parseStatus(String output) {
    final List<String> fields = output.split('\u0000');
    final List<GitStatusEntry> entries = <GitStatusEntry>[];
    var index = 0;
    while (index < fields.length) {
      final String field = fields[index];
      index++;
      if (field.isEmpty) {
        continue;
      }
      if (field.length < 4 || field[2] != ' ') {
        throw FormatException('Unexpected git status entry: "$field"', field);
      }
      final String code = field.substring(0, 2);
      final String path = field.substring(3);
      String? originalPath;
      if (code.contains('R') || code.contains('C')) {
        if (index >= fields.length || fields[index].isEmpty) {
          throw FormatException(
            'Missing source path for git status entry: "$field"',
            output,
          );
        }
        originalPath = fields[index];
        index++;
      }
      entries.add(GitStatusEntry(
        code: code,
        path: path,
        originalPath: originalPath,
        indexState: _stateFor(code[0]),
        workTreeState: _stateFor(code[1]),
      ));
    }
    return entries;
  }

  /// State described by one porcelain status letter.
  static GitFileState _stateFor(String letter) {
    switch (letter) {
      case ' ':
        return GitFileState.unchanged;
      case 'M':
        return GitFileState.modified;
      case 'T':
        return GitFileState.typeChanged;
      case 'A':
        return GitFileState.added;
      case 'D':
        return GitFileState.deleted;
      case 'R':
        return GitFileState.renamed;
      case 'C':
        return GitFileState.copied;
      case 'U':
        return GitFileState.unmerged;
      case '?':
        return GitFileState.untracked;
      default:
        throw FormatException('Unexpected git status letter: "$letter"');
    }
  }
}
