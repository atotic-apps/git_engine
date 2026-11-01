import '../../core/errors/git_exception.dart';

/// A branch or a tag could not be created because its name is already taken.
///
/// Raised by `GitBranches.create` and `GitBranches.rename` without `force`,
/// and by `GitTags.create` without `force`, when git refuses so the existing
/// reference keeps pointing where it points. Creating with `force: true`
/// moves the existing reference instead.
///
/// The underlying engine failure that reported the refusal is carried in
/// [cause] when there is one.
/// {@category Errors}
class GitRefExistsException extends GitException {
  /// Short branch or tag name that is already taken.
  final String name;

  /// The underlying engine failure that reported the refusal.
  final GitException? cause;

  /// Creates the refusal of [name], from the [cause] git reported when
  /// there is one.
  GitRefExistsException({
    required this.name,
    this.cause,
  }) : super('the reference "$name" already exists');
}
