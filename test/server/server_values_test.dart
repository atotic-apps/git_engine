import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

import '../support/fake_git_http.dart';

void main() {
  group('GitServedRepositoryId', () {
    test('is equal by value', () {
      expect(
        const GitServedRepositoryId('a'),
        const GitServedRepositoryId('a'),
      );
      expect(
        const GitServedRepositoryId('a').hashCode,
        const GitServedRepositoryId('a').hashCode,
      );
      expect(
        const GitServedRepositoryId('a'),
        isNot(const GitServedRepositoryId('b')),
      );
    });

    test('normalizes nothing', () {
      const GitServedRepositoryId id = GitServedRepositoryId('Repo.GIT');
      expect(id.value, 'Repo.GIT');
      expect(id, isNot(const GitServedRepositoryId('repo')));
      expect(id, isNot(const GitServedRepositoryId('Repo.git')));
      expect(id, isNot(const GitServedRepositoryId('/Repo.GIT')));
      expect(id.toString(), 'Repo.GIT');
    });
  });

  group('GitProtocolParameters', () {
    test('reports version 0 without an explicit request', () {
      expect(GitProtocolParameters.empty().version, 0);
      expect(GitProtocolParameters.empty().entries, isEmpty);
      expect(
        GitProtocolParameters(<String>['agent=unit/1']).version,
        0,
      );
    });

    test('reports the requested version', () {
      expect(
        GitProtocolParameters(<String>['version=2']).version,
        2,
      );
      expect(
        GitProtocolParameters(<String>['object-format=sha256', 'version=1'])
            .version,
        1,
      );
    });

    test('keeps the entries in the order received, unmodifiable', () {
      final GitProtocolParameters parameters = GitProtocolParameters(
        <String>['version=2', 'side-band-64k'],
      );
      expect(
        parameters.entries,
        <String>['version=2', 'side-band-64k'],
      );
      expect(
        () => parameters.entries.add('nope'),
        throwsUnsupportedError,
      );
    });

    test('ignores an invalid version and keeps the last valid one', () {
      expect(
        GitProtocolParameters(<String>['version=two']).version,
        0,
      );
      expect(
        GitProtocolParameters(<String>['version=1', 'version=2']).version,
        2,
      );
      expect(
        GitProtocolParameters(<String>['version=-1']).version,
        0,
      );
    });

    test('is equal by value', () {
      expect(
        GitProtocolParameters(<String>['version=2']),
        GitProtocolParameters(<String>['version=2']),
      );
      expect(
        GitProtocolParameters(<String>['a', 'b']),
        isNot(GitProtocolParameters(<String>['b', 'a'])),
      );
    });
  });

  group('GitHttpHeaders', () {
    test('is case-insensitive on names and keeps every value', () {
      final GitHttpHeaders headers = GitHttpHeaders(<String, List<String>>{
        'Content-Type': <String>['application/x-git-upload-pack-request'],
        'git-protocol': <String>['version=2', 'side-band-64k'],
      });

      expect(headers.values('CONTENT-TYPE'),
          <String>['application/x-git-upload-pack-request']);
      expect(headers.values('Git-Protocol'),
          <String>['version=2', 'side-band-64k']);
      expect(headers.firstValue('GIT-PROTOCOL'), 'version=2');
      expect(headers.contains('Git-Protocol'), isTrue);
      expect(headers.contains('Accept'), isFalse);
      expect(headers.values('Accept'), isEmpty);
      expect(headers.firstValue('Accept'), isNull);
    });

    test('is immutable', () {
      final GitHttpHeaders headers = GitHttpHeaders(<String, List<String>>{
        'X-Once': <String>['a'],
      });
      expect(
        () => headers.values('X-Once').add('b'),
        throwsUnsupportedError,
      );
      expect(headers.firstValue('x-once'), 'a');
    });
  });

  group('GitReadOnlyAuthorizationPolicy', () {
    test('allows reading to everyone and refuses writing', () {
      const GitReadOnlyAuthorizationPolicy policy =
          GitReadOnlyAuthorizationPolicy();
      const GitServedRepositoryId repository = GitServedRepositoryId('repo');

      expect(policy.canRead(null, repository), isTrue);
      expect(policy.canRead(const FakeGitPrincipal('ada'), repository), isTrue);
      expect(policy.canWrite(null, repository), isFalse);
      expect(
          policy.canWrite(const FakeGitPrincipal('ada'), repository), isFalse);
    });
  });
}
