import 'dart:async';

import 'package:git_engine/git_engine.dart';
import '../git_process_launcher.dart';
import '../process_git_process_launcher.dart';
import '../process_git_runner.dart';
import 'process_upload_pack_exchange.dart';

/// [GitUploadPackService] of the process backend: every operation launches
/// `git upload-pack --stateless-rpc` on the git directory the backend's own
/// resolution gives for the served identifier.
///
/// The service is built with four things: the backend's resolution, the
/// launcher of its streaming processes, the inactivity delay and the buffer
/// size.
///
/// - The resolution is a
///   `FutureOr<GitFileBareRepository?> Function(GitServedRepositoryId)`,
///   possibly asynchronous — the host may consult a catalog before the
///   repository is opened. Returning null means the identifier is unknown,
///   which surfaces as [GitUnknownServedRepositoryException]; the smart
///   HTTP processing answers 404 for it.
/// - The launcher starts the real git executable with the hardened command
///   line and environment of the backend; hand a
///   [ProcessGitProcessLauncher] built on the runner the rest of the
///   application uses.
/// - The inactivity delay releases an exchange no byte moves in — a
///   response never listened to included — by killing the process.
/// - The buffer size bounds the memory held for one exchange, independent
///   of the size of the bodies: chunks written to git are split to it, and
///   the standard error git produces is kept within it, never sent to the
///   client.
///
/// The protocol parameters cross to git through the `GIT_PROTOCOL`
/// variable and nothing else: every entry is validated before the launch,
/// and no other variable and no command-line option ever comes from the
/// request.
/// {@category Server}
final class ProcessGitUploadPackService implements GitUploadPackService {
  /// Entries a protocol negotiation may carry, as git receives them
  /// through `GIT_PROTOCOL`: a name of letters, digits, `-` or `_`,
  /// optionally followed by `=` and a value that may also carry `.` and
  /// `/`.
  static final RegExp _protocolEntry = RegExp(
    r'^[A-Za-z0-9_-]+(=[A-Za-z0-9_./-]+)?$',
  );

  final FutureOr<GitFileBareRepository?> Function(GitServedRepositoryId)
      _resolveRepository;
  final GitProcessLauncher _launcher;
  final Duration _inactivityTimeout;
  final int _bufferBytes;

  /// Creates the service resolving served identifiers with
  /// [resolveRepository], launching git through [launcher], releasing idle
  /// exchanges after [inactivityTimeout] and holding at most [bufferBytes]
  /// bytes per exchange.
  ///
  /// When no [launcher] is given, the service builds one on a
  /// [ProcessGitRunner] launching [executable] with [globalEnvironment]
  /// layered over the inherited environment, so a caller needs no runner of
  /// its own. Giving [executable] or [globalEnvironment] together with a
  /// [launcher] raises an [ArgumentError] naming the extra parameter, since
  /// the launcher already carries its runner.
  ///
  /// [inactivityTimeout] and [bufferBytes] must be positive.
  ProcessGitUploadPackService({
    required FutureOr<GitFileBareRepository?> Function(GitServedRepositoryId)
        resolveRepository,
    GitProcessLauncher? launcher,
    String executable = 'git',
    Map<String, String>? globalEnvironment,
    required Duration inactivityTimeout,
    required int bufferBytes,
  })  : _resolveRepository = resolveRepository,
        _launcher = launcher ??
            ProcessGitProcessLauncher(
              runner: ProcessGitRunner(
                executable: executable,
                globalEnvironment: globalEnvironment,
              ),
            ),
        _inactivityTimeout = inactivityTimeout,
        _bufferBytes = bufferBytes {
    if (launcher != null && executable != 'git') {
      throw ArgumentError.value(
        executable,
        'executable',
        'cannot be given with a launcher, which carries its own runner',
      );
    }
    if (launcher != null && globalEnvironment != null) {
      throw ArgumentError.value(
        globalEnvironment,
        'globalEnvironment',
        'cannot be given with a launcher, which carries its own runner',
      );
    }
    if (inactivityTimeout <= Duration.zero) {
      throw ArgumentError.value(
        inactivityTimeout,
        'inactivityTimeout',
        'must be positive',
      );
    }
    if (bufferBytes <= 0) {
      throw ArgumentError.value(bufferBytes, 'bufferBytes', 'must be positive');
    }
  }

  /// Produces the first response of the protocol by launching
  /// `git upload-pack --stateless-rpc --advertise-refs` on the resolved
  /// git directory.
  ///
  /// In protocol v0/v1 the body advertises the references; in v2 it
  /// announces the capabilities, and the references come through the
  /// `ls-refs` command of a later [uploadPack] request.
  @override
  Future<GitServiceResponse> advertiseRefs(
    GitServedRepositoryId repository, {
    required GitProtocolParameters protocol,
  }) async {
    final String gitDir = await _gitDirOf(repository);
    final List<String> arguments = <String>[
      'upload-pack',
      '--stateless-rpc',
      '--advertise-refs',
      gitDir,
    ];
    final GitLaunchedProcess process = await _launch(arguments, protocol);
    // The advertisement reads no input: close stdin so git sees an end of
    // stream instead of a writer that never comes.
    unawaited(process.closeStdin());
    return ProcessUploadPackExchange(
      process: process,
      arguments: arguments,
      inactivityTimeout: _inactivityTimeout,
      bufferBytes: _bufferBytes,
    );
  }

  /// Answers one stateless RPC of [repository] by launching
  /// `git upload-pack --stateless-rpc` on the resolved git directory and
  /// writing [request] into its standard input.
  @override
  Future<GitServiceResponse> uploadPack(
    GitServedRepositoryId repository,
    Stream<List<int>> request, {
    required GitProtocolParameters protocol,
  }) async {
    final String gitDir = await _gitDirOf(repository);
    final List<String> arguments = <String>[
      'upload-pack',
      '--stateless-rpc',
      gitDir,
    ];
    final GitLaunchedProcess process = await _launch(arguments, protocol);
    final ProcessUploadPackExchange exchange = ProcessUploadPackExchange(
      process: process,
      arguments: arguments,
      inactivityTimeout: _inactivityTimeout,
      bufferBytes: _bufferBytes,
    );
    unawaited(exchange.pumpRequest(request));
    return exchange;
  }

  /// The git directory of [repository], or the unknown-identifier failure
  /// when the resolution knows none.
  Future<String> _gitDirOf(GitServedRepositoryId repository) async {
    final GitFileBareRepository? bare = await _resolveRepository(repository);
    if (bare == null) {
      throw GitUnknownServedRepositoryException(repository);
    }
    return bare.gitDir();
  }

  /// Launches [arguments] with the environment the validated [protocol]
  /// asks for.
  Future<GitLaunchedProcess> _launch(
    List<String> arguments,
    GitProtocolParameters protocol,
  ) {
    return _launcher.start(GitProcessLaunchRequest(
      arguments: arguments,
      environment: _protocolEnvironment(protocol),
    ));
  }

  /// The environment carrying the negotiated protocol, after validating
  /// that every entry can cross to git as it was received.
  static Map<String, String> _protocolEnvironment(
    GitProtocolParameters protocol,
  ) {
    if (protocol.entries.isEmpty) {
      return const <String, String>{};
    }
    for (final String entry in protocol.entries) {
      if (!_protocolEntry.hasMatch(entry)) {
        throw ArgumentError.value(
          protocol.entries,
          'protocol',
          'entry "$entry" carries a character git cannot receive through '
              'GIT_PROTOCOL',
        );
      }
    }
    return <String, String>{'GIT_PROTOCOL': protocol.entries.join(':')};
  }
}
