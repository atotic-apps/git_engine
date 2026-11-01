import 'dart:typed_data';

import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

/// The key rule of [GitDirectorySnapshot]: a capture only ever names files
/// relative to the git directory, spelled with forward slashes.
void main() {
  GitDirectorySnapshot snapshotOf(List<String> keys) {
    return GitDirectorySnapshot(<String, Uint8List>{
      for (final String key in keys) key: Uint8List(0),
    });
  }

  group('GitDirectorySnapshot keys', () {
    test('accepts git-directory relative paths spelled with slashes', () {
      final GitDirectorySnapshot snapshot = snapshotOf(<String>[
        'HEAD',
        'config',
        'refs/heads/main',
        'hooks/pre-commit.sample',
      ]);

      expect(snapshot.files.keys, hasLength(4));
    });

    final List<(String, String)> refused = <(String, String)>[
      ('', 'empty key'),
      ('/rooted/notes.txt', 'rooted POSIX path'),
      ('\\windows\\system32', 'rooted Windows path'),
      ('C:\\hooks\\pre-commit', 'drive path'),
      ('C:hooks', 'drive relative path'),
      ('\\\\server\\share\\hooks', 'UNC share'),
      ('hooks\\pre-commit', 'backslash separator'),
      ('a\u0000b', 'NUL character'),
      ('hooks//pre-commit', 'empty segment'),
      ('hooks/./pre-commit', 'dot segment'),
      ('hooks/../outside', 'dot-dot segment'),
      ('../escaped.txt', 'dot-dot before the directory'),
      ('.', 'dot key'),
      ('..', 'dot-dot key'),
      ('hooks/', 'trailing empty segment'),
    ];

    for (final (String key, String reason) in refused) {
      test('rejects a $reason', () {
        expect(
          () => snapshotOf(<String>[key]),
          throwsA(isA<ArgumentError>()),
          reason: 'the key "$key" must be refused',
        );
      });
    }

    test('names the refused key', () {
      const String key = '../escaped.txt';

      expect(
        () => snapshotOf(<String>[key]),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.toString(),
            'message',
            contains(key),
          ),
        ),
      );
    });
  });
}
