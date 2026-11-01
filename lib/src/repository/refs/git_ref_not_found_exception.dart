import '../../core/errors/git_exception.dart';

/// A branch or a tag an operation names does not exist.
///
/// Raised by `GitBranches.rename` and `GitBranches.setUpstream` for an
/// unknown branch, by `GitBranches.delete` for an unknown branch, and by
/// `GitTags.delete` for an unknown tag. Operations that document a null
/// result for a missing reference keep that result instead of raising.
///
/// The underlying engine failure that reported the refusal is carried in
/// [cause] when there is one.
/// {@category Errors}
class GitRefNotFoundException extends GitException {
  /// Short branch or tag name that does not exist.
  final String name;

  /// The underlying engine failure that reported the refusal.
  final GitException? cause;

  /// Creates the refusal of [name], from the [cause] git reported when
  /// there is one.
  GitRefNotFoundException({
    required this.name,
    this.cause,
  }) : super('the reference "$name" does not exist');
}
