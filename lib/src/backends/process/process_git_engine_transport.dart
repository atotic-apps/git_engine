part of 'process_git_engine.dart';

mixin _ProcessGitTransport {
  GitRunner get _runner;

  GitPlatform get _platform;

  /// Environment of a clone, fetch or push supplying non-interactive SSH
  /// defaults: the askpass fallback is disabled, and a default
  /// SSH command refusing to prompt is added unless the user chose one —
  /// in the platform environment, the runner's global environment, the
  /// repository context, or a configuration file. [mayUseSsh] is false for
  /// sources that cannot open an SSH connection, which need no environment.
  Future<Map<String, String>> _connectionEnvironment({
    required bool mayUseSsh,
    required GitRunner commandRunner,
    GitRepositoryContext? context,
  }) async {
    if (!mayUseSsh) {
      return const <String, String>{};
    }
    if (_environmentChoosesSshCommand(_platform.environment) ||
        _environmentChoosesSshCommand(_globalEnvironment()) ||
        (context != null &&
            _environmentChoosesSshCommand(context.environment))) {
      return _sshAskpassNever;
    }
    if (await _isSshCommandConfigured(commandRunner, context)) {
      return _sshAskpassNever;
    }
    return _nonInteractiveSsh;
  }

  /// Whether [environment] carries an SSH command the user chose.
  bool _environmentChoosesSshCommand(Map<String, String> environment) {
    return environment.containsKey('GIT_SSH_COMMAND') ||
        environment.containsKey('GIT_SSH');
  }

  /// Environment variables the runner layers over the process environment
  /// for every command; empty for a runner this backend does not know.
  Map<String, String> _globalEnvironment() {
    final GitRunner runner = _runner;
    return runner is ProcessGitRunner
        ? runner.globalEnvironment
        : const <String, String>{};
  }

  /// Whether a configuration file visible from [context] sets
  /// `core.sshCommand`; [context] null reads the configuration of the
  /// machine alone, as a clone does. Exit code 1 means the key is not set.
  Future<bool> _isSshCommandConfigured(
    GitRunner commandRunner,
    GitRepositoryContext? context,
  ) async {
    try {
      final GitRunResult result = await commandRunner.run(GitRunRequest(
        arguments: sshCommandProbe,
        workingDirectory: context?.path,
        environment: context?.environment ?? const <String, String>{},
      ));
      return result.stdout.trim().isNotEmpty;
    } on GitCommandException catch (error) {
      if (error.exitCode == 1) {
        return false;
      }
      rethrow;
    }
  }

  /// Disables the SSH askpass fallback; an SSH command the user chose keeps
  /// running as it is.
  static const Map<String, String> _sshAskpassNever = <String, String>{
    'SSH_ASKPASS_REQUIRE': 'never',
  };

  /// Environment for an SSH connection when the user chose no SSH command:
  /// OpenSSH's batch mode fails instead of waiting for a password, a
  /// passphrase or the acceptance of an unknown host key.
  static const Map<String, String> _nonInteractiveSsh = <String, String>{
    'GIT_SSH_COMMAND': 'ssh -oBatchMode=yes',
    'SSH_ASKPASS_REQUIRE': 'never',
  };

  /// Runs an exchange command in [repository]'s context, with the bounding
  /// transport environment and the no-prompt connection environment applied
  /// last, and types the failures git reports on its standard error: a ref
  /// the remote does not have, a push refused because it is not a
  /// fast-forward, refused or demanded credentials, an unreachable remote,
  /// and an absent remote repository. Every other failure stays as it came.
  Future<GitRunResult> _exchange(
    GitFileRepository repository,
    List<String> arguments,
  ) async {
    final ProcessGitRepository processRepository = _process(repository);
    try {
      return await processRepository.runner.run(GitRunRequest(
        arguments: arguments,
        workingDirectory: processRepository.context.path,
        environment: <String, String>{
          ...processRepository.context.environment,
          ...await _connectionEnvironment(
            mayUseSsh: true,
            commandRunner: processRepository.runner,
            context: processRepository.context,
          ),
          ...transportEnvironment,
        },
      ));
    } on GitNotARepositoryException {
      rethrow;
    } on GitCommandException catch (error) {
      if (_isRemoteRefNotFound(error.stderr)) {
        throw GitRemoteRefNotFoundException(cause: error);
      }
      if (_isRefusedNonFastForward(error.stderr)) {
        throw GitPushRejectedException(cause: error);
      }
      final GitException? classified = GitRemoteFailure.classify(error);
      if (classified != null) {
        throw classified;
      }
      rethrow;
    }
  }

  /// [repository] as the process type whose context commands must run in.
  ProcessGitRepository _process(GitFileRepository repository) {
    if (repository is ProcessGitRepository) {
      return repository;
    }
    throw ArgumentError.value(
      repository,
      'repository',
      'is not a repository of the process backend',
    );
  }

  /// Whether git said a ref the command mentioned does not exist remotely.
  ///
  /// Fetch words it as `couldn't find remote ref <ref>`; a push to a
  /// destination git cannot name ends with `unable to push to unqualified
  /// destination <ref>`. Refusals of any other kind carry other messages.
  static bool _isRemoteRefNotFound(String stderr) {
    final String text = stderr.toLowerCase();
    return text.contains("couldn't find remote ref") ||
        text.contains('unable to push to unqualified destination');
  }

  /// Whether git refused the pushed ref: because it was not a fast-forward,
  /// or because a tag already exists remotely with another value.
  ///
  /// A push onto a remote tip git cannot see in the local history is
  /// rejected as `(fetch first)`; a push whose remote tip is already
  /// known locally is rejected as `(non-fast-forward)`. Both are the
  /// same refusal to lose remote commits. A tag the remote already holds
  /// with another value is rejected as `(already exists)`.
  static bool _isRefusedNonFastForward(String stderr) {
    final String text = stderr.toLowerCase();
    return text.contains('non-fast-forward') ||
        text.contains('fetch first') ||
        text.contains('already exists');
  }
}
