import 'package:git_engine/testing.dart';
import 'package:test/test.dart';

void main() {
  group('GitPathStyle', () {
    group('windows', () {
      const GitPathStyle style = GitPathStyle.windows;

      test('separates segments with a backslash', () {
        expect(style.separator, '\\');
        expect(style.isWindows, isTrue);
        expect(style.isPosix, isFalse);
      });

      test('recognizes drives, UNC shares and rooted paths', () {
        expect(style.isAbsolute(r'C:\repo'), isTrue);
        expect(style.isAbsolute('C:/repo'), isTrue);
        expect(style.isAbsolute(r'\\server\share\repo'), isTrue);
        expect(style.isAbsolute(r'\repo'), isTrue);
        expect(style.isAbsolute('/repo'), isTrue);
        expect(style.isAbsolute(r'repo\sub'), isFalse);
        expect(style.isAbsolute('repo'), isFalse);
      });

      test('returns the root a path hangs from', () {
        expect(style.driveRoot(r'C:\repo\sub'), r'C:\');
        expect(style.driveRoot('C:/repo'), 'C:/');
        expect(style.driveRoot(r'\\server\share\repo'), r'\\server\share\');
        expect(style.driveRoot(r'\repo'), r'\');
        expect(style.driveRoot(r'\repo\sub'), r'\');
        expect(style.driveRoot('/repo'), '/');
        expect(style.driveRoot(r'repo\sub'), isNull);
        expect(style.driveRoot(''), isNull);
      });

      test('joins a relative path with backslashes', () {
        expect(style.join(r'C:\base', 'a/b'), r'C:\base\a\b');
        expect(style.join(r'C:\base\', 'a'), r'C:\base\a');
      });

      test('normalizes dot segments wherever the separators come from', () {
        expect(style.normalize(r'C:\base/other\..\repo'), r'C:\base\repo');
        expect(style.normalize(r'\\server\share\a\..\b'), r'\\server\share\b');
        expect(style.normalize(r'\repo\.\sub'), r'\repo\sub');
      });
    });

    group('posix', () {
      const GitPathStyle style = GitPathStyle.posix;

      test('separates segments with a slash', () {
        expect(style.separator, '/');
        expect(style.isPosix, isTrue);
        expect(style.isWindows, isFalse);
      });

      test('recognizes absolute paths', () {
        expect(style.isAbsolute('/repo'), isTrue);
        expect(style.isAbsolute('/'), isTrue);
        expect(style.isAbsolute('repo/sub'), isFalse);
        expect(style.isAbsolute(''), isFalse);
      });

      test('returns the root a path hangs from', () {
        expect(style.driveRoot('/repo/sub'), '/');
        expect(style.driveRoot('/'), '/');
        expect(style.driveRoot('repo/sub'), isNull);
      });

      test('joins a relative path with slashes', () {
        expect(style.join('/base', 'a/b'), '/base/a/b');
        expect(style.join('/base/', 'a'), '/base/a');
      });

      test('normalizes dot segments under the root', () {
        expect(style.normalize('/base/other/../repo'), '/base/repo');
        expect(style.normalize('/../repo/./sub'), '/repo/sub');
      });
    });
  });

  group('GitPlatform', () {
    test('windows carries the Windows path style and an empty environment', () {
      expect(GitPlatform.windows.operatingSystem, GitOperatingSystem.windows);
      expect(GitPlatform.windows.pathStyle, GitPathStyle.windows);
      expect(GitPlatform.windows.environment, isEmpty);
    });

    test('linux carries the POSIX path style and an empty environment', () {
      expect(GitPlatform.linux.operatingSystem, GitOperatingSystem.linux);
      expect(GitPlatform.linux.pathStyle, GitPathStyle.posix);
      expect(GitPlatform.linux.environment, isEmpty);
    });

    test('macos carries the POSIX path style and an empty environment', () {
      expect(GitPlatform.macos.operatingSystem, GitOperatingSystem.macos);
      expect(GitPlatform.macos.pathStyle, GitPathStyle.posix);
      expect(GitPlatform.macos.environment, isEmpty);
    });

    test('the derived path style can be overridden', () {
      final GitPlatform crossStyle = GitPlatform(
        operatingSystem: GitOperatingSystem.linux,
        pathStyle: GitPathStyle.windows,
      );

      expect(crossStyle.pathStyle, GitPathStyle.windows);
    });

    test('the environment is copied and unmodifiable', () {
      final Map<String, String> source = <String, String>{'HOME': '/home'};
      final GitPlatform platform = GitPlatform(
        operatingSystem: GitOperatingSystem.linux,
        environment: source,
      );

      source['HOME'] = '/elsewhere';
      source['PATH'] = '/bin';

      expect(platform.environment, <String, String>{'HOME': '/home'});
      expect(
        () => platform.environment['HOME'] = '/other',
        throwsUnsupportedError,
      );
    });
  });
}
