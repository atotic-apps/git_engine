@Tags(['git'])
library;

import 'package:test/test.dart';

import '../../../contract/client/git_file_client_contract.dart';
import '../../../contract/client/git_file_client_exchange_contract.dart';
import '../../../contract/client/git_file_client_pull_contract.dart';
import '../process_backend_factory.dart';

/// Runs the GitFileClient contracts against the process backend.
void main() {
  defineGitFileClientContract(const ProcessBackendFactory());
  defineGitFileClientPullContract(const ProcessBackendFactory());
  defineGitFileClientExchangeContract(const ProcessBackendFactory());
}
