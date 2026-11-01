import 'dart:convert';

import 'package:git_engine/backend.dart';
import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../git_date.dart';
import '../git_refusal.dart';
import '../git_runner.dart';
import '../process_git_repository.dart';

/// [GitTags] implementation running git through the owning process
/// repository, so every command inherits the repository context — working
/// directory and environment variables — instead of talking to the runner
/// alone.
class ProcessGitTags implements GitTags {
  /// Repository whose context every command runs in.
  final ProcessGitRepository repository;

  /// Creates the implementation running commands through [repository]'s
  /// context.
  ProcessGitTags({required this.repository});

  /// Fields of one tag record: full name, object name the reference names,
  /// kind of that object, object name after peeling (empty when the
  /// reference names no tag object).
  static const String _listFormat =
      '%(refname)%09%(objectname)%09%(objecttype)%09%(*objectname)';

  static const String _tagsPrefix = 'refs/tags/';

  @override
  Future<List<GitTagRef>> list() async {
    final GitRunResult result = await repository.runCommand(<String>[
      'for-each-ref',
      '--format=$_listFormat',
      'refs/tags',
    ]);
    return _parseTags(result.stdout);
  }

  @override
  Future<void> create(
    String name,
    GitOid target, {
    String? message,
    GitIdentity? tagger,
    DateTime? date,
    bool force = false,
  }) async {
    checkTagName(name);
    // A tag object records its tagger as git records a committer, so the
    // identity and the date cross to git through the committer variables.
    final Map<String, String> environment = <String, String>{
      if (tagger != null) ...<String, String>{
        'GIT_COMMITTER_NAME': tagger.name,
        'GIT_COMMITTER_EMAIL': tagger.email,
      },
      if (date != null) 'GIT_COMMITTER_DATE': formatGitDate(date),
    };
    final ProcessGitRepository view = environment.isEmpty
        ? repository
        : repository.withEnvironment(environment);
    try {
      await view.runCommand(<String>[
        'tag',
        if (force) '--force',
        if (message != null) ...<String>['--annotate', '--message', message],
        '--',
        name,
        target.value,
      ]);
    } on GitCommandException catch (error) {
      final GitException refusal = refExistsFailure(error, name);
      if (refusal is! GitCommandException) {
        throw refusal;
      }
      throw unknownRevisionFailure(error, target.value);
    }
  }

  @override
  Future<void> delete(String name) async {
    checkTagName(name);
    try {
      await repository.runCommand(<String>['tag', '--delete', '--', name]);
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException catch (error) {
      throw tagNotFoundFailure(error, name);
    }
  }

  /// Removes [prefix] from the start of [ref], leaving [ref] unchanged when
  /// it does not start with it.
  static String _withoutPrefix(String ref, String prefix) =>
      ref.startsWith(prefix) ? ref.substring(prefix.length) : ref;

  /// Parses the tab-separated `for-each-ref` records of a tag listing.
  static List<GitTagRef> _parseTags(String output) {
    final List<GitTagRef> tags = <GitTagRef>[];
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
      final GitObjectType? type = GitObjectType.tryParse(fields[2].trim());
      if (type == null) {
        throw FormatException(
          'Unexpected for-each-ref object type in: "$line"',
          line,
        );
      }
      final bool annotated = type == GitObjectType.tag;
      final GitOid? peeled = GitOid.tryParse(fields[3].trim());
      if (annotated && peeled == null) {
        throw FormatException(
          'Unexpected for-each-ref peeled object name in: "$line"',
          line,
        );
      }
      tags.add(GitTagRef(
        name: _withoutPrefix(fields[0].trim(), _tagsPrefix),
        oid: oid,
        target: annotated ? peeled! : oid,
        isAnnotated: annotated,
      ));
    }
    return tags;
  }
}
