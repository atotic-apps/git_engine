/// A scheme followed by `//` and the userinfo of the authority, up to the
/// `@` that separates it from the host.
///
/// The userinfo may hold any character except the ones ending the authority
/// (`/`, whitespace, `?`, `#`); percent-encoded characters need no special
/// case because `%` is such a character.
final RegExp _userinfoPattern = RegExp(
  r'([A-Za-z][A-Za-z0-9+.-]*://)([^/\s?#]*@)',
);

/// [text] with the userinfo of every URL it contains replaced by `***`.
///
/// `scheme://userinfo@host/rest` becomes `scheme://***@host/rest`; the
/// scheme, host, path and the rest of the text are kept, including when the
/// URL is part of a larger argument or of a line. Percent-encoded userinfo is
/// replaced as written. The scp-like `user@host:path` spelling carries no
/// scheme and is left unchanged.
String redactUrlUserinfo(String text) {
  return text.replaceAllMapped(
    _userinfoPattern,
    (Match match) => '${match.group(1)}***@',
  );
}

/// A git config key naming the extra headers of the HTTP transport.
///
/// It matches `http.extraHeader` and the per-URL `http.<url>.extraHeader`
/// spelling, whatever the case of the key.
final RegExp _extraHeaderKey = RegExp(
  r'^http\.(?:.*\.)?extraHeader$',
  caseSensitive: false,
);

/// [arguments] joined by spaces for display, with the value of every HTTP
/// extra-header configuration argument replaced by `***`.
///
/// The `-c http.extraHeader=value` spelling (two arguments) and the attached
/// `-chttp.extraHeader=value` spelling are both masked, as are their
/// `http.<url>.extraHeader` variants, whatever the case of the key. The key
/// stays visible. The values are masked argument by argument, before the
/// join, because a value may contain spaces. URL userinfo is masked too, as
/// by [redactUrlUserinfo].
String redactGitArguments(List<String> arguments) {
  final List<String> redacted = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    if (argument == '-c' && index + 1 < arguments.length) {
      redacted
        ..add(argument)
        ..add(_redactConfigArgument(arguments[index + 1]));
      index++;
    } else if (argument.startsWith('-c') && argument.length > 2) {
      redacted.add('-c${_redactConfigArgument(argument.substring(2))}');
    } else {
      redacted.add(argument);
    }
  }
  return redactUrlUserinfo(redacted.join(' '));
}

/// [argument], a git config setting, with the value of an HTTP extra-header
/// key replaced by `***`.
///
/// Any other key, and a setting without a value, is returned unchanged.
String _redactConfigArgument(String argument) {
  final int separator = argument.indexOf('=');
  if (separator < 0) {
    return argument;
  }
  if (!_extraHeaderKey.hasMatch(argument.substring(0, separator))) {
    return argument;
  }
  return '${argument.substring(0, separator + 1)}***';
}
