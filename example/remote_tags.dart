/// Fetches lightweight and annotated tags over public HTTPS.
/// Uses the official standalone archive of Dart's args library, which has
/// both lightweight and annotated release tags.
/// No account or remote write access is needed. The temporary bare repo is
/// removed afterwards.
///
/// Shows GitTagFetch.none versus all, lists the received refs, reads the
/// annotated tag's message and checks that every tag target was downloaded.
/// Run separately from the offline examples because it needs the internet:
///
///     dart run example/remote_tags.dart
library;

import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main() async {
  const String source = 'https://github.com/dart-archive/args.git';
  final Directory sandbox =
      await Directory.systemTemp.createTemp('git_engine_remote_tags_');
  try {
    final ProcessGitEngine engine = ProcessGitEngine();
    final GitFileClient client = engine;
    final GitFileBareRepository repository = await engine.initBare(
      '${sandbox.path}${Platform.pathSeparator}repository.git',
      initialBranch: 'main',
    );
    await repository.remotes.add('origin', source);
    print('Source: $source');

    await client.fetch(repository, remote: 'origin', tags: GitTagFetch.none);
    if ((await repository.tags.list()).isNotEmpty) {
      throw StateError('Fetching with tags: none unexpectedly created tags.');
    }
    print('fetch(tags: none): no tag refs created');

    await client.fetch(repository, remote: 'origin', tags: GitTagFetch.all);
    final List<GitTagRef> tags = await repository.tags.list();
    if (!tags.any((GitTagRef tag) => tag.isAnnotated) ||
        !tags.any((GitTagRef tag) => !tag.isAnnotated)) {
      throw StateError('Expected both annotated and lightweight tags.');
    }
    final int annotated = tags.where((GitTagRef tag) => tag.isAnnotated).length;
    print('fetch(tags: all): ${tags.length} tags received '
        '($annotated annotated, ${tags.length - annotated} lightweight)');
    for (final GitTagRef ref in tags) {
      final GitOid? peeled = await repository.revisions
          .resolveRevision('refs/tags/${ref.name}^{}');
      if (peeled != ref.target ||
          !await repository.objects.objectExists(ref.target)) {
        throw StateError('Missing or incorrect target for ${ref.name}.');
      }
      final GitObjectType? type =
          await repository.objects.objectType(ref.target);
      print('${ref.name}: ${ref.isAnnotated ? 'annotated' : 'lightweight'} '
          '-> ${type?.name} ${ref.target.short()}');
      if (ref.isAnnotated) {
        final GitTag tag = await repository.objects.readTag(ref.oid);
        print('  message: ${tag.message}');
        print('  tagger: ${tag.tagger.name}');
      }
    }
    print('remote tag example passed');
  } finally {
    for (var attempt = 0;; attempt++) {
      try {
        await sandbox.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt >= 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    print('temporary directory removed');
  }
}
