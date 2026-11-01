import '../core/errors/git_exception.dart';
import '../core/redact_url_userinfo.dart';

/// A remote location the client refuses before git runs at all.
///
/// Raised for a clone source or a remote location spelled in a form the
/// library does not accept: a remote helper (`ext::…`, `fd::…`, any
/// `<transport>::…`), a scheme outside `GitFileClient.supportedSchemes`, or
/// a value spelled like an option. Nothing has been launched when this is
/// raised, so the failure can never come from git itself. The message masks
/// the userinfo of the refused URL.
/// {@category Errors}
class GitUnsupportedUrlException extends GitException {
  /// The refused value, exactly as it was given.
  ///
  /// It may contain the userinfo of a remote URL; do not log it as it is.
  /// [message] masks it.
  final String url;

  /// Creates the refusal of [url], with [reason] saying which accepted form
  /// it misses.
  GitUnsupportedUrlException(this.url, {required String reason})
      : super('Unsupported remote location "${redactUrlUserinfo(url)}": '
            '$reason');
}
