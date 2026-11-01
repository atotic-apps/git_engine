/// Author or committer identity handed to git through environment variables.
///
/// [toEnvironment] translates the identity into the `GIT_AUTHOR_*` and
/// `GIT_COMMITTER_*` variables git honors, which take precedence over the
/// `user.name` / `user.email` configuration.
/// {@category Getting started}
class GitIdentity {
  /// Human-readable name, e.g. `Ada Lovelace`.
  final String name;

  /// E-mail address, e.g. `ada@example.com`.
  final String email;

  /// Creates an identity of [name] and [email]; either being blank is an
  /// [ArgumentError].
  GitIdentity({required this.name, required this.email}) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (email.trim().isEmpty) {
      throw ArgumentError.value(email, 'email', 'must not be empty');
    }
  }

  /// Environment variables describing this identity, both as author and as
  /// committer.
  Map<String, String> toEnvironment() => <String, String>{
        'GIT_AUTHOR_NAME': name,
        'GIT_AUTHOR_EMAIL': email,
        'GIT_COMMITTER_NAME': name,
        'GIT_COMMITTER_EMAIL': email,
      };

  @override
  bool operator ==(Object other) =>
      other is GitIdentity && other.name == name && other.email == email;

  @override
  int get hashCode => Object.hash(name, email);

  @override
  String toString() => '$name <$email>';
}
