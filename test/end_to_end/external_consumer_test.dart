@Tags(['git'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// Source of the external consumer: it imports only the two public entry
/// points a production application needs, creates a repository, commits a file
/// and reads the commit back.
const String _consumerSource = r'''
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main(List<String> arguments) async {
  final String repositoryPath = arguments.single;
  final File globalConfig = File('${repositoryPath}_gitconfig');
  await globalConfig.writeAsString('');
  final ProcessGitEngine engine = ProcessGitEngine(
    globalEnvironment: <String, String>{
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': globalConfig.path,
    },
  );
  final GitWorkingRepository repository = await engine.init(
    repositoryPath,
    initialBranch: 'main',
  );
  await repository.config.set('user.name', 'External Consumer');
  await repository.config.set('user.email', 'consumer@example.com');
  await File('${repositoryPath}/notes.txt').writeAsString('external consumer\n');
  await repository.worktree.addAll();
  final GitOid commit = await repository.worktree.commit(
    'external consumer commit',
  );
  final GitCommit read = await repository.objects.readCommit(commit);
  print('message: ${read.message}');
  print('author: ${read.author.name}');
}
''';

void main() {
  test(
    'an external package drives the engine through the public entry points',
    () async {
      final Directory sandbox = await Directory.systemTemp.createTemp(
        'git_engine_external_consumer_',
      );
      addTearDown(() => _deleteRecursively(sandbox));

      final Directory consumer = Directory(_join(sandbox.path, 'consumer'));
      await consumer.create();
      await File(
        _join(consumer.path, 'pubspec.yaml'),
      ).writeAsString(_pubspec());
      final Directory bin = Directory(_join(consumer.path, 'bin'));
      await bin.create();
      await File(
        _join(bin.path, 'main.dart'),
      ).writeAsString(_consumerSource);

      final ProcessResult resolved = await Process.run(
        Platform.resolvedExecutable,
        const <String>['pub', 'get', '--offline'],
        workingDirectory: consumer.path,
      );
      expect(
        resolved.exitCode,
        0,
        reason: 'pub get failed\nstdout:\n${resolved.stdout}\n'
            'stderr:\n${resolved.stderr}',
      );

      final String repositoryPath = _join(sandbox.path, 'repository');
      final ProcessResult run = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', 'bin/main.dart', repositoryPath],
        workingDirectory: consumer.path,
      );
      expect(
        run.exitCode,
        0,
        reason: 'the external consumer failed\nstdout:\n${run.stdout}\n'
            'stderr:\n${run.stderr}',
      );
      expect(run.stdout, contains('message: external consumer commit'));
      expect(run.stdout, contains('author: External Consumer'));
      expect(Directory(repositoryPath).existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// The consumer's pubspec: a path dependency on this package and nothing else.
String _pubspec() {
  final String packagePath = Directory.current.absolute.path.replaceAll(
    '\\',
    '/',
  );
  return '''
name: git_engine_external_consumer
version: 1.0.0
publish_to: none
environment:
  sdk: ^3.3.0
dependencies:
  git_engine:
    path: "$packagePath"
''';
}

/// Joins [base] and [relative] with the platform separator.
String _join(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}

/// Deletes [directory], retrying while Windows may still hold a handle.
Future<void> _deleteRecursively(Directory directory) async {
  for (var attempt = 0;; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt >= 4) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
