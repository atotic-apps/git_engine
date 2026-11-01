@Tags(['git'])
library;

import 'package:test/test.dart';

import '../../../contract/repository/git_directory_confinement_contract.dart';
import '../process_backend_factory.dart';

/// Runs the git-directory confinement contract against the process backend.
void main() {
  defineGitDirectoryConfinementContract(const ProcessBackendFactory());
}
