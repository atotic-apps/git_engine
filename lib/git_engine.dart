/// The package's backend-independent API: engine and repository contracts,
/// value types, error hierarchy and server contracts.
/// {@category Getting started}
///
/// Program against its interfaces, whatever the backend.
library;

export 'src/core/errors/git_engine_unavailable_exception.dart'
    show GitEngineUnavailableException;
export 'src/core/errors/git_feature_unavailable_exception.dart'
    show GitFeatureUnavailableException;
export 'src/core/git_engine_runtime.dart' show GitEngineRuntime;
export 'src/core/errors/git_output_limit_exception.dart'
    show GitOutputLimitException;
export 'src/core/errors/git_timeout_exception.dart' show GitTimeoutException;
export 'src/core/errors/git_version_exception.dart' show GitVersionException;
export 'src/client/git_authentication_exception.dart'
    show GitAuthenticationException;
export 'src/client/git_file_client.dart' show GitFileClient;
export 'src/client/git_no_upstream_exception.dart' show GitNoUpstreamException;
export 'src/client/git_push_rejected_exception.dart'
    show GitPushRejectedException;
export 'src/client/git_remote_ref_not_found_exception.dart'
    show GitRemoteRefNotFoundException;
export 'src/client/git_remote_repository_not_found_exception.dart'
    show GitRemoteRepositoryNotFoundException;
export 'src/client/git_remote_unreachable_exception.dart'
    show GitRemoteUnreachableException;
export 'src/client/git_unsupported_url_exception.dart'
    show GitUnsupportedUrlException;
export 'src/core/errors/git_exception.dart' show GitException;
export 'src/core/errors/git_not_a_bare_repository_exception.dart'
    show GitNotABareRepositoryException;
export 'src/core/errors/git_not_a_repository_exception.dart'
    show GitNotARepositoryException;
export 'src/core/errors/git_not_a_working_repository_exception.dart'
    show GitNotAWorkingRepositoryException;
export 'src/core/errors/git_occupied_directory_exception.dart'
    show GitOccupiedDirectoryException;
export 'src/core/errors/git_repository_kind_exception.dart'
    show GitRepositoryKindException;
export 'src/models/git_apply_result.dart'
    show GitApplyApplied, GitApplyConflicted, GitApplyRefused, GitApplyResult;
export 'src/models/git_archive_format.dart' show GitArchiveFormat;
export 'src/models/git_branch.dart' show GitBranch;
export 'src/models/git_change_kind.dart' show GitChangeKind;
export 'src/models/git_commit.dart' show GitCommit;
export 'src/models/git_conflict_region.dart' show GitConflictRegion;
export 'src/models/git_config_entry.dart' show GitConfigEntry;
export 'src/models/git_directory_drift.dart' show GitDirectoryDrift;
export 'src/models/git_directory_snapshot.dart' show GitDirectorySnapshot;
export 'src/models/git_identity.dart' show GitIdentity;
export 'src/models/git_log_commit.dart' show GitLogCommit;
export 'src/models/git_log_entry.dart' show GitLogEntry;
export 'src/models/git_merge_mode.dart' show GitMergeMode;
export 'src/models/git_merge_result.dart'
    show
        GitMergeCommit,
        GitMergeConflicts,
        GitMergeFastForward,
        GitMergeResult,
        GitMergeStopped,
        GitMergeUpToDate;
export 'src/models/git_merge_tree_result.dart' show GitMergeTreeResult;
export 'src/models/git_object_type.dart' show GitObjectType;
export 'src/models/git_oid.dart' show GitOid;
export 'src/models/git_raw_object.dart' show GitRawObject;
export 'src/models/git_ref.dart' show GitRef;
export 'src/models/git_reset_mode.dart' show GitResetMode;
export 'src/models/git_status_entry.dart' show GitFileState, GitStatusEntry;
export 'src/models/git_tag.dart' show GitTag;
export 'src/models/git_tag_fetch.dart' show GitTagFetch;
export 'src/models/git_tag_ref.dart' show GitTagRef;
export 'src/models/git_tree.dart' show GitTree, GitTreeEntry;
export 'src/models/git_unmerged_entry.dart' show GitUnmergedEntry;
export 'src/repository/branches/git_branches.dart' show GitBranches;
export 'src/repository/config/git_config.dart' show GitConfig;
export 'src/repository/gitdir/git_directory_files.dart' show GitDirectoryFiles;
export 'src/repository/git_bare_repository.dart' show GitBareRepository;
export 'src/repository/git_repository_manager.dart' show GitRepositoryManager;
export 'src/repository/git_file_bare_repository.dart'
    show GitFileBareRepository;
export 'src/repository/git_file_repository.dart' show GitFileRepository;
export 'src/repository/git_indexed_repository.dart' show GitIndexedRepository;
export 'src/repository/git_repository.dart' show GitRepository;
export 'src/repository/git_repository_reader.dart' show GitRepositoryReader;
export 'src/repository/git_repository_writer.dart' show GitRepositoryWriter;
export 'src/repository/git_working_repository.dart' show GitWorkingRepository;
export 'src/repository/history/git_history.dart' show GitHistory;
export 'src/repository/history/git_history_reader.dart' show GitHistoryReader;
export 'src/repository/index/git_index.dart' show GitIndex;
export 'src/repository/merge/git_merge.dart' show GitMerge;
export 'src/repository/merge/git_merge_not_fast_forward_exception.dart'
    show GitMergeNotFastForwardException;
export 'src/repository/merge/git_no_merge_in_progress_exception.dart'
    show GitNoMergeInProgressException;
export 'src/repository/merge/git_unrelated_histories_exception.dart'
    show GitUnrelatedHistoriesException;
export 'src/repository/merge/git_working_merge.dart' show GitWorkingMerge;
export 'src/repository/objects/git_object_reader.dart' show GitObjectReader;
export 'src/repository/objects/git_object_store.dart' show GitObjectStore;
export 'src/repository/objects/git_invalid_object_exception.dart'
    show GitInvalidObjectException;
export 'src/repository/objects/git_object_writer.dart' show GitObjectWriter;
export 'src/repository/objects/git_objects.dart' show GitObjects;
export 'src/repository/patches/git_indexed_patches.dart' show GitIndexedPatches;
export 'src/repository/patches/git_patches.dart' show GitPatches;
export 'src/repository/patches/git_working_patches.dart' show GitWorkingPatches;
export 'src/repository/refs/git_branch_not_merged_exception.dart'
    show GitBranchNotMergedException;
export 'src/repository/refs/git_invalid_ref_name_exception.dart'
    show GitInvalidRefNameException;
export 'src/repository/refs/git_ref_exists_exception.dart'
    show GitRefExistsException;
export 'src/repository/refs/git_ref_mismatch_exception.dart'
    show GitRefMismatchException;
export 'src/repository/refs/git_ref_reader.dart' show GitRefReader;
export 'src/repository/refs/git_ref_transaction.dart' show GitRefTransaction;
export 'src/repository/refs/git_ref_not_found_exception.dart'
    show GitRefNotFoundException;
export 'src/repository/refs/git_refs.dart' show GitRefs;
export 'src/repository/refs/git_unknown_revision_exception.dart'
    show GitUnknownRevisionException;
export 'src/repository/refs/git_revision_resolver.dart'
    show GitRevisionResolver;
export 'src/repository/refs/git_revisions.dart' show GitRevisions;
export 'src/repository/remotes/git_remotes.dart' show GitRemotes;
export 'src/repository/tags/git_tags.dart' show GitTags;
export 'src/repository/worktree/git_local_changes_overwritten_exception.dart'
    show GitLocalChangesOverwrittenException;
export 'src/repository/worktree/git_worktree.dart' show GitWorktree;
export 'src/server/git_authorization_policy.dart'
    show GitAuthorizationPolicy, GitReadOnlyAuthorizationPolicy;
export 'src/server/git_http_headers.dart' show GitHttpHeaders;
export 'src/server/git_http_request.dart' show GitHttpRequest;
export 'src/server/git_http_response.dart' show GitHttpResponse;
export 'src/server/git_principal.dart' show GitPrincipal;
export 'src/server/git_protocol_parameters.dart' show GitProtocolParameters;
export 'src/server/git_served_repository_id.dart' show GitServedRepositoryId;
export 'src/server/git_service_response.dart' show GitServiceResponse;
export 'src/server/git_smart_http_handler.dart'
    show GitHttpBodyDecoder, GitSmartHttpHandler;
export 'src/server/git_unknown_served_repository_exception.dart'
    show GitUnknownServedRepositoryException;
export 'src/server/git_upload_pack_service.dart' show GitUploadPackService;
