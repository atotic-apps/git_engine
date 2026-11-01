/// Formats [date] the way git accepts it in `GIT_AUTHOR_DATE`,
/// `GIT_COMMITTER_DATE` and every other identity date variable: seconds
/// since the epoch followed by the numeric offset of the date's zone.
String formatGitDate(DateTime date) {
  final int offsetSeconds = date.timeZoneOffset.inSeconds;
  final String sign = offsetSeconds < 0 ? '-' : '+';
  final int absolute = offsetSeconds.abs();
  final String hours = (absolute ~/ 3600).toString().padLeft(2, '0');
  final String minutes = ((absolute % 3600) ~/ 60).toString().padLeft(2, '0');
  final int seconds = date.millisecondsSinceEpoch ~/ 1000;
  return '@$seconds $sign$hours$minutes';
}
