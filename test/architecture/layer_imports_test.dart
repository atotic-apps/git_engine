import 'dart:io';

import 'package:test/test.dart';

/// A layer of `lib/src`, from the most general to the process backend.
///
/// `lib/git_engine.dart` is not a layer: it is a re-export facade outside the
/// graph. It is still classified here so that an inner layer importing it is
/// reported as a dependency on another layer.
enum _Layer {
  core,
  repository,
  client,
  server,
  backend,
  process,
  testing,
  serverIo,
  facade,
}

/// One forbidden dependency, identified by the importing and imported files.
class _Violation {
  const _Violation(this.source, this.target, this.rule);

  final String source;
  final String target;
  final String rule;

  String get key => '$source -> $target';

  String get description => '$key: $rule';
}

/// Import and export directives, including their URI on a separate line.
final RegExp _directivePattern = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

const String _sourceRoot = 'lib';
const String _backendRoot = 'lib/src/backends/';
const String _dartIoAdapterRoot = 'lib/src/server/dart_io/';
const String _gitEngineEntry = 'package:git_engine/git_engine.dart';
const String _backendEntry = 'package:git_engine/backend.dart';

void main() {
  group('lib/src layer imports', () {
    test('no file breaks a layer rule', () {
      expect(
        _allViolations().map((_Violation violation) => violation.description),
        isEmpty,
        reason: 'layer violations are never tolerated',
      );
    });
  });

  group('layer rules', () {
    test('core may only import core', () {
      const String source = 'lib/src/core/errors/custom_exception.dart';
      const String coreImport = "import '../../models/git_oid.dart';";
      const String repositoryImport =
          "import '../../repository/git_repository.dart';";
      expect(_violationsIn(source, coreImport), isEmpty);
      expect(
        _violationsIn(source, repositoryImport).single.rule,
        'core may only import core',
      );
    });

    test('repository may only import core', () {
      const String source = 'lib/src/repository/refs/git_refs.dart';
      const String coreImport = "import '../../models/git_oid.dart';";
      const String backendImport =
          "import '../../backends/process/git_runner.dart';";
      expect(_violationsIn(source, coreImport), isEmpty);
      expect(
        _violationsIn(source, backendImport).single.rule,
        'repository may only import core',
      );
    });

    test('client and server may only import core and repository', () {
      const String client = 'lib/src/client/git_file_client.dart';
      const String server = 'lib/src/server/upload_pack_service.dart';

      expect(
        _violationsIn(client, "import '../repository/git_repository.dart';"),
        isEmpty,
      );
      expect(
        _violationsIn(client, "import '../server/upload_pack_service.dart';")
            .single
            .rule,
        contains('never each other'),
      );
      expect(
        _violationsIn(server, "import '../client/git_file_client.dart';")
            .single
            .rule,
        contains('never each other'),
      );
      expect(
        _violationsIn(server, "import '../backends/process/git_runner.dart';")
            .single
            .rule,
        isNotEmpty,
      );
    });

    test('only the process and testing entries may reach backends', () {
      expect(
        _violationsIn(
          'lib/src/backends/process/process_git_engine.dart',
          "import 'process_git_runner.dart';",
        ),
        isEmpty,
      );
      expect(
        _violationsIn(
          'lib/process.dart',
          "export 'src/backends/process/process_git_engine.dart';",
        ),
        isEmpty,
      );
      expect(
        _violationsIn(
          'lib/testing.dart',
          "export 'src/backends/process/git_runner.dart';",
        ),
        isEmpty,
      );
      expect(
        _violationsIn(
          'lib/git_engine.dart',
          "export 'src/backends/process/git_runner.dart';",
        ).single.rule,
        'only lib/process.dart and lib/testing.dart may import lib/src/backends',
      );
      expect(
        _violationsIn(
          'lib/src/unclassified_helper.dart',
          "import 'backends/process/git_runner.dart';",
        ).single.rule,
        'only lib/process.dart and lib/testing.dart may import lib/src/backends',
      );
    });

    test('a backend file reaches the core only through the two entries', () {
      const String source = 'lib/src/backends/process/git_refusal.dart';
      expect(
        _violationsIn(
          source,
          "import 'package:git_engine/git_engine.dart';",
        ),
        isEmpty,
      );
      expect(
        _violationsIn(
          source,
          "import 'package:git_engine/backend.dart';",
        ),
        isEmpty,
      );
      expect(
        _violationsIn(
          source,
          "import '../../core/errors/git_exception.dart';",
        ).single.rule,
        contains('reaches the core only through'),
      );
      expect(
        _violationsIn(
          source,
          "export 'package:git_engine/src/core/errors/git_exception.dart';",
        ).single.rule,
        contains('reaches the core only through'),
      );
    });

    test('only the server_io entry may reach the dart:io server adapter', () {
      expect(
        _violationsIn(
          'lib/server_io.dart',
          "export 'src/server/dart_io/dart_io_git_http_server.dart';",
        ),
        isEmpty,
      );
      expect(
        _violationsIn(
          'lib/src/server/dart_io/dart_io_body_decoder.dart',
          "import 'dart_io_git_http_server.dart';",
        ),
        isEmpty,
      );
      expect(
        _violationsIn(
          'lib/git_engine.dart',
          "export 'src/server/dart_io/dart_io_git_http_server.dart';",
        ).single.rule,
        'only lib/server_io.dart may reach lib/src/server/dart_io',
      );
    });

    test('external libraries are not layers', () {
      expect(
        _violationsIn(
          'lib/src/core/errors/custom_exception.dart',
          "import 'dart:io';\nimport 'package:test/test.dart';",
        ),
        isEmpty,
      );
    });
  });

  group('server layer purity', () {
    const String dartIoAdapterRoot = 'lib/src/server/dart_io/';

    test('only the dart:io adapter imports dart:io', () {
      final List<String> violations = <String>[];
      final RegExp dartIoImport = RegExp(
        r'''^\s*import\s+['"]dart:io['"]''',
        multiLine: true,
      );
      for (final String path in _dartSourceFiles()) {
        if (_layerOf(path) != _Layer.server) {
          continue;
        }
        if (dartIoImport.hasMatch(File(path).readAsStringSync()) &&
            !path.startsWith(dartIoAdapterRoot)) {
          violations.add(path);
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'the server layer stays independent of the HTTP framework '
            'and of every platform binding, dart:io included, except in its '
            'dart:io adapter folder',
      );
    });

    test('the dart:io adapter imports dart:io', () {
      final RegExp dartIoImport = RegExp(
        r'''^\s*import\s+['"]dart:io['"]''',
        multiLine: true,
      );
      final bool found = _dartSourceFiles().any(
        (String path) =>
            path.startsWith(dartIoAdapterRoot) &&
            dartIoImport.hasMatch(File(path).readAsStringSync()),
      );
      expect(found, isTrue, reason: 'the adapter is where dart:io belongs');
    });
  });

  group('process backend seam purity', () {
    /// The seam contracts: file operations and platform facts, described
    /// without a single platform binding so tests run without a disk.
    const List<String> seamContracts = <String>[
      'lib/src/backends/process/git_file_system.dart',
      'lib/src/backends/process/git_platform.dart',
      'lib/src/backends/process/git_runner.dart',
      'lib/src/backends/process/memory_git_file_system.dart',
    ];

    /// The dart:io side of those seams, one file per implementation.
    const List<String> seamImplementations = <String>[
      'lib/src/backends/process/process_git_file_system.dart',
      'lib/src/backends/process/process_git_platform.dart',
    ];

    final RegExp dartIoImport = RegExp(
      r'''^\s*import\s+['"]dart:io['"]''',
      multiLine: true,
    );

    test('the seam contracts do not import dart:io', () {
      final List<String> violations = <String>[
        for (final String path in seamContracts)
          if (dartIoImport.hasMatch(File(path).readAsStringSync())) path,
      ];
      expect(
        violations,
        isEmpty,
        reason: 'the seam contracts are pure descriptions: dart:io stays '
            'in their process implementations',
      );
    });

    test('the dart:io implementations stay in the process backend', () {
      for (final String path in seamImplementations) {
        final File file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path is missing');
        expect(
          dartIoImport.hasMatch(file.readAsStringSync()),
          isTrue,
          reason: '$path is the dart:io side of the seam',
        );
      }
    });
  });
}

/// Every layer violation in `lib/src`, sorted by key.
List<_Violation> _allViolations() {
  final List<_Violation> violations = <_Violation>[];
  for (final String path in _dartSourceFiles()) {
    violations.addAll(_violationsIn(path, File(path).readAsStringSync()));
  }
  violations.sort(
    (_Violation first, _Violation second) => first.key.compareTo(second.key),
  );
  return violations;
}

/// The Dart files under `lib`, as normalized package-relative paths.
List<String> _dartSourceFiles() {
  final List<String> files = Directory(_sourceRoot)
      .listSync(recursive: true)
      .whereType<File>()
      .map((File file) => _normalize(file.path))
      .where((String path) => path.endsWith('.dart'))
      .toList();
  files.sort();
  return files;
}

/// Layer violations of [source] whose contents are [contents].
List<_Violation> _violationsIn(String source, String contents) {
  final _Layer? sourceLayer = _layerOf(source);
  final List<_Violation> violations = <_Violation>[];
  for (final RegExpMatch match in _directivePattern.allMatches(contents)) {
    final String uri = match.group(1)!;
    final String? target = _resolveUri(source, uri);
    if (target == null) {
      continue;
    }
    if (source.startsWith(_backendRoot) &&
        _isCoreFile(target) &&
        uri != _gitEngineEntry &&
        uri != _backendEntry) {
      violations.add(
        _Violation(
          source,
          target,
          'a backend file reaches the core only through $_gitEngineEntry '
          'and $_backendEntry',
        ),
      );
      continue;
    }
    if (target.startsWith(_dartIoAdapterRoot) &&
        !source.startsWith(_dartIoAdapterRoot) &&
        source != 'lib/server_io.dart') {
      violations.add(
        _Violation(
          source,
          target,
          'only lib/server_io.dart may reach lib/src/server/dart_io',
        ),
      );
      continue;
    }
    final _Layer? targetLayer = _layerOf(target);
    if (targetLayer == null) {
      continue;
    }
    final String? rule = _ruleBetween(sourceLayer, targetLayer);
    if (rule != null) {
      violations.add(_Violation(source, target, rule));
    }
  }
  return violations;
}

/// The layer [path] belongs to, or null for a file outside every layer.
_Layer? _layerOf(String path) {
  if (path == 'lib/git_engine.dart') {
    return _Layer.facade;
  }
  if (path == 'lib/process.dart') {
    return _Layer.process;
  }
  if (path == 'lib/testing.dart') {
    return _Layer.testing;
  }
  if (path == 'lib/server_io.dart') {
    return _Layer.serverIo;
  }
  if (path.startsWith('lib/src/core/') || path.startsWith('lib/src/models/')) {
    return _Layer.core;
  }
  if (path.startsWith('lib/src/repository/')) {
    return _Layer.repository;
  }
  if (path.startsWith('lib/src/client/')) {
    return _Layer.client;
  }
  if (path.startsWith('lib/src/server/')) {
    return _Layer.server;
  }
  if (path.startsWith('lib/src/backends/')) {
    return _Layer.backend;
  }
  return null;
}

/// The rule [target] breaks for a file of layer [source], or null when the
/// dependency is allowed.
String? _ruleBetween(_Layer? source, _Layer target) {
  switch (source) {
    case _Layer.core:
      return target == _Layer.core ? null : 'core may only import core';
    case _Layer.repository:
      return target == _Layer.core || target == _Layer.repository
          ? null
          : 'repository may only import core';
    case _Layer.client:
    case _Layer.server:
      final bool allowed = target == _Layer.core ||
          target == _Layer.repository ||
          target == source;
      return allowed
          ? null
          : 'client and server may only import core and repository, '
              'and never each other';
    case _Layer.backend:
      return null;
    case _Layer.process:
    case _Layer.testing:
      final bool allowed = target == _Layer.core || target == _Layer.backend;
      return allowed
          ? null
          : 'the process and testing entries may only reach core and backends';
    case _Layer.serverIo:
      final bool allowed = target == _Layer.core || target == _Layer.server;
      return allowed
          ? null
          : 'the server_io entry may only reach core and the server layer';
    case _Layer.facade:
      return target == _Layer.backend
          ? 'only lib/process.dart and lib/testing.dart may import '
              'lib/src/backends'
          : null;
    case null:
      return target == _Layer.backend
          ? 'only lib/process.dart and lib/testing.dart may import '
              'lib/src/backends'
          : null;
  }
}

/// Whether [path] belongs to the core layers a backend reads through its two
/// entry points.
bool _isCoreFile(String path) {
  return path.startsWith('lib/src/core/') ||
      path.startsWith('lib/src/models/') ||
      path.startsWith('lib/src/repository/') ||
      path.startsWith('lib/src/client/') ||
      path.startsWith('lib/src/server/');
}

/// The package-relative file [uri] points at, or null for an external
/// library.
String? _resolveUri(String source, String uri) {
  if (uri.startsWith('dart:')) {
    return null;
  }
  if (uri.startsWith('package:git_engine/')) {
    return _normalize('lib/${uri.substring('package:git_engine/'.length)}');
  }
  if (uri.contains(':')) {
    return null;
  }
  final int slash = source.lastIndexOf('/');
  final String directory = slash < 0 ? '' : source.substring(0, slash);
  return _normalize('$directory/$uri');
}

/// [path] with forward slashes and no `.` or `..` segment.
String _normalize(String path) {
  final List<String> parts = path.replaceAll('\\', '/').split('/');
  final List<String> normalized = <String>[];
  for (final String part in parts) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (normalized.isNotEmpty) {
        normalized.removeLast();
      }
      continue;
    }
    normalized.add(part);
  }
  return normalized.join('/');
}
