@Tags(['git'])
library;

import 'package:test/test.dart';

import '../../../contract/repository/git_ref_transaction_contract.dart';
import '../process_backend_factory.dart';

void main() {
  refTransactionContractTests(const ProcessBackendFactory());
}
