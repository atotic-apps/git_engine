import 'package:git_engine/git_engine.dart';
import 'package:test/test.dart';

/// Declares the contract of the domain exceptions that can carry their cause.
///
/// These failures extend [GitException] directly, never a backend command
/// failure, so a caller catches a domain refusal without accidentally catching
/// every command failure. The process backend supplies the cause; a backend
/// with no command underneath raises them without one, so [GitException.cause]
/// is optional and every backend may honour the shape.
void defineGitDomainExceptionContract() {
  GitException commandFailure() => GitException('git exited with a failure');

  group('domain exceptions', () {
    test('GitNotARepositoryException is a domain failure carrying its cause',
        () {
      final GitException cause = commandFailure();
      final GitNotARepositoryException error =
          GitNotARepositoryException(cause: cause);

      expect(error, isA<GitException>());
      expect(error, isA<GitNotARepositoryException>());
      expect(error.cause, same(cause));
    });

    test('GitRefMismatchException is a domain failure carrying its cause', () {
      final GitException cause = commandFailure();
      final GitRefMismatchException error =
          GitRefMismatchException(cause: cause);

      expect(error, isA<GitException>());
      expect(error, isA<GitRefMismatchException>());
      expect(error.cause, same(cause));
    });

    test('GitRemoteRefNotFoundException is a domain failure carrying its cause',
        () {
      final GitException cause = commandFailure();
      final GitRemoteRefNotFoundException error =
          GitRemoteRefNotFoundException(cause: cause);

      expect(error, isA<GitException>());
      expect(error, isA<GitRemoteRefNotFoundException>());
      expect(error.cause, same(cause));
    });

    test('GitPushRejectedException is a domain failure carrying its cause', () {
      final GitException cause = commandFailure();
      final GitPushRejectedException error =
          GitPushRejectedException(cause: cause);

      expect(error, isA<GitException>());
      expect(error, isA<GitPushRejectedException>());
      expect(error.cause, same(cause));
    });

    test('GitAuthenticationException is a domain failure carrying its cause',
        () {
      final GitException cause = commandFailure();
      final GitAuthenticationException error =
          GitAuthenticationException(cause: cause);

      expect(error, isA<GitException>());
      expect(error, isA<GitAuthenticationException>());
      expect(error.cause, same(cause));
    });

    test('GitRemoteUnreachableException is a domain failure carrying its cause',
        () {
      final GitException cause = commandFailure();
      final GitRemoteUnreachableException error =
          GitRemoteUnreachableException(cause: cause);

      expect(error, isA<GitException>());
      expect(error, isA<GitRemoteUnreachableException>());
      expect(error.cause, same(cause));
    });

    test(
        'GitRemoteRepositoryNotFoundException is a domain failure carrying '
        'its cause', () {
      final GitException cause = commandFailure();
      final GitRemoteRepositoryNotFoundException error =
          GitRemoteRepositoryNotFoundException(cause: cause);

      expect(error, isA<GitException>());
      expect(error, isA<GitRemoteRepositoryNotFoundException>());
      expect(error.cause, same(cause));
    });

    test(
        'GitMergeNotFastForwardException is a domain failure carrying its '
        'cause', () {
      final GitException cause = commandFailure();
      final GitMergeNotFastForwardException error =
          GitMergeNotFastForwardException('no fast-forward possible',
              cause: cause);

      expect(error, isA<GitException>());
      expect(error, isA<GitMergeNotFastForwardException>());
      expect(error.cause, same(cause));
    });

    test('GitUnknownRevisionException is a domain failure carrying its cause',
        () {
      final GitException cause = commandFailure();
      final GitUnknownRevisionException error = GitUnknownRevisionException(
        expression: 'no-such-branch',
        cause: cause,
      );

      expect(error, isA<GitException>());
      expect(error, isA<GitUnknownRevisionException>());
      expect(error.cause, same(cause));
      expect(error.expression, 'no-such-branch');
      expect(error.message, contains('no-such-branch'));
    });

    test(
        'GitUnknownRevisionException raises without a cause, as a backend '
        'with no command underneath does', () {
      final GitUnknownRevisionException error = GitUnknownRevisionException(
        expression: 'no-such-branch',
      );

      expect(error, isA<GitException>());
      expect(error, isA<GitUnknownRevisionException>());
      expect(error.cause, isNull);
    });

    test(
        'GitLocalChangesOverwrittenException is a domain failure carrying '
        'its cause', () {
      final GitException cause = commandFailure();
      final GitLocalChangesOverwrittenException error =
          GitLocalChangesOverwrittenException(
        paths: const <String>['notes.txt', 'generated/'],
        cause: cause,
      );

      expect(error, isA<GitException>());
      expect(error, isA<GitLocalChangesOverwrittenException>());
      expect(error.cause, same(cause));
      expect(error.paths, <String>['notes.txt', 'generated/']);
    });

    test(
        'GitLocalChangesOverwrittenException raises without a cause, as a '
        'backend with no command underneath does', () {
      final GitLocalChangesOverwrittenException error =
          GitLocalChangesOverwrittenException();

      expect(error, isA<GitException>());
      expect(error, isA<GitLocalChangesOverwrittenException>());
      expect(error.cause, isNull);
      expect(error.paths, isEmpty);
    });

    test('GitBranchNotMergedException is a domain failure carrying its cause',
        () {
      final GitException cause = commandFailure();
      final GitBranchNotMergedException error = GitBranchNotMergedException(
        branch: 'topic',
        cause: cause,
      );

      expect(error, isA<GitException>());
      expect(error, isA<GitBranchNotMergedException>());
      expect(error.cause, same(cause));
      expect(error.branch, 'topic');
    });

    test(
        'GitBranchNotMergedException raises without a cause, as a backend '
        'with no command underneath does', () {
      final GitBranchNotMergedException error = GitBranchNotMergedException(
        branch: 'topic',
      );

      expect(error, isA<GitException>());
      expect(error, isA<GitBranchNotMergedException>());
      expect(error.cause, isNull);
    });

    test('GitNoMergeInProgressException is a domain failure carrying its cause',
        () {
      final GitException cause = commandFailure();
      final GitNoMergeInProgressException error = GitNoMergeInProgressException(
        cause: cause,
      );

      expect(error, isA<GitException>());
      expect(error, isA<GitNoMergeInProgressException>());
      expect(error.cause, same(cause));
    });

    test(
        'GitNoMergeInProgressException raises without a cause, as a backend '
        'with no command underneath does', () {
      final GitNoMergeInProgressException error =
          GitNoMergeInProgressException();

      expect(error, isA<GitException>());
      expect(error, isA<GitNoMergeInProgressException>());
      expect(error.cause, isNull);
    });

    test(
        'GitUnrelatedHistoriesException is a domain failure carrying its cause',
        () {
      final GitException cause = commandFailure();
      final GitUnrelatedHistoriesException error =
          GitUnrelatedHistoriesException(cause: cause);

      expect(error, isA<GitException>());
      expect(error, isA<GitUnrelatedHistoriesException>());
      expect(error.cause, same(cause));
    });

    test(
        'GitUnrelatedHistoriesException raises without a cause, as a backend '
        'with no command underneath does', () {
      final GitUnrelatedHistoriesException error =
          GitUnrelatedHistoriesException();

      expect(error, isA<GitException>());
      expect(error, isA<GitUnrelatedHistoriesException>());
      expect(error.cause, isNull);
    });

    test('GitRefMismatchException raises without a cause too', () {
      final GitRefMismatchException error = GitRefMismatchException();

      expect(error, isA<GitException>());
      expect(error, isA<GitRefMismatchException>());
      expect(error.cause, isNull);
    });

    test('GitRefExistsException is a domain failure carrying its cause', () {
      final GitException cause = commandFailure();
      final GitRefExistsException error = GitRefExistsException(
        name: 'topic',
        cause: cause,
      );

      expect(error, isA<GitException>());
      expect(error, isA<GitRefExistsException>());
      expect(error.cause, same(cause));
      expect(error.name, 'topic');
      expect(error.message, contains('topic'));
    });

    test(
        'GitRefExistsException raises without a cause, as a backend with no '
        'command underneath does', () {
      final GitRefExistsException error = GitRefExistsException(name: 'topic');

      expect(error, isA<GitException>());
      expect(error, isA<GitRefExistsException>());
      expect(error.cause, isNull);
    });

    test('GitRefNotFoundException is a domain failure carrying its cause', () {
      final GitException cause = commandFailure();
      final GitRefNotFoundException error = GitRefNotFoundException(
        name: 'v1',
        cause: cause,
      );

      expect(error, isA<GitException>());
      expect(error, isA<GitRefNotFoundException>());
      expect(error.cause, same(cause));
      expect(error.name, 'v1');
      expect(error.message, contains('v1'));
    });

    test(
        'GitRefNotFoundException raises without a cause, as a backend with '
        'no command underneath does', () {
      final GitRefNotFoundException error = GitRefNotFoundException(name: 'v1');

      expect(error, isA<GitException>());
      expect(error, isA<GitRefNotFoundException>());
      expect(error.cause, isNull);
    });

    test('GitMergeNotFastForwardException raises without a cause too', () {
      final GitMergeNotFastForwardException error =
          GitMergeNotFastForwardException('no fast-forward possible');

      expect(error, isA<GitException>());
      expect(error, isA<GitMergeNotFastForwardException>());
      expect(error.cause, isNull);
    });

    test('GitInvalidRefNameException is a domain failure without a cause', () {
      final GitInvalidRefNameException error = GitInvalidRefNameException(
        name: '-branche',
        reason: 'it starts with the option marker `-`',
      );

      expect(error, isA<GitException>());
      expect(error, isA<GitInvalidRefNameException>());
      expect(error.name, '-branche');
      expect(error.message, contains('-branche'));
      expect(error.message, contains('the option marker'));
    });
  });
}
