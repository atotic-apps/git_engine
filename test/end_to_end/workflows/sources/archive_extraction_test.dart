@Tags(['git'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import 'sources_support.dart';

/// Extracting the tip of a bare origin by archive, and what happens when
/// there is nothing to extract.
void main() {
  late SourcesSandbox sandbox;

  setUp(() async {
    sandbox = await createSourcesSandbox();
  });

  test('the whole tip of a bare origin is extracted as a tar', () async {
    final String originPath = sandbox.path('origin.git');
    await sandbox.engine.initBare(originPath, initialBranch: 'main');
    await sandbox.pushTip(
      originPath,
      branch: 'main',
      files: <String, String>{
        'docs/spec.md': '# spec\n',
        'top.md': '# top\n',
      },
      message: 'seed the origin',
    );
    final GitFileBareRepository origin =
        await sandbox.engine.openBare(originPath);
    final String tarPath = sandbox.path('tip.tar');
    final GitOid tip = (await origin.revisions.resolveRevision('main'))!;

    final Uint8List archive = await _collect(origin.objects.archive(tip));
    File(tarPath).writeAsBytesSync(archive);

    final Map<String, String> contents = <String, String>{
      for (final TarFileEntry entry
          in readTarFiles(File(tarPath).readAsBytesSync()))
        entry.name: entry.text,
    };
    expect(contents, <String, String>{
      'docs/spec.md': '# spec\n',
      'top.md': '# top\n',
    });
  });

  test('an unborn branch or a missing repository yields no extraction',
      () async {
    final GitFileBareRepository empty = await sandbox.engine
        .initBare(sandbox.path('empty.git'), initialBranch: 'main');

    await expectLater(
      empty.objects.archive(GitOid.parse('0' * 40)),
      emitsError(isA<GitException>()),
    );
    // A directory that exists but holds no repository is not an origin; a
    // path that does not exist at all is not one either.
    Directory(sandbox.path('plain')).createSync();
    await expectLater(
      sandbox.engine.open(sandbox.path('plain')),
      throwsA(isA<GitNotARepositoryException>()),
    );
    await expectLater(
      sandbox.engine.open(sandbox.path('nowhere')),
      throwsA(isA<GitException>()),
    );
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
