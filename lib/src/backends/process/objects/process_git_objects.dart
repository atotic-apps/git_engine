import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_date.dart';
import '../git_process_launcher.dart';
import '../git_runner.dart';
import '../process_git_repository.dart';
import '../tail_byte_buffer.dart';
import 'raw_object_parser.dart';

/// [GitObjects] implementation running git through the owning process
/// repository, so every command inherits the repository context — working
/// directory and environment variables — instead of talking to the runner
/// alone.
class ProcessGitObjects implements GitObjects {
  /// Repository whose context every command runs in.
  final ProcessGitRepository repository;

  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitObjects({required this.repository});

  /// Runs [arguments] with [stdin] inside the repository context.
  Future<GitRunResult> _run(
    List<String> arguments, {
    Uint8List? stdin,
  }) {
    return repository.runCommand(arguments, stdin: stdin);
  }

  @override
  Future<GitOid> hashObject(
    List<int> bytes, {
    GitObjectType type = GitObjectType.blob,
  }) async {
    final GitRunResult result = await _run(
      <String>[
        'hash-object',
        '-t',
        type.name,
        '--stdin',
      ],
      stdin: _bytes(bytes),
    );
    return _parseSingleOid(result.stdout, 'hash-object');
  }

  @override
  Future<GitOid> writeObject(GitObjectType type, List<int> content) async {
    try {
      final GitRunResult result = await _run(
        <String>[
          'hash-object',
          '-t',
          type.name,
          '-w',
          '--stdin',
        ],
        stdin: _bytes(content),
      );
      return _parseSingleOid(result.stdout, 'hash-object');
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException catch (error) {
      throw GitInvalidObjectException(type: type, cause: error);
    }
  }

  @override
  Future<GitObjectType?> objectType(GitOid oid) async {
    try {
      final GitRunResult result = await _run(
        <String>['cat-file', '-t', oid.value],
      );
      return GitObjectType.tryParse(result.stdout.trim());
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException {
      // Absent object: git reports it on stderr and exits non-zero.
      return null;
    }
  }

  @override
  Future<bool> objectExists(GitOid oid) async {
    try {
      await _run(<String>['cat-file', '-e', oid.value]);
      return true;
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException {
      return false;
    }
  }

  @override
  Future<GitRawObject> readObject(GitOid oid) async {
    final GitRunResult typeResult = await _run(
      <String>['cat-file', '-t', oid.value],
    );
    final GitObjectType? type =
        GitObjectType.tryParse(typeResult.stdout.trim());
    if (type == null) {
      throw FormatException(
        'Unexpected cat-file output: "${typeResult.stdout.trim()}"',
        typeResult.stdout,
      );
    }
    final GitRunResult content = await _run(
      <String>['cat-file', type.name, oid.value],
    );
    return GitRawObject(type: type, content: content.stdoutBytes);
  }

  @override
  Future<Uint8List> readBlob(GitOid oid) async {
    final GitRunResult result = await _run(
      <String>['cat-file', GitObjectType.blob.name, oid.value],
    );
    return result.stdoutBytes;
  }

  @override
  Future<GitCommit> readCommit(GitOid oid) async {
    final GitRunResult result = await _run(
      <String>['cat-file', GitObjectType.commit.name, oid.value],
    );
    return parseCommitObject(oid, result.stdoutBytes);
  }

  @override
  Future<GitTag> readTag(GitOid oid) async {
    final GitRunResult result = await _run(
      <String>['cat-file', GitObjectType.tag.name, oid.value],
    );
    return parseTagObject(oid, result.stdoutBytes);
  }

  @override
  Future<GitTree> readTree(GitOid oid) async {
    final GitRunResult listing = await _run(<String>[
      'ls-tree',
      '-z',
      '--full-tree',
      oid.value,
    ]);
    return GitTree(oid: oid, entries: _parseTreeEntries(listing.stdout));
  }

  @override
  Future<GitOid> commitTree(
    GitOid tree,
    List<GitOid> parents,
    String message, {
    GitIdentity? author,
    GitIdentity? committer,
    DateTime? authorDate,
    DateTime? committerDate,
  }) async {
    final Map<String, String> environment = <String, String>{
      if (author != null) ...<String, String>{
        'GIT_AUTHOR_NAME': author.name,
        'GIT_AUTHOR_EMAIL': author.email,
      },
      if (committer != null) ...<String, String>{
        'GIT_COMMITTER_NAME': committer.name,
        'GIT_COMMITTER_EMAIL': committer.email,
      },
      if (authorDate != null) 'GIT_AUTHOR_DATE': formatGitDate(authorDate),
      if (committerDate != null)
        'GIT_COMMITTER_DATE': formatGitDate(committerDate),
    };
    final ProcessGitRepository view = repository.withEnvironment(environment);
    final GitRunResult result = await view.runCommand(
      <String>[
        'commit-tree',
        tree.value,
        for (final GitOid parent in parents) ...<String>['-p', parent.value],
        '-F',
        '-',
      ],
      stdin: _bytes(utf8.encode(_messageWithFinalNewline(message))),
    );
    return _parseSingleOid(result.stdout, 'commit-tree');
  }

  @override
  Stream<List<int>> archive(
    GitOid treeish, {
    GitArchiveFormat format = GitArchiveFormat.tar,
  }) {
    return _archive(<String>[
      'archive',
      '--format=${format.name}',
      treeish.value,
    ]);
  }

  /// Streams the standard output of [arguments], reading through the
  /// repository's streaming launcher.
  ///
  /// Cancelling the subscription stops the process; descendants that outlive
  /// it may keep running. A non-zero exit is reported as
  /// [GitCommandException] once its error output is read; that output is
  /// bounded to its most recent 16 MiB, so an endless stream cannot grow
  /// memory without bound.
  Stream<List<int>> _archive(List<String> arguments) async* {
    final GitLaunchedProcess process = await repository.launcher.start(
      GitProcessLaunchRequest(
        arguments: arguments,
        workingDirectory: repository.context.path,
        environment: repository.context.environment,
      ),
    );
    final TailByteBuffer stderr = TailByteBuffer();
    final Completer<void> stderrDone = Completer<void>();
    final stderrSubscription = process.stderr.listen(
      stderr.add,
      onError: (Object _) {},
      onDone: stderrDone.complete,
    );
    var finished = false;
    try {
      await for (final List<int> chunk in process.stdout) {
        yield chunk;
      }
      final int exitCode = await process.exitCode;
      await stderrDone.future;
      finished = true;
      if (exitCode != 0) {
        throw GitCommandException(
          arguments: arguments,
          workingDirectory: repository.context.path,
          exitCode: exitCode,
          stderr: utf8.decode(stderr.takeBytes(), allowMalformed: true),
        );
      }
    } finally {
      if (!finished) {
        await process.kill();
      }
      await stderrSubscription.cancel();
    }
  }

  /// [message] with one final newline, which is what a commit stores.
  static String _messageWithFinalNewline(String message) {
    return message.endsWith('\n') ? message : '$message\n';
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

  /// Parses the NUL-separated records of `ls-tree -z`.
  ///
  /// Each record is `<mode> SP <type> SP <oid> TAB <path>`.
  static List<GitTreeEntry> _parseTreeEntries(String output) {
    final List<GitTreeEntry> entries = <GitTreeEntry>[];
    for (final String record in output.split('\x00')) {
      if (record.isEmpty) {
        continue;
      }
      final int tab = record.indexOf('\t');
      if (tab < 0) {
        throw FormatException('Unexpected ls-tree record: "$record"', record);
      }
      final List<String> fields = record.substring(0, tab).split(' ');
      if (fields.length != 3) {
        throw FormatException('Unexpected ls-tree record: "$record"', record);
      }
      final GitObjectType? type = GitObjectType.tryParse(fields[1]);
      final GitOid? oid = GitOid.tryParse(fields[2]);
      if (type == null || oid == null) {
        throw FormatException('Unexpected ls-tree record: "$record"', record);
      }
      entries.add(GitTreeEntry(
        mode: fields[0],
        type: type,
        oid: oid,
        path: record.substring(tab + 1),
      ));
    }
    return entries;
  }

  /// Encodes [bytes] for standard input.
  static Uint8List _bytes(List<int> bytes) => Uint8List.fromList(bytes);
}
