import 'dart:convert';
import 'dart:io';

import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart' show ProcessGitEngine;
import '../../../backends/process/support/process_backend_types.dart'
    show ProcessGitRunner;
import 'package:test/test.dart';

/// A throwaway workspace holding bare repositories and their clones, sealed
/// off from the machine's git configuration.
///
/// Every repository inside inherits the fixed identity, the default branch
/// `main` and `core.autocrlf=false` from the sandbox's own global
/// configuration file.
final class LandingSandbox {
  LandingSandbox._({
    required this.root,
    required this.engine,
  });

  /// Root directory of the sandbox; every repository lives inside it.
  final Directory root;

  /// Engine building and opening the repositories of the sandbox, and
  /// carrying the fetch and push exchanges between them.
  final ProcessGitEngine engine;

  /// Creates a sandbox whose disposal is registered with the current test.
  static Future<LandingSandbox> create() async {
    final Directory root = await Directory.systemTemp.createTemp('landing_ws_');
    final File globalConfig = File(sandboxPath(root.path, 'gitconfig-global'));
    await globalConfig.writeAsString(_globalConfig);
    final ProcessGitRunner runner = ProcessGitRunner(
      globalEnvironment: <String, String>{
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': globalConfig.path,
      },
    );
    final LandingSandbox sandbox = LandingSandbox._(
      root: root,
      engine: ProcessGitEngine(runner: runner),
    );
    addTearDown(sandbox.dispose);
    return sandbox;
  }

  /// Absolute path of [relative] inside the sandbox.
  String path(String relative) => sandboxPath(root.path, relative);

  /// Initializes an empty bare repository named [name] in the sandbox.
  Future<GitFileBareRepository> initBare(
    String name, {
    String? initialBranch,
  }) {
    return engine.initBare(path(name), initialBranch: initialBranch);
  }

  /// Clones [source] into the sandbox as [name].
  Future<GitWorkingRepository> clone(String source, String name) {
    return engine.clone(source, path(name));
  }

  /// Deletes the sandbox, retrying while the system may still hold file
  /// locks right after git exits.
  Future<void> dispose() async {
    for (var attempt = 0;; attempt++) {
      try {
        await root.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 4) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}

/// Writes [content] into [relative] of the work tree at [repoPath].
void writeFile(String repoPath, String relative, String content) {
  final File file = File(sandboxPath(repoPath, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

/// Content of [relative] in the work tree at [repoPath].
String readFile(String repoPath, String relative) {
  return File(sandboxPath(repoPath, relative)).readAsStringSync();
}

/// Whether [relative] exists in the work tree at [repoPath].
bool fileExists(String repoPath, String relative) {
  return File(sandboxPath(repoPath, relative)).existsSync();
}

/// Stages every change of [repository] and commits it as [message].
Future<GitOid> commitAll(
  GitWorkingRepository repository,
  String message,
) async {
  await repository.worktree.addAll();
  return repository.worktree.commit(message);
}

/// Resolves [rev] in [repository], failing the test when it names nothing.
Future<GitOid> resolve(GitRepository repository, String rev) async {
  final GitOid? oid = await repository.revisions.resolveRevision(rev);
  if (oid == null) {
    fail('revision "$rev" does not resolve');
  }
  return oid;
}

/// Parents of the commit [rev] names in [repository].
Future<List<GitOid>> parentsOf(GitRepository repository, String rev) async {
  final GitOid oid = await resolve(repository, rev);
  return (await repository.objects.readCommit(oid)).parents;
}

/// Names of every branch of [repository], the `refs/heads/` prefix stripped,
/// sorted.
Future<List<String>> branchNames(GitRepository repository) async {
  final List<GitRef> refs = await repository.refs.listRefs(
    prefix: 'refs/heads/',
  );
  return refs
      .map((GitRef ref) => ref.name.substring('refs/heads/'.length))
      .toList()
    ..sort();
}

/// Content of [path] as [ref] names it in [repository], or null when the
/// path does not exist there.
Future<String?> contentAt(
  GitRepository repository,
  String ref,
  String path,
) async {
  final GitOid? blob = await repository.revisions.resolveRevision('$ref:$path');
  if (blob == null) {
    return null;
  }
  return utf8.decode(await repository.objects.readBlob(blob));
}

/// A working clone of a bare repository used to advance its branches, the
/// way another writer would between two attempts.
final class RemoteWriter {
  RemoteWriter._(this._clone, this._engine);

  final GitWorkingRepository _clone;
  final ProcessGitEngine _engine;

  /// Creates a writer clone of [barePath] inside [sandbox] as [name].
  static Future<RemoteWriter> create(
    LandingSandbox sandbox,
    String barePath,
    String name,
  ) async {
    final GitWorkingRepository clone = await sandbox.clone(
      barePath,
      name,
    );
    return RemoteWriter._(clone, sandbox.engine);
  }

  /// Writes [files], commits them on [branch] and pushes the branch onto the
  /// bare repository, creating the branch at the work commit when the remote
  /// does not hold it yet. Returns the tip the branch holds afterwards.
  Future<GitOid> commitOnBranch(
    String branch,
    Map<String, String> files,
    String message,
  ) async {
    await _engine.fetch(_clone, remote: 'origin');
    final GitOid? remoteTip = await _clone.revisions.resolveRevision(
      'refs/remotes/origin/$branch',
    );
    await _clone.worktree.checkoutNewBranch(
      branch,
      startPoint: remoteTip?.value,
      resetIfExists: true,
    );
    files.forEach((String relative, String content) {
      writeFile(_clone.path, relative, content);
    });
    final GitOid commit = await commitAll(_clone, message);
    await _engine.push(
      _clone,
      remote: 'origin',
      refspecs: <String>['HEAD:refs/heads/$branch'],
    );
    return commit;
  }
}

/// Configuration every repository of every sandbox inherits.
const String _globalConfig = '''
[user]
	name = Landing Tests
	email = landing-tests@example.com
[init]
	defaultBranch = main
[core]
	autocrlf = false
''';

/// Joins [base] and [relative] with the platform separator.
String sandboxPath(String base, String relative) {
  final String separator = Platform.pathSeparator;
  return base.endsWith(separator)
      ? '$base$relative'
      : '$base$separator$relative';
}
