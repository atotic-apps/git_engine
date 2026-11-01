import 'dart:convert';

import 'package:git_engine/backend.dart';
import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_refusal.dart';
import '../git_runner.dart';
import '../process_git_repository.dart';

/// [GitBranches] implementation running git through the owning process
/// repository, so every command inherits the repository context — working
/// directory and environment variables — instead of talking to the runner
/// alone.
class ProcessGitBranches implements GitBranches {
  /// Repository whose context every command runs in.
  final ProcessGitRepository repository;

  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitBranches({required this.repository});

  /// Fields of one local-branch record: full name, object name, the `*`
  /// marker of the branch `HEAD` points at, full name of the tracked
  /// upstream.
  static const String _listFormat =
      '%(refname)%09%(objectname)%09%(HEAD)%09%(upstream)';

  static const String _headsPrefix = 'refs/heads/';
  static const String _remotesPrefix = 'refs/remotes/';

  /// Fields of one remote-branch record: full name, object name, the full
  /// name of the ref this one is symbolic to (the `<remote>/HEAD`
  /// references), empty otherwise.
  static const String _remoteListFormat =
      '%(refname)%09%(objectname)%09%(symref)';

  @override
  Future<List<GitBranch>> list() async {
    final GitRunResult result = await repository.runCommand(<String>[
      'for-each-ref',
      '--format=$_listFormat',
      'refs/heads',
    ]);
    return _parseBranches(result.stdout);
  }

  @override
  Future<List<GitRef>> listRemote({String? remote}) async {
    final GitRunResult result = await repository.runCommand(<String>[
      'for-each-ref',
      '--format=$_remoteListFormat',
      remote == null ? 'refs/remotes' : 'refs/remotes/$remote',
    ]);
    return _parseRemoteBranches(result.stdout);
  }

  @override
  Future<String?> current() async {
    final String? head = await _headReference();
    return head == null ? null : _withoutPrefix(head, _headsPrefix);
  }

  @override
  Future<void> create(
    String name, {
    String? startPoint,
    bool force = false,
  }) async {
    checkBranchName(name);
    if (startPoint != null) {
      refuseOptionLikeRevision(startPoint);
    }
    try {
      await repository.runCommand(<String>[
        'branch',
        if (force) '--force',
        '--',
        name,
        if (startPoint != null) startPoint,
      ]);
    } on GitCommandException catch (error) {
      final GitException refusal = refExistsFailure(error, name);
      if (refusal is! GitCommandException) {
        throw refusal;
      }
      throw unknownRevisionFailure(error, startPoint ?? 'HEAD');
    }
  }

  @override
  Future<void> rename(String name, String newName, {bool force = false}) async {
    checkBranchName(name);
    checkBranchName(newName);
    try {
      await repository.runCommand(<String>[
        'branch',
        force ? '-M' : '-m',
        '--',
        name,
        newName,
      ]);
    } on GitCommandException catch (error) {
      final GitException refusal = refExistsFailure(error, newName);
      if (refusal is! GitCommandException) {
        throw refusal;
      }
      throw branchNotFoundFailure(error, name);
    }
  }

  @override
  Future<void> delete(String name, {bool force = false}) async {
    checkBranchName(name);
    // git refuses only in a work tree; a bare repository would delete the
    // branch HEAD points at and leave HEAD dangling, so the refusal is held
    // here instead.
    final String? checkedOut = await _headReference();
    if (checkedOut == '$_headsPrefix$name') {
      throw GitException(
        'the branch "$name" is checked out and cannot be deleted',
      );
    }
    try {
      await repository.runCommand(<String>[
        'branch',
        force ? '-D' : '-d',
        '--',
        name,
      ]);
    } on GitCommandException catch (error) {
      throw branchDeletionFailure(error, name);
    }
  }

  @override
  Future<void> setUpstream(String branch, String upstream) async {
    checkBranchName(branch);
    refuseOptionLikeRevision(upstream);
    try {
      await repository.runCommand(<String>[
        'branch',
        '--set-upstream-to=$upstream',
        '--',
        branch,
      ]);
    } on GitCommandException catch (error) {
      final GitException refusal = branchNotFoundFailure(error, branch);
      if (refusal is! GitCommandException) {
        throw refusal;
      }
      throw unknownRevisionFailure(error, upstream);
    }
  }

  /// Full name of the branch `HEAD` points at, or null when `HEAD` is
  /// detached.
  Future<String?> _headReference() async {
    try {
      final GitRunResult result = await repository.runCommand(
        <String>['symbolic-ref', '--quiet', 'HEAD'],
      );
      return result.stdout.trim();
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException {
      // Exit code 1: HEAD is detached.
      return null;
    }
  }

  /// Removes [prefix] from the start of [ref], leaving [ref] unchanged when
  /// it does not start with it.
  static String _withoutPrefix(String ref, String prefix) =>
      ref.startsWith(prefix) ? ref.substring(prefix.length) : ref;

  /// Short form of an upstream reference: `<remote>/<branch>` for a
  /// remote-tracking branch, the local branch name for a local one.
  static String _shortUpstream(String ref) {
    if (ref.startsWith(_remotesPrefix)) {
      return _withoutPrefix(ref, _remotesPrefix);
    }
    return _withoutPrefix(ref, _headsPrefix);
  }

  /// Parses the tab-separated `for-each-ref` records of a local listing.
  static List<GitBranch> _parseBranches(String output) {
    final List<GitBranch> branches = <GitBranch>[];
    for (final String line in const LineSplitter().convert(output)) {
      if (line.isEmpty) {
        continue;
      }
      final List<String> fields = line.split('\t');
      if (fields.length != 4) {
        throw FormatException('Unexpected for-each-ref line: "$line"', line);
      }
      final GitOid? oid = GitOid.tryParse(fields[1].trim());
      if (oid == null) {
        throw FormatException(
          'Unexpected for-each-ref object name in: "$line"',
          line,
        );
      }
      final String upstream = fields[3].trim();
      branches.add(GitBranch(
        name: _withoutPrefix(fields[0].trim(), _headsPrefix),
        oid: oid,
        isCurrent: fields[2].trim() == '*',
        upstream: upstream.isEmpty ? null : _shortUpstream(upstream),
      ));
    }
    return branches;
  }

  /// Parses the tab-separated `for-each-ref` records of a remote listing,
  /// keeping only the references that are not symbolic.
  static List<GitRef> _parseRemoteBranches(String output) {
    final List<GitRef> refs = <GitRef>[];
    for (final String line in const LineSplitter().convert(output)) {
      if (line.isEmpty) {
        continue;
      }
      final List<String> fields = line.split('\t');
      if (fields.length != 3) {
        throw FormatException('Unexpected for-each-ref line: "$line"', line);
      }
      if (fields[2].trim().isNotEmpty) {
        // A symbolic reference, e.g. origin/HEAD.
        continue;
      }
      final GitOid? oid = GitOid.tryParse(fields[1].trim());
      if (oid == null) {
        throw FormatException(
          'Unexpected for-each-ref object name in: "$line"',
          line,
        );
      }
      refs.add(GitRef(name: fields[0], oid: oid));
    }
    return refs;
  }
}
