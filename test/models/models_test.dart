import 'package:git_engine/src/models/git_branch.dart';
import 'package:git_engine/src/models/git_commit.dart';
import 'package:git_engine/src/models/git_identity.dart';
import 'package:git_engine/src/models/git_log_commit.dart';
import 'package:git_engine/src/models/git_oid.dart';
import 'package:git_engine/src/models/git_tag_ref.dart';
import 'package:test/test.dart';

void main() {
  const String sha1 = 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391';
  const String sha256 =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  group('GitOid.parse', () {
    test('accepts 40-character hexadecimal object names', () {
      final GitOid oid = GitOid.parse(sha1);
      expect(oid.value, sha1);
      expect(oid.isSha256, isFalse);
    });

    test('accepts 64-character hexadecimal object names', () {
      final GitOid oid = GitOid.parse(sha256);
      expect(oid.value, sha256);
      expect(oid.isSha256, isTrue);
    });

    test('normalizes upper case to lower case', () {
      expect(GitOid.parse(sha1.toUpperCase()).value, sha1);
    });

    test('rejects wrong lengths', () {
      for (final String candidate in <String>[
        '',
        'a' * 39,
        'a' * 41,
        'a' * 63,
        'a' * 65
      ]) {
        expect(
          () => GitOid.parse(candidate),
          throwsFormatException,
          reason: 'should reject "${candidate.length} chars"',
        );
      }
    });

    test('rejects non-hexadecimal characters', () {
      expect(() => GitOid.parse('g' * 40), throwsFormatException);
      expect(() => GitOid.parse('z' * 64), throwsFormatException);
      expect(() => GitOid.parse(' ' * 40), throwsFormatException);
    });

    test('tryParse returns null instead of throwing', () {
      expect(GitOid.tryParse(sha1), isA<GitOid>());
      expect(GitOid.tryParse('nope'), isNull);
    });
  });

  group('GitOid equality', () {
    test('values are equal regardless of case', () {
      expect(GitOid.parse(sha1), GitOid.parse(sha1.toUpperCase()));
      expect(GitOid.parse(sha1).hashCode, GitOid.parse(sha1).hashCode);
    });

    test('different values are not equal', () {
      expect(GitOid.parse(sha1), isNot(GitOid.parse(sha256)));
    });

    test('short returns the abbreviated form', () {
      expect(GitOid.parse(sha1).short(), sha1.substring(0, 7));
      expect(GitOid.parse(sha1).short(12), sha1.substring(0, 12));
      expect(GitOid.parse(sha1).short(40), sha1);
      expect(() => GitOid.parse(sha1).short(0), throwsRangeError);
    });

    test('toString returns the full value', () {
      expect(GitOid.parse(sha1).toString(), sha1);
    });
  });

  group('GitLogCommit', () {
    GitCommit commitOf(String message) {
      return GitCommit(
        tree: GitOid.parse(sha1),
        parents: <GitOid>[GitOid.parse(sha256)],
        author: GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com'),
        authorDate: DateTime.utc(2023, 11, 14, 22, 13, 20),
        committer:
            GitIdentity(name: 'Grace Hopper', email: 'grace@example.com'),
        committerDate: DateTime.utc(2023, 11, 14, 22, 15),
        message: message,
      );
    }

    test('compares its object name and its complete commit', () {
      final GitLogCommit first = GitLogCommit(
        oid: GitOid.parse(sha1),
        commit: commitOf('Subject'),
      );
      final GitLogCommit second = GitLogCommit(
        oid: GitOid.parse(sha1),
        commit: commitOf('Subject'),
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          GitLogCommit(oid: GitOid.parse(sha1), commit: commitOf('Other')),
        ),
      );
    });

    test('renders its short object name and subject', () {
      final GitLogCommit entry = GitLogCommit(
        oid: GitOid.parse(sha1),
        commit: commitOf('Subject\n\nBody'),
      );

      expect(
          entry.toString(), 'GitLogCommit(${sha1.substring(0, 7)}: Subject)');
    });
  });

  group('GitIdentity', () {
    test('translates into author and committer environment variables', () {
      final Map<String, String> environment = GitIdentity(
        name: 'Ada Lovelace',
        email: 'ada@example.com',
      ).toEnvironment();

      expect(environment, <String, String>{
        'GIT_AUTHOR_NAME': 'Ada Lovelace',
        'GIT_AUTHOR_EMAIL': 'ada@example.com',
        'GIT_COMMITTER_NAME': 'Ada Lovelace',
        'GIT_COMMITTER_EMAIL': 'ada@example.com',
      });
    });

    test('rejects empty names and emails', () {
      expect(
        () => GitIdentity(name: '', email: 'ada@example.com'),
        throwsArgumentError,
      );
      expect(
        () => GitIdentity(name: 'Ada Lovelace', email: '  '),
        throwsArgumentError,
      );
    });

    test('renders as git does', () {
      expect(
        GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com').toString(),
        'Ada Lovelace <ada@example.com>',
      );
    });
  });

  group('GitBranch', () {
    final GitOid oid = GitOid.parse(sha1);

    test('compares by name, tip, marker and upstream', () {
      final GitBranch branch = GitBranch(
        name: 'main',
        oid: oid,
        isCurrent: true,
        upstream: 'origin/main',
      );

      expect(
        branch,
        GitBranch(
          name: 'main',
          oid: GitOid.parse(sha1.toUpperCase()),
          isCurrent: true,
          upstream: 'origin/main',
        ),
      );
      expect(branch.hashCode, branch.hashCode);
    });

    test('distinguishes every field', () {
      final GitBranch branch = GitBranch(
        name: 'main',
        oid: oid,
        isCurrent: true,
      );

      expect(
        branch,
        isNot(GitBranch(name: 'topic', oid: oid, isCurrent: true)),
      );
      expect(
        branch,
        isNot(GitBranch(
            name: 'main', oid: GitOid.parse(sha256), isCurrent: true)),
      );
      expect(
        branch,
        isNot(GitBranch(name: 'main', oid: oid, isCurrent: false)),
      );
      expect(
        branch,
        isNot(GitBranch(
          name: 'main',
          oid: oid,
          isCurrent: true,
          upstream: 'origin/main',
        )),
      );
    });

    test('renders with its upstream when it tracks one', () {
      expect(
        GitBranch(name: 'main', oid: oid, isCurrent: true).toString(),
        'main -> $sha1',
      );
      expect(
        GitBranch(
                name: 'main',
                oid: oid,
                isCurrent: true,
                upstream: 'origin/main')
            .toString(),
        'main -> $sha1 (tracks origin/main)',
      );
    });
  });

  group('GitTagRef', () {
    final GitOid tagOid = GitOid.parse(sha1);
    final GitOid commitOid = GitOid.parse(sha256);

    test('compares by name, object, final object and annotation', () {
      final GitTagRef ref = GitTagRef(
        name: 'v1',
        oid: tagOid,
        target: commitOid,
        isAnnotated: true,
      );

      expect(
        ref,
        GitTagRef(
          name: 'v1',
          oid: GitOid.parse(sha1.toUpperCase()),
          target: commitOid,
          isAnnotated: true,
        ),
      );
      expect(ref.hashCode, ref.hashCode);
      expect(
        ref,
        isNot(GitTagRef(
          name: 'v1',
          oid: tagOid,
          target: commitOid,
          isAnnotated: false,
        )),
      );
      expect(
        ref,
        isNot(GitTagRef(
          name: 'other',
          oid: tagOid,
          target: commitOid,
          isAnnotated: true,
        )),
      );
      expect(
        ref,
        isNot(GitTagRef(
          name: 'v1',
          oid: commitOid,
          target: commitOid,
          isAnnotated: true,
        )),
      );
      expect(
        ref,
        isNot(GitTagRef(
          name: 'v1',
          oid: tagOid,
          target: tagOid,
          isAnnotated: true,
        )),
      );
    });

    test('renders with its final object and its annotation', () {
      expect(
        GitTagRef(
          name: 'v1',
          oid: tagOid,
          target: commitOid,
          isAnnotated: true,
        ).toString(),
        'v1 -> $sha256 (annotated)',
      );
      expect(
        GitTagRef(
          name: 'start',
          oid: commitOid,
          target: commitOid,
          isAnnotated: false,
        ).toString(),
        'start -> $sha256',
      );
    });
  });
}
