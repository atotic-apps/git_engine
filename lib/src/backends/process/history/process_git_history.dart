import 'dart:convert';

import 'package:git_engine/backend.dart';
import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_refusal.dart';
import '../git_runner.dart';
import '../process_git_repository.dart';

/// [GitHistory] implementation running git through the owning process
/// repository, so every command inherits the repository context.
class ProcessGitHistory implements GitHistory {
  /// Repository whose context every command runs in.
  final ProcessGitRepository repository;

  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitHistory({required this.repository});

  @override
  Future<bool> isAncestor(GitOid ancestor, GitOid descendant) async {
    try {
      await repository.runCommand(<String>[
        'merge-base',
        '--is-ancestor',
        ancestor.value,
        descendant.value,
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
  Future<GitOid?> mergeBase(GitOid first, GitOid second) async {
    try {
      final GitRunResult result = await repository.runCommand(
        <String>['merge-base', first.value, second.value],
      );
      return GitOid.tryParse(result.stdout.trim());
    } on GitCommandException catch (error) {
      if (error.exitCode == 1) {
        // Exit code 1: the two commits share no ancestor.
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<List<GitLogCommit>> log({
    String to = 'HEAD',
    String? from,
    String? path,
    int? limit,
    bool firstParent = false,
  }) async {
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be greater than zero');
    }

    GitOid? fromOid;
    if (from != null) {
      fromOid = await repository.revisions.resolveRevision(from);
      if (fromOid == null) {
        throw GitUnknownRevisionException(expression: from);
      }
    }
    final GitOid? toOid = await repository.revisions.resolveRevision(to);
    if (toOid == null) {
      if (to == 'HEAD' && from == null) {
        return const <GitLogCommit>[];
      }
      throw GitUnknownRevisionException(expression: to);
    }
    final String range =
        fromOid == null ? toOid.value : '${fromOid.value}..${toOid.value}';

    final GitRunResult result;
    try {
      result = await repository.runCommand(<String>[
        'rev-list',
        '--date-order',
        if (firstParent) '--first-parent',
        if (limit != null) ...<String>['-n', '$limit'],
        range,
        if (path != null) ...<String>['--', path],
      ]);
    } on GitCommandException catch (error) {
      throw unknownRevisionFailure(error, from ?? to);
    }

    final GitObjects objects = repository.objects;
    final List<GitLogCommit> commits = <GitLogCommit>[];
    for (final String line in const LineSplitter().convert(result.stdout)) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final GitOid oid = GitOid.parse(trimmed);
      commits.add(
        GitLogCommit(oid: oid, commit: await objects.readCommit(oid)),
      );
    }
    return commits;
  }

  @override
  Future<GitOid?> lastCommitTouching(String path, {String? rev}) async {
    if (rev != null) {
      refuseOptionLikeRevision(rev);
    }
    try {
      final GitRunResult result = await repository.runCommand(<String>[
        'log',
        '-1',
        '--format=%H',
        if (rev != null) ...<String>['--end-of-options', rev],
        '--',
        path,
      ]);
      final String output = result.stdout.trim();
      return output.isEmpty ? null : GitOid.parse(output);
    } on GitCommandException catch (error) {
      if (rev == null) {
        rethrow;
      }
      throw unknownRevisionFailure(error, rev);
    }
  }

  @override
  Future<List<GitOid>> commitsTouching(
    String path, {
    String? from,
    String? to,
  }) async {
    if (from != null) {
      refuseOptionLikeRevision(from);
    }
    if (to != null) {
      refuseOptionLikeRevision(to);
    }
    final String range =
        from == null ? (to ?? 'HEAD') : '$from..${to ?? 'HEAD'}';
    if (readsAsOption(range)) {
      throw GitUnknownRevisionException(
        expression: range,
      );
    }
    try {
      final GitRunResult result = await repository.runCommand(<String>[
        'log',
        '--format=%H',
        '--end-of-options',
        range,
        '--',
        path,
      ]);
      return const LineSplitter()
          .convert(result.stdout)
          .where((String line) => line.trim().isNotEmpty)
          .map((String line) => GitOid.parse(line.trim()))
          .toList();
    } on GitCommandException catch (error) {
      throw unknownRevisionFailure(error, range);
    }
  }

  @override
  Future<List<GitLogEntry>> commitsSince(String base, String tip) async {
    refuseOptionLikeRevision(base);
    refuseOptionLikeRevision(tip);
    final String range = '$base..$tip';
    if (readsAsOption(range)) {
      throw GitUnknownRevisionException(
        expression: range,
      );
    }
    try {
      final GitRunResult result = await repository.runCommand(<String>[
        'log',
        '--format=%H%x1f%s',
        '--end-of-options',
        range,
      ]);
      final List<GitLogEntry> entries = <GitLogEntry>[];
      for (final String line in const LineSplitter().convert(result.stdout)) {
        if (line.isEmpty) {
          continue;
        }
        final int separator = line.indexOf('\x1f');
        if (separator < 0) {
          throw FormatException('Unexpected git log line: "$line"', line);
        }
        entries.add(GitLogEntry(
          oid: GitOid.parse(line.substring(0, separator)),
          subject: line.substring(separator + 1),
        ));
      }
      return entries;
    } on GitCommandException catch (error) {
      throw unknownRevisionFailure(error, range);
    }
  }
}
