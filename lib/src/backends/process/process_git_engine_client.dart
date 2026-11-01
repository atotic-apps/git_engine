part of 'process_git_engine.dart';

mixin _ProcessGitFileClient on _ProcessGitTransport implements GitFileClient {
  Future<GitWorkingRepository> openWorking(String path);

  Future<GitFileBareRepository> openBare(String path);

  @override
  Future<GitWorkingRepository> clone(
    String source,
    String target, {
    bool noCheckout = false,
    String? branch,
  }) async {
    await _clone(source, target, noCheckout: noCheckout, branch: branch);
    return openWorking(target);
  }

  @override
  Future<GitFileBareRepository> cloneBare(
    String source,
    String target,
  ) async {
    await _clone(source, target, bare: true);
    return openBare(target);
  }

  @override
  Future<void> fetch(
    GitFileRepository repository, {
    String? remote,
    List<String>? refspecs,
    bool prune = false,
    GitTagFetch tags = GitTagFetch.follow,
  }) async {
    await _fetch(
      repository,
      remote: remote,
      refspecs: refspecs,
      prune: prune,
      tags: tags,
    );
  }

  /// Fetches [refspecs] from [remote] like [fetch], and returns the object
  /// name of the branch the refspecs obtained when [readFetchedOid] asks for
  /// it.
  ///
  /// That object name is read right after the branch fetch and before the
  /// tags are fetched, so a tag naming another commit cannot replace it.
  Future<GitOid?> _fetch(
    GitFileRepository repository, {
    String? remote,
    List<String>? refspecs,
    bool prune = false,
    GitTagFetch tags = GitTagFetch.follow,
    bool readFetchedOid = false,
  }) async {
    final List<String> refspecList = refspecs ?? const <String>[];
    if (refspecList.isNotEmpty && remote == null) {
      throw ArgumentError.value(
        refspecList,
        'refspecs',
        'require a remote, otherwise nothing would be fetched',
      );
    }
    if (remote != null) {
      classifyRemoteLocation(remote);
    }
    if (tags == GitTagFetch.follow && refspecList.isNotEmpty) {
      return _fetchAndFollowTags(
        repository,
        remote!,
        refspecList,
        prune,
        readFetchedOid: readFetchedOid,
      );
    }
    await _exchange(repository, <String>[
      'fetch',
      ..._tagFetchArguments(tags),
      if (prune) '--prune',
      if (remote != null) ...<String>['--', remote],
      ...refspecList,
    ]);
    return null;
  }

  @override
  Future<void> push(
    GitFileRepository repository, {
    String? remote,
    List<String>? refspecs,
    bool force = false,
    bool tags = false,
    bool setUpstream = false,
  }) async {
    final List<String> refspecList = refspecs ?? const <String>[];
    if (refspecList.isNotEmpty && remote == null) {
      throw ArgumentError.value(
        refspecList,
        'refspecs',
        'require a remote, otherwise nothing would be pushed',
      );
    }
    final List<String> effectiveRefspecs = setUpstream
        ? await _setUpstreamRefspecs(repository, remote, refspecList)
        : refspecList;
    if (remote != null) {
      classifyRemoteLocation(remote);
    }
    await _exchange(repository, <String>[
      'push',
      if (force) '--force',
      if (tags) '--tags',
      if (setUpstream) '--set-upstream',
      if (remote != null) ...<String>['--', remote],
      ...effectiveRefspecs,
    ]);
  }

  @override
  Future<GitMergeResult> pull(
    GitWorkingRepository repository, {
    String? remote,
    String? branch,
    GitMergeMode mode = GitMergeMode.auto,
  }) async {
    if (branch != null && remote == null) {
      throw ArgumentError.value(
        branch,
        'branch',
        'requires a remote, otherwise nothing would be fetched',
      );
    }
    String pullRemote = remote ?? '';
    String pullBranch = branch ?? '';
    if (branch == null) {
      final String? current = await repository.branches.current();
      if (current == null) {
        throw GitNoUpstreamException(
          'HEAD is detached; name the remote and the branch to pull',
        );
      }
      if (remote == null) {
        final String? configuredRemote =
            await repository.config.get('branch.$current.remote');
        final String? mergeRef =
            await repository.config.get('branch.$current.merge');
        if (configuredRemote == null || mergeRef == null) {
          throw GitNoUpstreamException(
            'branch "$current" has no upstream; name the remote and the '
            'branch to pull',
          );
        }
        pullRemote = configuredRemote;
        pullBranch = _upstreamBranchOf(mergeRef);
      } else {
        pullBranch = current;
      }
    }
    final GitOid? fetched = await _fetch(
      repository,
      remote: pullRemote,
      refspecs: <String>[pullBranch],
      readFetchedOid: true,
    );
    final String trackingRef = 'refs/remotes/$pullRemote/$pullBranch';
    final GitOid? tracking =
        await repository.revisions.resolveRevision(trackingRef);
    final String revision;
    if (fetched == null) {
      revision = tracking != null ? trackingRef : 'FETCH_HEAD';
    } else if (tracking == fetched) {
      revision = trackingRef;
    } else {
      revision = fetched.value;
    }
    return repository.merge.merge(revision, mode: mode);
  }

  /// The arguments a fetch carries for [tags]: nothing for the default
  /// follow behavior, every tag, or no tag.
  static List<String> _tagFetchArguments(GitTagFetch tags) {
    return switch (tags) {
      GitTagFetch.follow => const <String>[],
      GitTagFetch.all => const <String>['--tags'],
      GitTagFetch.none => const <String>['--no-tags'],
    };
  }

  /// Fetches explicit [refspecs] from [remote] and then the tags that
  /// designate the commits the fetch retrieved; returns the object name of
  /// the branch the refspecs obtained when [readFetchedOid] asks for it,
  /// read before the tag fetch.
  ///
  /// A fetch restricted by refspecs brings no tag of its own, whatever the
  /// history it downloads. The tags of the remote are listed once the fetch
  /// ran, and the ones whose target the fetch deposited in the repository
  /// are fetched by name afterwards.
  Future<GitOid?> _fetchAndFollowTags(
    GitFileRepository repository,
    String remote,
    List<String> refspecs,
    bool prune, {
    required bool readFetchedOid,
  }) async {
    await _exchange(repository, <String>[
      'fetch',
      '--no-tags',
      if (prune) '--prune',
      '--',
      remote,
      ...refspecs,
    ]);
    final GitOid? fetched = readFetchedOid
        ? await repository.revisions.resolveRevision('FETCH_HEAD')
        : null;
    final Map<String, String> tagTargets =
        await _remoteTagTargets(repository, remote);
    if (tagTargets.isEmpty) {
      return fetched;
    }
    final Set<String> present =
        await _objectsInRepository(repository, tagTargets.values.toSet());
    final List<String> tagRefs = <String>[
      for (final MapEntry<String, String> tag in tagTargets.entries)
        if (present.contains(tag.value)) '${tag.key}:${tag.key}',
    ];
    if (tagRefs.isNotEmpty) {
      await _exchange(repository, <String>[
        'fetch',
        '--no-tags',
        '--',
        remote,
        ...tagRefs,
      ]);
    }
    return fetched;
  }

  /// The tags [remote] holds, each mapped to the object it designates: the
  /// peeled object of an annotated tag, the tag reference itself for a
  /// lightweight one.
  Future<Map<String, String>> _remoteTagTargets(
    GitFileRepository repository,
    String remote,
  ) async {
    final GitRunResult listing = await _exchange(repository, <String>[
      'ls-remote',
      '--tags',
      '--',
      remote,
    ]);
    final Map<String, String> targets = <String, String>{};
    for (final String line in listing.stdout.split('\n')) {
      final int separator = line.indexOf('\t');
      if (separator <= 0) {
        continue;
      }
      String name = line.substring(separator + 1);
      if (name.endsWith('^{}')) {
        name = name.substring(0, name.length - 3);
      }
      targets[name] = line.substring(0, separator);
    }
    return targets;
  }

  /// The object names of [oids] the repository holds, asked of one
  /// `cat-file --batch-check` reading them on its standard input.
  Future<Set<String>> _objectsInRepository(
    GitFileRepository repository,
    Set<String> oids,
  ) async {
    if (oids.isEmpty) {
      return const <String>{};
    }
    final GitRunResult listing = await _process(repository).runCommand(
      const <String>['cat-file', '--batch-check'],
      stdin: Uint8List.fromList(utf8.encode('${oids.join('\n')}\n')),
    );
    final Set<String> present = <String>{};
    for (final String line in listing.stdout.split('\n')) {
      if (line.isEmpty || line.endsWith(' missing')) {
        continue;
      }
      final int separator = line.indexOf(' ');
      if (separator > 0) {
        present.add(line.substring(0, separator));
      }
    }
    return present;
  }

  /// The refspecs a push with an upstream to set carries: the local branch
  /// they designate, or the checked out branch when none is given — pushed
  /// by name to [remote] when one is named, and otherwise left to the remote
  /// choice of the repository configuration. A push whose refspecs do not
  /// designate exactly one local branch, and a detached `HEAD` without
  /// refspecs, is refused before git runs.
  Future<List<String>> _setUpstreamRefspecs(
    GitFileRepository repository,
    String? remote,
    List<String> refspecs,
  ) async {
    if (refspecs.length > 1) {
      throw ArgumentError.value(
        refspecs,
        'refspecs',
        'setUpstream requires them to designate exactly one local branch',
      );
    }
    if (refspecs.isEmpty) {
      final String? current = await repository.branches.current();
      if (current == null) {
        throw ArgumentError.value(
          repository,
          'repository',
          'HEAD is detached, so no local branch follows the remote; name '
              'the branch with refspecs',
        );
      }
      return remote == null ? refspecs : <String>[current];
    }
    final String? branch = _localBranchOfRefspec(refspecs.single);
    if (branch == null) {
      throw ArgumentError.value(
        refspecs,
        'refspecs',
        'setUpstream requires them to designate exactly one local branch',
      );
    }
    if (!await repository.refs.exists('refs/heads/$branch')) {
      throw ArgumentError.value(
        refspecs,
        'refspecs',
        'no local branch "$branch" for setUpstream to record',
      );
    }
    return refspecs;
  }

  /// The local branch [refspec] pushes, or null when it names none: the
  /// source side of `src` or `src:destination`, with an optional leading
  /// `+`, spelled `refs/heads/<name>` or `<name>`, never a revision
  /// expression, a pattern or a remote destination alone.
  static String? _localBranchOfRefspec(String refspec) {
    String source = refspec;
    if (source.startsWith('+')) {
      source = source.substring(1);
    }
    final int colon = source.indexOf(':');
    if (colon >= 0) {
      source = source.substring(0, colon);
    }
    const String prefix = 'refs/heads/';
    if (source.startsWith(prefix)) {
      source = source.substring(prefix.length);
    }
    if (source.isEmpty ||
        source.startsWith('@{') ||
        const <String>['~', '^', ':', '*', '?', '['].any(source.contains)) {
      return null;
    }
    return source;
  }

  /// The branch name of an upstream `branch.<name>.merge` value: the part
  /// after its `refs/heads/` prefix, the value itself when it carries none.
  static String _upstreamBranchOf(String mergeRef) {
    const String prefix = 'refs/heads/';
    return mergeRef.startsWith(prefix)
        ? mergeRef.substring(prefix.length)
        : mergeRef;
  }

  /// Runs `git clone` with [source] validated first; [bare], [noCheckout]
  /// and [branch] refine the clone. The bounding transport environment
  /// always applies, the no-prompt connection environment applies when
  /// [source] may open an SSH connection, and connection failures are
  /// typed.
  Future<void> _clone(
    String source,
    String target, {
    bool bare = false,
    bool noCheckout = false,
    String? branch,
  }) async {
    final GitRemoteTransport transport = classifyRemoteLocation(source);
    try {
      await _runner.run(GitRunRequest(
        arguments: <String>[
          'clone',
          if (branch != null) '--branch=$branch',
          if (bare) '--bare',
          if (noCheckout) '--no-checkout',
          '--',
          source,
          target,
        ],
        environment: <String, String>{
          ...await _connectionEnvironment(
            mayUseSsh: transportMayUseSsh(transport),
            commandRunner: _runner,
          ),
          ...transportEnvironment,
        },
      ));
    } on GitCommandException catch (error) {
      final GitException? classified = GitRemoteFailure.classify(error);
      if (classified != null) {
        throw classified;
      }
      rethrow;
    }
  }
}
