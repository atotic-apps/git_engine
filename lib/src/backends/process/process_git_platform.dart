import 'dart:io';

import 'git_platform.dart';

/// [GitPlatform] of the machine this process runs on.
///
/// The operating system, current directory and environment come from
/// `dart:io`. It is the default the process backend falls back to when no
/// platform is handed to it.
GitPlatform get hostGitPlatform {
  final GitOperatingSystem operatingSystem;
  if (Platform.isWindows) {
    operatingSystem = GitOperatingSystem.windows;
  } else if (Platform.isMacOS) {
    operatingSystem = GitOperatingSystem.macos;
  } else {
    operatingSystem = GitOperatingSystem.linux;
  }
  return GitPlatform(
    operatingSystem: operatingSystem,
    environment: Platform.environment,
    currentDirectory: Directory.current.path,
  );
}
