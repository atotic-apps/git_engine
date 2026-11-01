@Tags(['git'])
library;

import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/test_repository.dart';
import 'objects_test_support.dart';

void main() {
  test('archives a subdirectory of a bare repository as tar', () async {
    final TestRepository repo = await createTestRepository();
    await commitFile(repo, 'docs/guide.txt', 'the guide\n', 'add guide');
    await commitFile(
      repo,
      'docs/accent/café.txt',
      'accented content\n',
      'add accented',
    );
    await commitFile(repo, 'root.txt', 'root\n', 'add root');

    final String bare = await createBareClone(repo, 'bare.git');
    final ProcessGitRepository repository =
        await openRepository(repo, directory: bare);
    final GitOid docs = GitOid.parse(await oidOf(repo, 'HEAD:docs'));

    final Uint8List bytes = await _collect(
      repository.objects.archive(docs, format: GitArchiveFormat.tar),
    );
    final List<TarEntry> entries = readTar(bytes);
    final Map<String, String> contents = <String, String>{
      for (final TarEntry entry in entries) entry.name: entry.text,
    };

    expect(contents.keys.toSet(), <String>{
      'guide.txt',
      'accent/café.txt',
    });
    expect(contents['guide.txt'], 'the guide\n');
    expect(contents['accent/café.txt'], 'accented content\n');
  });
}

/// Collects [stream] into one byte buffer.
Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
