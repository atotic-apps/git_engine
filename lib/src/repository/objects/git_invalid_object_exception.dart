import '../../core/errors/git_exception.dart';
import '../../core/redact_url_userinfo.dart';
import '../../models/git_object_type.dart';

/// The content handed to `GitObjectWriter.writeObject` was refused.
///
/// Raised when `GitObjectWriter.writeObject` cannot store the serialized
/// content as a valid object of the requested type. The underlying engine
/// failure that refused it is carried in [cause].
/// {@category Errors}
class GitInvalidObjectException extends GitException {
  /// Type of the object the content was meant to be.
  final GitObjectType type;

  /// Underlying engine failure that refused the content.
  final GitException cause;

  /// Creates the refusal of [type] from the [cause] that reported it.
  GitInvalidObjectException({required this.type, required this.cause})
      : super('Invalid ${type.name} object: '
            '${redactUrlUserinfo(cause.message)}');
}
