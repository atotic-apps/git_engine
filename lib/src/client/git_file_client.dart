import '../models/git_merge_mode.dart';
import '../models/git_merge_result.dart';
import '../models/git_tag_fetch.dart';
import '../repository/git_file_bare_repository.dart';
import '../repository/git_file_repository.dart';
import '../repository/git_working_repository.dart';
import 'git_authentication_exception.dart';
import 'git_no_upstream_exception.dart';
import 'git_push_rejected_exception.dart';
import 'git_remote_ref_not_found_exception.dart';
import 'git_remote_repository_not_found_exception.dart';
import 'git_remote_unreachable_exception.dart';
import 'git_unsupported_url_exception.dart';

/// Client role over repositories stored on disk: it clones a remote location
/// into a target path, and exchanges with remotes on behalf of those
/// repositories.
///
/// The role is distinct from the repository one: a repository never clones
/// another repository or exchanges with a remote, and [GitFileClient] never
/// reads objects or moves references itself.
///
/// This contract assumes disk storage; a client independent of storage will
/// be a distinct contract.
///
/// ## Accepted remote locations
///
/// A [clone] source or a [fetch]/[push] remote location must be one of:
///
/// - a path of the local disk (`/srv/repo.git`, `../repo`, `C:\repo`), a
///   Windows UNC share included;
/// - a `file://`, `http://`, `https://` or `ssh://` URL;
/// - the scp-like spelling `user@host:path`.
///
/// Everything else is refused with [GitUnsupportedUrlException] before git
/// runs: a remote helper invocation (`ext::…`, `fd::…`, any
/// `<transport>::…`), a scheme outside [supportedSchemes], and a value
/// spelled like an option. [supportedSchemes] carries the accepted schemes
/// as data.
///
/// ## Transports
///
/// Clone, fetch, pull and push reach only the accepted forms above, whatever
/// the git configuration allows. Git reads `GIT_ALLOW_PROTOCOL` in preference
/// to every `protocol.*` configuration, and the client sets it to exactly
/// `file:http:https:ssh`, so a remote already configured in a repository, a
/// redirect or a submodule cannot borrow another transport.
///
/// ## Credentials and prompts
///
/// The library supplies no credentials of its own: git uses what the
/// environment already provides — a configured credential helper, ssh-agent,
/// or keys. The process backend disables Git terminal prompts and Git
/// Credential Manager interaction by default, and uses SSH batch mode when
/// no SSH command is configured. A command the user already chose through
/// `GIT_SSH_COMMAND`, `GIT_SSH` or `core.sshCommand` is preserved without
/// adding batch mode. The host must configure custom SSH commands and
/// credential helpers for non-interactive use; their behavior is not
/// guaranteed by the backend's prompt defaults.
/// {@category Client}
abstract interface class GitFileClient {
  /// The URI schemes this client accepts for clone sources and remote
  /// locations.
  ///
  /// The accepted forms beside these schemes are a path of the local disk
  /// and the scp-like `user@host:path` spelling, neither of which carries a
  /// scheme. Values in any other form are refused with
  /// [GitUnsupportedUrlException] before git runs.
  List<String> get supportedSchemes;

  /// Clones the repository [source] into the directory [target], and opens
  /// the clone as a [GitWorkingRepository].
  ///
  /// [source] is a remote location in one of the accepted forms documented
  /// on this class. [noCheckout] leaves an empty work tree, holding only the
  /// git directory; [branch] checks out that branch instead of [source]'s
  /// own `HEAD`.
  ///
  /// A path is always treated as a path, even when it is spelled like an
  /// option. Every other failure — an unreadable [source], an existing and
  /// non-empty [target] — is a `GitException`.
  ///
  /// Throws [GitUnsupportedUrlException] without running git when [source]
  /// is not in an accepted form, [GitAuthenticationException] when the
  /// remote refused or demanded credentials, [GitRemoteUnreachableException]
  /// when the remote host could not be reached, and
  /// [GitRemoteRepositoryNotFoundException] when no repository exists at
  /// [source].
  Future<GitWorkingRepository> clone(
    String source,
    String target, {
    bool noCheckout = false,
    String? branch,
  });

  /// Clones the repository [source] into the bare repository [target], and
  /// opens it as a [GitFileBareRepository].
  ///
  /// [source] is a remote location in one of the accepted forms documented
  /// on this class. A path is always treated as a path, even when it is
  /// spelled like an option. Every other failure is a `GitException`.
  ///
  /// Throws [GitUnsupportedUrlException] without running git when [source]
  /// is not in an accepted form, [GitAuthenticationException] when the
  /// remote refused or demanded credentials, [GitRemoteUnreachableException]
  /// when the remote host could not be reached, and
  /// [GitRemoteRepositoryNotFoundException] when no repository exists at
  /// [source].
  Future<GitFileBareRepository> cloneBare(String source, String target);

  /// Downloads objects and refs from [remote] into [repository]
  /// (`git fetch`), running inside that repository's context.
  ///
  /// [remote] is a configured remote name or a remote location in one of the
  /// accepted forms documented on this class. Without [remote], git fetches
  /// from the default remote of the checked out branch, `origin` after a
  /// normal clone. [refspecs] restrict the refs to fetch and map them (e.g.
  /// `main:refs/heads/other`); they require [remote]. With [prune], refs the
  /// remote no longer has are deleted too.
  ///
  /// [tags] selects which tags come along: [GitTagFetch.follow] (the
  /// default) brings the tags that designate the commits the fetch
  /// retrieves, [GitTagFetch.all] brings every tag of the remote, and
  /// [GitTagFetch.none] brings no tag at all.
  ///
  /// Throws [GitUnsupportedUrlException] without running git when [remote]
  /// is not in an accepted form, [GitRemoteRefNotFoundException] when a
  /// [refspecs] entry names a ref the remote does not have,
  /// [GitAuthenticationException] when the remote refused or demanded
  /// credentials, [GitRemoteUnreachableException] when the remote host could
  /// not be reached, and [GitRemoteRepositoryNotFoundException] when no
  /// repository exists at the remote location.
  Future<void> fetch(
    GitFileRepository repository, {
    String? remote,
    List<String>? refspecs,
    bool prune = false,
    GitTagFetch tags = GitTagFetch.follow,
  });

  /// Updates [remote] with refs of [repository] (`git push`), running inside
  /// that repository's context.
  ///
  /// [remote] is a configured remote name or a remote location in one of the
  /// accepted forms documented on this class. Without [remote], git pushes
  /// the checked out branch to its default remote. [refspecs] give the refs
  /// to push and the remote names they take (e.g. `main:refs/heads/topic`);
  /// they require [remote]. A push that would discard the remote's history —
  /// it is not a fast-forward — is refused with
  /// [GitPushRejectedException].
  ///
  /// With [force], the exchange is not refused for discarding the remote's
  /// history: the remote branch moves onto the pushed commit even when the
  /// pushed history does not descend from the remote tip (`git push
  /// --force`), so the remote keeps the pushed history instead of refusing
  /// the exchange. The commits the remote branch leaves behind stay in the
  /// remote repository as objects until git collects them. Every other
  /// failure stays typed.
  ///
  /// With [tags], every local tag is pushed alongside the other refs; a tag
  /// the remote already holds with another value is refused with
  /// [GitPushRejectedException].
  ///
  /// With [setUpstream], the pushed local branch follows its remote branch
  /// once the push succeeded, so a later [pull] without arguments follows
  /// it. It requires the [refspecs] to designate exactly one local branch —
  /// `refs/heads/<name>`, `<name>`, with an optional destination — or no
  /// [refspecs] at all while `HEAD` is attached to a branch; anything else,
  /// a detached `HEAD` included, is refused with `ArgumentError` before git
  /// runs. Without [refspecs], that branch is pushed by name to [remote];
  /// without [remote] too, what is pushed stays the choice of the
  /// repository's own configuration.
  ///
  /// Throws [GitUnsupportedUrlException] without running git when [remote]
  /// is not in an accepted form, [GitAuthenticationException] when the
  /// remote refused or demanded credentials, [GitRemoteUnreachableException]
  /// when the remote host could not be reached, and
  /// [GitRemoteRepositoryNotFoundException] when no repository exists at the
  /// remote location.
  Future<void> push(
    GitFileRepository repository, {
    String? remote,
    List<String>? refspecs,
    bool force = false,
    bool tags = false,
    bool setUpstream = false,
  });

  /// Fetches [branch] from [remote] and merges it into the current branch of
  /// [repository] — the composition of [fetch] and `GitWorkingMerge.merge`
  /// (`git pull`), running inside that repository's context.
  ///
  /// With [remote] and [branch], the fetch retrieves that branch of that
  /// remote, and the merge folds the remote-tracking branch it obtained into
  /// the current branch. Without [remote] and [branch], the fetch follows
  /// the upstream of the current branch: the remote and the branch its
  /// configuration names, and the merge folds the fetched upstream in. With
  /// [remote] alone, the fetch retrieves the current branch from it.
  /// [branch] without [remote] is an `ArgumentError`, exactly as a refspec
  /// without a remote in [fetch].
  ///
  /// The result is the merge's: up to date, fast-forward, merge commit or
  /// conflicts — a conflicted merge is a result, never an exception. There
  /// is no rebase: [mode] only selects which merges the merge half allows.
  ///
  /// Throws [GitNoUpstreamException] without running git when no branch is
  /// given and none can be derived — `HEAD` is detached, or the current
  /// branch has no upstream. The fetch half throws the failures of [fetch]
  /// ([GitUnsupportedUrlException], [GitRemoteRefNotFoundException],
  /// [GitAuthenticationException], [GitRemoteUnreachableException],
  /// [GitRemoteRepositoryNotFoundException]); the merge half throws the
  /// failures of `GitWorkingMerge.merge` — [GitMergeNotFastForwardException]
  /// when [mode] is [GitMergeMode.fastForwardOnly] and the history cannot
  /// fast-forward, and [GitLocalChangesOverwrittenException] when the merge
  /// would overwrite local changes or untracked files. Every other failure
  /// is a `GitException`.
  Future<GitMergeResult> pull(
    GitWorkingRepository repository, {
    String? remote,
    String? branch,
    GitMergeMode mode = GitMergeMode.auto,
  });
}
