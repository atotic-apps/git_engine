/// Rules shared by the engines maintained with the package.
///
/// Import this library to apply the common remote-location, reference-name
/// and diagnostic rules to a backend.
library;

export 'src/client/git_remote_location.dart' show checkRemoteLocation;
export 'src/core/errors/git_exception.dart' show maxDiagnosticChainLength;
export 'src/core/redact_url_userinfo.dart'
    show redactGitArguments, redactUrlUserinfo;
export 'src/models/git_directory_snapshot.dart' show relativePathError;
export 'src/repository/refs/git_ref_name_rules.dart'
    show
        checkBranchName,
        checkTagName,
        checkWritableRefName,
        readsAsOption,
        refuseOptionLikeRevision;
