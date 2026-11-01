import '../../models/git_config_entry.dart';

/// Local configuration of one repository.
///
/// Every operation reads or writes only the repository's own configuration
/// file, so the system and global configurations are never touched — reads
/// return only what the local file holds, writes land only in it. Whether the
/// other levels hold the same key is therefore invisible.
///
/// Keys use git's spelling (`remote.origin.url`, `user.email`). Every failure
/// is a `GitException`.
///
/// ```dart
/// await repo.config.set('user.name', 'Ada Lovelace');
/// final String? name = await repo.config.get('user.name');
/// final List<GitConfigEntry> remotes =
///     await repo.config.getAll(prefix: 'remote.');
/// await repo.config.unset('user.name');
/// await repo.config.removeSection('remote.origin');
/// ```
/// {@category Getting started}
abstract interface class GitConfig {
  /// Most recent value of [key] in the local configuration, or null when it
  /// does not hold that key. The value without git's trailing newline;
  /// anything it held, spaces and newlines included, is kept.
  Future<String?> get(String key);

  /// Every key/value pair of the local configuration whose key starts with
  /// [prefix], in the order the file holds them.
  ///
  /// Keys are compared in their normalized form: the section and the variable
  /// name are lowercase, while the subsection keeps the case it was written
  /// with. `remote.origin.url` and `custom.CamelCase.key` show that form.
  /// [prefix] is matched against that form, so an empty prefix returns the
  /// whole local configuration. Values read back exactly as written, newlines
  /// included; the result is empty when no key matches.
  Future<List<GitConfigEntry>> getAll({String prefix = ''});

  /// Sets [key] to [value] in the local configuration, replacing the value
  /// it already held. Multi-valued keys cannot be replaced by a single
  /// value: git's refusal is raised as a `GitException`.
  Future<void> set(String key, String value);

  /// Removes every value of [key] from the local configuration. Git reports
  /// refusals — an absent key, several values at once — as `GitException`.
  Future<void> unset(String key);

  /// Removes the whole section [name] (e.g. `remote.origin`) from the local
  /// configuration. Git refuses an absent section with a `GitException`.
  Future<void> removeSection(String name);
}
