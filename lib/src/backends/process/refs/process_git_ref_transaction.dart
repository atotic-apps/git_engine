import 'dart:convert';
import 'dart:typed_data';

import 'package:git_engine/backend.dart';
import 'package:git_engine/git_engine.dart';
import '../git_command_exception.dart';
import '../process_git_repository.dart';
import 'ref_update_failure.dart';

/// NUL byte terminating every field of the script.
const int _nul = 0x00;

/// [GitRefTransaction] implementation running one `update-ref --stdin -z`
/// command in the owning repository's context.
///
/// The staged commands travel on standard input, every field closed by a NUL
/// byte, so a name or a value can never read as a further command of the
/// script. An old value that the staging call did not give is written as an
/// empty field, the way the `-z` grammar of the documentation of `git
/// update-ref` marks its absence; the fields a name could then hide behind
/// are already ruled out by the name validation of the staging methods. The
/// commands are sent between `start` and `prepare`, followed by `commit`:
/// git locks and verifies every reference during `prepare`, so a wrong
/// expected value refuses the whole transaction before anything is written.
class ProcessGitRefTransaction implements GitRefTransaction {
  /// Repository whose context the transaction command runs in.
  final ProcessGitRepository repository;

  final List<List<String>> _commands = <List<String>>[];
  bool _committed = false;

  /// Creates a transaction running commands through [repository]'s context.
  ProcessGitRefTransaction({required this.repository});

  @override
  void update(String ref, GitOid newOid, {GitOid? expectedOld}) {
    checkWritableRefName(ref);
    _stage(<String>[
      'update',
      ref,
      newOid.value,
      expectedOld?.value ?? '',
    ]);
  }

  @override
  void create(String ref, GitOid oid) {
    checkWritableRefName(ref);
    _stage(<String>['create', ref, oid.value]);
  }

  @override
  void delete(String ref, {GitOid? expectedOld}) {
    checkWritableRefName(ref);
    _stage(<String>[
      'delete',
      ref,
      expectedOld?.value ?? '',
    ]);
  }

  /// Records one command, refusing to change a committed transaction.
  void _stage(List<String> fields) {
    if (_committed) {
      throw StateError('the reference transaction is already committed');
    }
    _commands.add(fields);
  }

  @override
  Future<void> commit() async {
    if (_committed) {
      throw StateError('the reference transaction is already committed');
    }
    _committed = true;
    final Uint8List script = _script();
    try {
      await repository.runCommand(
        const <String>['update-ref', '--stdin', '-z'],
        stdin: script,
      );
    } on GitCommandException catch (error) {
      if (isExpectedValueMismatch(error)) {
        throw GitRefMismatchException(cause: error);
      }
      rethrow;
    }
  }

  /// The staged commands, sent once more, as the `-z` script git reads:
  /// `start`, every staged command, `prepare`, `commit`. A command with no
  /// field is closed by one NUL byte; a command with fields carries them
  /// after one space, each closed by a NUL byte.
  Uint8List _script() {
    final BytesBuilder script = BytesBuilder();
    void writeCommand(List<String> fields) {
      script.add(utf8.encode(fields[0]));
      if (fields.length > 1) {
        script.add(utf8.encode(' '));
      }
      for (final String field in fields.skip(1)) {
        script.add(utf8.encode(field));
        script.add(<int>[_nul]);
      }
      if (fields.length == 1) {
        script.add(<int>[_nul]);
      }
    }

    writeCommand(<String>['start']);
    for (final List<String> command in _commands) {
      writeCommand(command);
    }
    writeCommand(<String>['prepare']);
    writeCommand(<String>['commit']);
    return script.takeBytes();
  }
}
