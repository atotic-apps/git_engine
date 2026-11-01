@Tags(['git'])
library;

import 'package:git_engine/src/backends/process/git_version.dart';
import 'package:git_engine/src/backends/process/process_git_engine.dart';
import 'package:test/test.dart';

import '../../../contract/repository/git_config_contract.dart';
import '../../../contract/repository/git_directory_files_contract.dart';
import '../../../contract/repository/git_exception_contract.dart';
import '../../../contract/repository/git_branches_contract.dart';
import '../../../contract/repository/git_history_contract.dart';
import '../../../contract/repository/git_index_contract.dart';
import '../../../contract/repository/git_objects_contract.dart';
import '../../../contract/repository/git_merge_contract.dart';
import '../../../contract/repository/git_patches_apply_contract.dart';
import '../../../contract/repository/git_patches_contract.dart';
import '../../../contract/repository/git_ref_reader_contract.dart';
import '../../../contract/repository/git_refs_contract.dart';
import '../../../contract/repository/git_ref_name_contract.dart';
import '../../../contract/repository/git_repository_manager_contract.dart';
import '../../../contract/repository/git_repository_type_contract.dart';
import '../../../contract/repository/git_repository_writer_contract.dart';
import '../../../contract/repository/git_revision_resolver_contract.dart';
import '../../../contract/repository/git_tags_contract.dart';
import '../../../contract/repository/git_temporary_index_contract.dart';
import '../../../contract/repository/git_working_merge_contract.dart';
import '../process_backend_factory.dart';

/// Runs the repository manager, ref reader, refs, revision resolver, history,
/// config, objects, git directory files, patches, repository writer,
/// repository type, temporary index, index, merge, working merge, branches
/// and tags contract suites against the process backend, on a working clone
/// and on a bare clone.
Future<void> main() async {
  final bool supportsMergeTree = await _supportsMergeTree();
  defineGitRepositoryManagerContract(const ProcessBackendFactory());
  defineGitRefReaderContract(const ProcessBackendFactory());
  defineGitRefsContract(const ProcessBackendFactory());
  defineGitRefNameContract(const ProcessBackendFactory());
  defineGitRevisionResolverContract(const ProcessBackendFactory());
  defineGitHistoryContract(const ProcessBackendFactory());
  defineGitConfigContract(const ProcessBackendFactory());
  defineGitExceptionContract(const ProcessBackendFactory());
  defineGitObjectsContract(const ProcessBackendFactory());
  defineGitDirectoryFilesContract(const ProcessBackendFactory());
  defineGitPatchesContract(const ProcessBackendFactory());
  defineGitPatchesApplyContract(const ProcessBackendFactory());
  defineGitRepositoryWriterContract(const ProcessBackendFactory());
  defineGitRepositoryTypeContract(const ProcessBackendFactory());
  defineGitTemporaryIndexContract(const ProcessBackendFactory());
  defineGitIndexContract(const ProcessBackendFactory());
  defineGitMergeContract(
    const ProcessBackendFactory(),
    supportsMergeTree: supportsMergeTree,
  );
  defineGitWorkingMergeContract(const ProcessBackendFactory());
  defineGitBranchesContract(const ProcessBackendFactory());
  defineGitTagsContract(const ProcessBackendFactory());
}

/// Whether the installed git can run `merge-tree --write-tree` (2.38 or
/// newer).
Future<bool> _supportsMergeTree() async {
  final String raw = await ProcessGitEngine().gitVersion();
  final GitVersionTriple? installed = parseGitVersion(raw);
  if (installed == null) {
    throw FormatException('Cannot parse git version from: "$raw"', raw);
  }
  return compareGitVersions(installed, (2, 38, 0)) >= 0;
}
