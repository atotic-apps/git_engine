/// Remotes of one repository and their declaration: listing, adding,
/// removing and renaming remotes, reading and writing their URLs.
///
/// Declaring remotes only configures the repository: nothing is exchanged
/// with a remote here. Fetching and pushing are client operations, exposed by
/// `GitFileClient` and performed on a `GitFileRepository`.
///
/// Every command runs inside the owning repository's context, so a derived
/// view (an alternate index, extra environment variables) applies here too.
///
/// No string these operations receive is ever interpreted by git as an
/// option: names and URLs are separated from the options git offers with its
/// `--` end-of-options marker, wherever `git remote` accepts one.
///
/// Every failure is a `GitException`.
///
/// ```dart
/// await repo.remotes.add('origin', '/srv/project.git');
/// final List<String> names = await repo.remotes.list();
/// final String? url = await repo.remotes.getUrl('origin');
/// await client.fetch(repo, remote: 'origin');
/// await client.push(repo, remote: 'origin',
///     refspecs: <String>['HEAD:refs/heads/main']);
/// ```
/// {@category Getting started}
abstract interface class GitRemotes {
  /// Names of the configured remotes, in the order git lists them.
  Future<List<String>> list();

  /// Registers the remote [name] fetching from [url]. A name git refuses —
  /// already in use, impossible to spell — is refused with a `GitException`.
  Future<void> add(String name, String url);

  /// Removes the remote [name], the remote-tracking refs it brought along
  /// included. Git refuses an unknown remote with a `GitException`.
  Future<void> remove(String name);

  /// Renames the remote [name] to [newName], moving its remote-tracking refs
  /// and updating the branch configurations that mention it. Git refuses an
  /// unknown remote with a `GitException`.
  Future<void> rename(String name, String newName);

  /// URL the remote [name] fetches from, or null when that remote does not
  /// exist.
  Future<String?> getUrl(String name);

  /// Sets the URL the remote [name] fetches from. Git refuses an unknown
  /// remote with a `GitException`.
  Future<void> setUrl(String name, String url);
}
