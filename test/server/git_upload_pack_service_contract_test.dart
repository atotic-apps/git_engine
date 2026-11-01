import '../support/fake_upload_pack_service.dart';
import '../contract/server/git_upload_pack_service_contract.dart';

void main() {
  defineGitUploadPackServiceContract(FakeUploadPackService.new);
}
