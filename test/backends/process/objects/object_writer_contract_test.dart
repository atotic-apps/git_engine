@Tags(['git'])
library;

import 'package:test/test.dart';

import '../../../contract/repository/git_object_writer_contract.dart';
import '../process_backend_factory.dart';

void main() {
  defineGitObjectWriterContract(const ProcessBackendFactory());
}
