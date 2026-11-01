import 'dart:async';
import 'dart:io';

import 'git_platform.dart';

/// Error code the operating system reports when the executable cannot be
/// found (ERROR_FILE_NOT_FOUND on Windows, ENOENT elsewhere).
const int processExecutableNotFoundErrorCode = 2;

/// Stops [process] and completes once it is gone.
///
/// On [GitOperatingSystem.windows], `taskkill /T /F` is attempted on
/// [process] and its tree while it is alive; when that fails, [process] is
/// killed directly. On other systems, [process] receives SIGTERM, then
/// SIGKILL when it is still running after a grace period.
///
/// Descendants that outlive [process], or that detach from it, may keep
/// running: this function does not guarantee that the whole process tree is
/// stopped. Killing an already exited process is allowed and completes
/// immediately.
Future<void> killProcessTree(
  Process process, {
  required GitOperatingSystem operatingSystem,
}) async {
  if (operatingSystem == GitOperatingSystem.windows) {
    try {
      final ProcessResult kill = await Process.run(
        'taskkill',
        <String>['/T', '/F', '/PID', '${process.pid}'],
      );
      if (kill.exitCode != 0) {
        process.kill();
      }
    } on ProcessException {
      process.kill();
    }
  } else {
    process.kill(ProcessSignal.sigterm);
  }
  const Duration gracePeriod = Duration(seconds: 5);
  try {
    await process.exitCode.timeout(gracePeriod);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  }
}
