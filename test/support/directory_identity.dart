import 'dart:io';

/// Whether two existing directory paths refer to the same filesystem object,
/// resolving symbolic links and letting the filesystem handle path casing.
bool sameDirectory(String a, String b) => FileSystemEntity.identicalSync(
      Directory(a).resolveSymbolicLinksSync(),
      Directory(b).resolveSymbolicLinksSync(),
    );
