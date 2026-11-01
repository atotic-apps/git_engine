# Client role

A repository declares its remotes; the client reaches them. [GitRemotes]
lists, adds, renames, re-points and removes remote declarations, while
[GitFileClient] clones repositories and exchanges with remotes on their
behalf. Keeping the roles apart means a repository never starts an exchange
and the client never edits objects or references itself.

## What the client drives

[GitFileClient] covers `clone` and `cloneBare`, then `fetch` and `push` on
an existing [GitFileRepository] and `pull` on a [GitWorkingRepository].
`supportedSchemes` exposes the accepted URL schemes as data. The runnable
examples are
`example/client.dart`, `example/remote_client.dart` and
`example/remote_tags.dart`.

## Accepted and refused locations

A clone source or remote location is accepted as a local path, Windows drive
and UNC spellings included, as a `file://`, `http://`, `https://` or
`ssh://` URL, or as the scp-like `user@host:path` form. Everything else is
refused before git starts: an empty value, a value spelled like an option, a
remote helper such as `ext::…` or `fd::…`, or a scheme outside the accepted
list.

The client also bounds the transports themselves. It sets
`GIT_ALLOW_PROTOCOL` to exactly `file:http:https:ssh`. Git reads that
variable in preference to every `protocol.*` setting, so a remote already
recorded in the repository, a redirect or a submodule cannot borrow a
transport the client did not accept.

## Credentials and prompts

The library supplies no credentials. Git uses the credential helper,
ssh-agent or keys the environment and git configuration already provide.
By default, the process environment sets `GIT_TERMINAL_PROMPT=0` and
`GCM_INTERACTIVE=never`. When no SSH command is configured, the client uses
`ssh -oBatchMode=yes`, so SSH refuses authentication or host-key prompts.

An SSH command chosen through `GIT_SSH_COMMAND`, `GIT_SSH` or
`core.sshCommand` is preserved without adding batch mode. The client sets
`SSH_ASKPASS_REQUIRE=never`, but cannot guarantee that a custom command or
credential helper will not prompt. The host must configure those programs
for non-interactive use. Runner environment defaults can also be overridden
explicitly by the caller.

## Pull semantics

`pull` fetches and then merges into the current branch of a
[GitWorkingRepository]. With no remote and no branch, it follows the
upstream of the current branch. With both, it integrates that remote branch.
With a remote alone, it fetches the current branch from that remote; asking
for a branch without a remote is refused before git runs.

A pull with no branch to follow — a detached HEAD or a current branch
without an upstream — fails before any exchange. The outcome is the merge
outcome, conflicts included: a conflicted merge is a result, not an
exception. The mode only selects which merges the merge half allows; there
is no rebase.

`fetch` and `push` share the same location rules and the same bounded
environment. A fetch chooses its tags through its `tags` argument; a push
can carry local tags, force a non-fast-forward update, or record the pushed
branch as the upstream of its remote counterpart.

```dart
import 'package:git_engine/git_engine.dart';
import 'package:git_engine/process.dart';

Future<void> main() async {
  final GitFileClient client = ProcessGitEngine();
  final GitWorkingRepository repository = await client.clone(
    'https://example.com/team/project.git',
    '/srv/project',
  );
  await repository.remotes.add(
    'upstream',
    'ssh://git@example.com/team/project.git',
  );
  await client.fetch(repository, remote: 'upstream');
  final GitMergeResult result = await client.pull(repository);
  print(result);
}
```
