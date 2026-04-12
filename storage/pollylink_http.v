module storage

import encoding.base64
import json
import net.http
import os

pub struct PollyLinkOfferEnvelope {
pub:
	offer    SyncOffer
	manifest SyncManifest
}

struct SyncOfferRequestDto {
	repo_name        string
	branch_name      string
	prediction_depth int
	target_branch    string
}

struct SyncNegotiateRequestDto {
	repo_name    string
	offer        SyncOfferDto
	manifest     SyncManifestDto
	use_manifest bool
}

struct SyncExchangeRequestDto {
	repo_name string
	offer     SyncOfferDto
	missing   SyncMissingSetDto
}

struct SyncFullExchangeRequestDto {
	repo_name string
	offer     SyncOfferDto
}

struct SyncApplyRequestDto {
	repo_name string
	exchange  SyncExchangeDto
}

struct SidecarRepoOpenRequestDto {
	repo_name      string
	default_branch string
}

struct SidecarBranchListDto {
	branches []BranchDto
}

struct SidecarBranchStatusListDto {
	branches []SidecarBranchStatusDto
}

struct SidecarProjectorValueDto {
	name                         string
	branch_name                  string
	value                        i64
	current_data_root_cid        string
	source_data_root_cid         string
	virtual_root_cid             string
	fresh                        bool
	stale_reason                 string
	source_json_path             string
	source_field_selector_meta   SidecarFieldSelectorMetaDto
	source_field_selector_plugin string
	source_field_selector        string
	source_markdown_selector     string
}

struct SidecarFieldSelectorMetaDto {
	plugin_name string
	selector    string
	value_type  string
	stores_row  bool
}

struct SidecarMarkdownMetricDto {
	branch_name string
	table_name  string
	column_name string
	selector    string
	value       i64
}

struct SidecarTypedRowDto {
	primary_key string
	values      map[string]string
}

struct SidecarIndexLookupDto {
	branch_name         string
	table_name          string
	index_name          string
	field_selector_meta SidecarFieldSelectorMetaDto
	query_kind          string
	value               string
	rows                []SidecarTypedRowDto
}

struct SidecarColumnDefDto {
	name        string
	typ         string
	nullable    bool
	aggregate   string
	enum_values []string
}

struct SidecarIndexDefDto {
	name                string
	column              string
	stores_row          bool
	json_field          string
	value_type          string
	field_selector_meta SidecarFieldSelectorMetaDto
}

struct SidecarTableSpecDto {
	branch_name string
	table_name  string
	primary_key []string
	columns     []SidecarColumnDefDto
	indexes     []SidecarIndexDefDto
}

struct SidecarQuerySchemaColumnDto {
	name          string
	typ           string
	nullable      bool
	filter_ops    []string
	index_names   []string
	planner_hints []SidecarQueryPlannerHintDto
	filter_shapes []SidecarQueryFilterShapeDto
}

struct SidecarQueryPlannerHintDto {
	op         string
	strategy   string
	index_name string
	stores_row bool
	score      int
}

struct SidecarQueryFilterShapeDto {
	op                  string
	value_type          string
	indexed             bool
	index_name          string
	planner_strategy    string
	planner_score       int
	projection_only     bool
	continuation_anchor bool
	sample_explain      SidecarQuerySamplePlanExplainDto
}

struct SidecarFtsShapeDto {
	kind             string
	indexed          bool
	index_name       string
	planner_strategy string
	sample_explain   SidecarQuerySamplePlanExplainDto
}

struct SidecarQuerySamplePlanExplainDto {
	strategy                    string
	index_name                  string
	warnings                    []string
	notes                       []string
	default_result_shape        string
	supports_continuation_token bool
}

struct SidecarQuerySchemaIndexDto {
	name                string
	column_name         string
	value_type          string
	stores_row          bool
	is_fts              bool
	fts_query_kinds     []string
	fts_shapes          []SidecarFtsShapeDto
	json_field          string
	field_selector_meta SidecarFieldSelectorMetaDto
	filter_ops          []string
}

struct SidecarGeneralFtsQueryPlanDto {
	strategy    string
	index_name  string
	column_name string
	backend     string
	query_kind  string
	term_count  int
	limit       int
}

struct SidecarGeneralFtsQueryRequestDto {
	repo_name      string
	branch_name    string
	table_name     string
	index_name     string
	query_kind     string
	terms          []string
	select_columns []string
	limit          int
}

struct SidecarGeneralFtsQueryPreviewDto {
	branch_name string
	table_name  string
	index_name  string
	query_kind  string
	terms       []string
	plan        SidecarGeneralFtsQueryPlanDto
}

struct SidecarGeneralFtsHitDto {
	primary_key string
	score       f64
	snippet     string
}

struct SidecarGeneralFtsQueryResultDto {
	branch_name    string
	table_name     string
	index_name     string
	query_kind     string
	terms          []string
	select_columns []string
	plan           SidecarGeneralFtsQueryPlanDto
	hits           []SidecarGeneralFtsHitDto
	rows           []SidecarTypedRowDto
}

struct SidecarQuerySchemaFieldSelectorDto {
	column_name      string
	plugin_name      string
	selector         string
	value_type       string
	stores_row       bool
	filter_ops       []string
	index_names      []string
	projection_names []string
	planner_hints    []SidecarQueryPlannerHintDto
	filter_shapes    []SidecarQueryFilterShapeDto
	fts_query_kinds  []string
	fts_shapes       []SidecarFtsShapeDto
}

struct SidecarQuerySchemaProjectionDto {
	name             string
	column_name      string
	source_json_path string
	plugin_name      string
	selector         string
	value_type       string
	aggregate        string
	priority         int
	cost_hint        string
}

struct SidecarQuerySchemaDto {
	branch_name                 string
	table_name                  string
	primary_key                 []string
	columns                     []SidecarQuerySchemaColumnDto
	indexes                     []SidecarQuerySchemaIndexDto
	field_selectors             []SidecarQuerySchemaFieldSelectorDto
	projection_metrics          []SidecarQuerySchemaProjectionDto
	supported_filter_ops        []string
	default_result_shape        string
	supports_continuation_token bool
	supports_select_projection  bool
}

struct SidecarMarkdownQueryDto {
	branch_name         string
	table_name          string
	column_name         string
	selector            string
	index_name          string
	field_selector_meta SidecarFieldSelectorMetaDto
	query_kind          string
	value               string
	metric_value        i64
	rows                []SidecarTypedRowDto
}

struct SidecarQueryPlanDto {
	strategy          string
	index_name        string
	index_filter      SidecarQueryFilterDto
	post_filters      []SidecarQueryFilterDto
	post_filter_count int
	limit             int
}

struct SidecarQueryRowsDto {
	branch_name             string
	table_name              string
	column_name             string
	plugin_name             string
	selector                string
	field_selector_meta     SidecarFieldSelectorMetaDto
	query_kind              string
	value                   string
	general_fts             SidecarGeneralFtsClauseDto
	select_columns          []string
	start_primary_key       string
	start_index_value       string
	continuation_token      string
	plan                    SidecarQueryPlanDto
	cursor                  SidecarQueryCursorDto
	general_fts_hits        []SidecarGeneralFtsHitDto
	has_more                bool
	next_primary_key        string
	next_index_value        string
	next_continuation_token string
	rows                    []SidecarTypedRowDto
}

struct SidecarQueryCursorDto {
	has_more                bool
	next_primary_key        string
	next_index_value        string
	next_continuation_token string
}

struct SidecarQueryFilterDto {
	column_name  string
	plugin_name  string
	selector     string
	query_kind   string
	value        string
	second_value string
}

struct SidecarGeneralFtsClauseDto {
	index_name string
	query_kind string
	terms      []string
}

struct SidecarQueryRowsPostRequestDto {
	repo_name          string
	branch_name        string
	table_name         string
	filters            []SidecarQueryFilterDto
	general_fts        SidecarGeneralFtsClauseDto
	select_columns     []string
	start_primary_key  string
	start_index_value  string
	continuation_token string
	limit              int
}

struct SidecarQueryPlanPreviewDto {
	branch_name                 string
	table_name                  string
	filters                     []SidecarQueryFilterDto
	general_fts                 SidecarGeneralFtsClauseDto
	select_columns              []string
	plan                        SidecarQueryPlanDto
	explain                     SidecarQuerySamplePlanExplainDto
	warnings                    []string
	notes                       []string
	default_result_shape        string
	supports_continuation_token bool
}

struct SidecarRepoListDto {
	repos []string
}

struct SidecarRepoSummaryListDto {
	repos []SidecarRepositoryInfoDto
}

struct SidecarRepoInfoQueryDto {
	repo SidecarRepositoryInfoDto
}

struct SidecarGovernanceStatusDto {
	auth_enabled        bool
	token_count         int
	repo_count          int
	requests_per_minute int
	recent_requests_1m  int
	recent_denies_1m    int
	recent_categories   []SidecarGovernanceCategoryDto
	recent_actors       []SidecarGovernanceActorDto
	recent_actions      []SidecarGovernanceActionDto
}

struct SidecarGovernanceCategoryDto {
	category           string
	recent_requests_1m int
	recent_denies_1m   int
}

struct SidecarGovernanceActorDto {
	actor              string
	recent_requests_1m int
	recent_denies_1m   int
}

struct SidecarGovernanceActionDto {
	action             string
	recent_requests_1m int
	recent_denies_1m   int
}

struct SidecarRepositoryInfoDto {
	repo_name             string
	default_branch        string
	branch_count          int
	latest_branch         string
	latest_commit_cid     string
	latest_timestamp      i64
	auth_enabled          bool
	allow_push_to_default bool
	require_auto_merge    bool
	default_sync_policy   string
	protection_summary    string
}

pub struct SidecarRepositoryInfo {
pub:
	repo_name             string
	default_branch        string
	branch_count          int
	latest_branch         string
	latest_commit_cid     string
	latest_timestamp      i64
	auth_enabled          bool
	allow_push_to_default bool
	require_auto_merge    bool
	default_sync_policy   string
	protection_summary    string
}

struct SidecarBranchPolicyInfo {
	policy_scope        string
	allow_push          bool
	require_auto_merge  bool
	default_sync_policy string
}

struct SidecarBranchActivityDto {
	branch       BranchDto
	root_cid     string
	parent_count int
	author       string
	message      string
	timestamp    i64
}

struct SidecarBranchLogDto {
	commits []CommitDto
}

struct SidecarRepoActivityDto {
	entries []SidecarRepoActivityEntryDto
}

struct SidecarRepoActivityEntryDto {
	repo_name    string
	branch       BranchDto
	root_cid     string
	parent_count int
	author       string
	message      string
	timestamp    i64
}

struct CommitDto {
	cid          string
	root_cid     string
	parent_count int
	author       string
	message      string
	timestamp    i64
}

pub struct SidecarBranchActivity {
pub:
	branch       Branch
	root_cid     string
	parent_count int
	author       string
	message      string
	timestamp    i64
}

struct SidecarBranchStatusDto {
	branch                                BranchDto
	root_cid                              string
	parent_count                          int
	author                                string
	message                               string
	timestamp                             i64
	merge_relation                        string
	projector_fresh                       int
	projector_stale                       int
	stale_projectors                      []string
	recommended_projection_refresh_policy string
	policy_scope                          string
	allow_push                            bool
	require_auto_merge                    bool
	default_sync_policy                   string
	protection_summary                    string
}

pub struct SidecarBranchStatus {
pub:
	branch                                Branch
	root_cid                              string
	parent_count                          int
	author                                string
	message                               string
	timestamp                             i64
	merge_relation                        string
	projector_fresh                       int
	projector_stale                       int
	stale_projectors                      []string
	recommended_projection_refresh_policy string
	policy_scope                          string
	allow_push                            bool
	require_auto_merge                    bool
	default_sync_policy                   string
	protection_summary                    string
}

pub struct SidecarProjectorValue {
pub:
	name                         string
	branch_name                  string
	value                        i64
	current_data_root_cid        string
	source_data_root_cid         string
	virtual_root_cid             string
	fresh                        bool
	stale_reason                 string
	source_json_path             string
	source_field_selector_meta   SidecarFieldSelectorMeta
	source_field_selector_plugin string
	source_field_selector        string
	source_markdown_selector     string
}

pub struct SidecarFieldSelectorMeta {
pub:
	plugin_name string
	selector    string
	value_type  string
	stores_row  bool
}

pub struct SidecarMarkdownMetric {
pub:
	branch_name string
	table_name  string
	column_name string
	selector    string
	value       i64
}

pub struct SidecarTypedRow {
pub:
	primary_key string
	values      map[string]string
}

pub struct SidecarIndexLookup {
pub:
	branch_name         string
	table_name          string
	index_name          string
	field_selector_meta SidecarFieldSelectorMeta
	query_kind          string
	value               string
	rows                []SidecarTypedRow
}

pub struct SidecarColumnDef {
pub:
	name        string
	typ         string
	nullable    bool
	aggregate   string
	enum_values []string
}

pub struct SidecarIndexDef {
pub:
	name                string
	column              string
	stores_row          bool
	json_field          string
	value_type          string
	field_selector_meta SidecarFieldSelectorMeta
}

pub struct SidecarTableSpec {
pub:
	branch_name string
	table_name  string
	primary_key []string
	columns     []SidecarColumnDef
	indexes     []SidecarIndexDef
}

pub struct SidecarQuerySchemaColumn {
pub:
	name          string
	typ           string
	nullable      bool
	filter_ops    []string
	index_names   []string
	planner_hints []SidecarQueryPlannerHint
	filter_shapes []SidecarQueryFilterShape
}

pub struct SidecarQueryPlannerHint {
pub:
	op         string
	strategy   string
	index_name string
	stores_row bool
	score      int
}

pub struct SidecarQueryFilterShape {
pub:
	op                  string
	value_type          string
	indexed             bool
	index_name          string
	planner_strategy    string
	planner_score       int
	projection_only     bool
	continuation_anchor bool
	sample_explain      SidecarQuerySamplePlanExplain
}

pub struct SidecarFtsShape {
pub:
	kind             string
	indexed          bool
	index_name       string
	planner_strategy string
	sample_explain   SidecarQuerySamplePlanExplain
}

pub struct SidecarQuerySamplePlanExplain {
pub:
	strategy                    string
	index_name                  string
	warnings                    []string
	notes                       []string
	default_result_shape        string
	supports_continuation_token bool
}

pub struct SidecarQuerySchemaIndex {
pub:
	name                string
	column_name         string
	value_type          string
	stores_row          bool
	is_fts              bool
	fts_query_kinds     []string
	fts_shapes          []SidecarFtsShape
	json_field          string
	field_selector_meta SidecarFieldSelectorMeta
	filter_ops          []string
}

pub struct SidecarGeneralFtsQueryRequest {
pub:
	branch_name    string
	table_name     string
	index_name     string
	query_kind     string
	terms          []string
	select_columns []string
	limit          int
}

pub struct SidecarGeneralFtsQueryPlan {
pub:
	strategy    string
	index_name  string
	column_name string
	backend     string
	query_kind  string
	term_count  int
	limit       int
}

pub struct SidecarGeneralFtsHit {
pub:
	primary_key string
	score       f64
	snippet     string
}

pub struct SidecarGeneralFtsQueryPreview {
pub:
	branch_name string
	table_name  string
	index_name  string
	query_kind  string
	terms       []string
	plan        SidecarGeneralFtsQueryPlan
}

pub struct SidecarGeneralFtsQueryResult {
pub:
	branch_name    string
	table_name     string
	index_name     string
	query_kind     string
	terms          []string
	select_columns []string
	plan           SidecarGeneralFtsQueryPlan
	hits           []SidecarGeneralFtsHit
	rows           []SidecarTypedRow
}

pub struct SidecarQuerySchemaFieldSelector {
pub:
	column_name      string
	plugin_name      string
	selector         string
	value_type       string
	stores_row       bool
	filter_ops       []string
	index_names      []string
	projection_names []string
	planner_hints    []SidecarQueryPlannerHint
	filter_shapes    []SidecarQueryFilterShape
	fts_query_kinds  []string
	fts_shapes       []SidecarFtsShape
}

struct SidecarFtsQueryPlanDto {
	strategy   string
	index_name string
	selector   string
	scope      string
	query_kind string
	term_count int
	limit      int
}

struct SidecarFtsQueryRequestDto {
	repo_name      string
	branch_name    string
	table_name     string
	column_name    string
	scope          string
	query_kind     string
	terms          []string
	select_columns []string
	limit          int
}

struct SidecarFtsQueryPreviewDto {
	branch_name string
	table_name  string
	column_name string
	scope       string
	query_kind  string
	terms       []string
	plan        SidecarFtsQueryPlanDto
	explain     SidecarQuerySamplePlanExplainDto
	warnings    []string
	notes       []string
}

struct SidecarFtsQueryResultDto {
	branch_name    string
	table_name     string
	column_name    string
	scope          string
	query_kind     string
	terms          []string
	select_columns []string
	plan           SidecarFtsQueryPlanDto
	hits           []SidecarFtsHitDto
	rows           []SidecarTypedRowDto
}

struct SidecarFtsHitDto {
	primary_key    string
	score          int
	matched_terms  []string
	matched_scopes []string
	summary        string
}

pub struct SidecarQuerySchemaProjection {
pub:
	name             string
	column_name      string
	source_json_path string
	plugin_name      string
	selector         string
	value_type       string
	aggregate        string
	priority         int
	cost_hint        string
}

pub struct SidecarQuerySchema {
pub:
	branch_name                 string
	table_name                  string
	primary_key                 []string
	columns                     []SidecarQuerySchemaColumn
	indexes                     []SidecarQuerySchemaIndex
	field_selectors             []SidecarQuerySchemaFieldSelector
	projection_metrics          []SidecarQuerySchemaProjection
	supported_filter_ops        []string
	default_result_shape        string
	supports_continuation_token bool
	supports_select_projection  bool
}

pub struct SidecarMarkdownQueryRequest {
pub:
	branch_name string
	table_name  string
	column_name string
	selector    string
	index_name  string
	query_kind  string
	value       string
	limit       int
}

pub struct SidecarMarkdownQuery {
pub:
	branch_name         string
	table_name          string
	column_name         string
	selector            string
	index_name          string
	field_selector_meta SidecarFieldSelectorMeta
	query_kind          string
	value               string
	metric_value        i64
	rows                []SidecarTypedRow
}

pub struct SidecarQueryRowsRequest {
pub:
	branch_name        string
	table_name         string
	column_name        string
	plugin_name        string
	selector           string
	query_kind         string
	value              string
	select_columns     []string
	start_primary_key  string
	start_index_value  string
	continuation_token string
	limit              int
}

pub struct SidecarQueryFilter {
pub:
	column_name  string
	plugin_name  string
	selector     string
	query_kind   string
	value        string
	second_value string
}

pub struct SidecarQueryRowsPostRequest {
pub:
	branch_name        string
	table_name         string
	filters            []SidecarQueryFilter
	general_fts        SidecarGeneralFtsClause
	select_columns     []string
	start_primary_key  string
	start_index_value  string
	continuation_token string
	limit              int
}

pub struct SidecarQueryPlanPreview {
pub:
	branch_name    string
	table_name     string
	filters        []SidecarQueryFilter
	general_fts    SidecarGeneralFtsClause
	select_columns []string
	plan           SidecarQueryPlan
	// Prefer explain for new call sites; the duplicated top-level fields remain for compatibility.
	explain                     SidecarQuerySamplePlanExplain
	warnings                    []string
	notes                       []string
	default_result_shape        string
	supports_continuation_token bool
}

pub struct SidecarQueryPlan {
pub:
	strategy          string
	index_name        string
	index_filter      SidecarQueryFilter
	post_filters      []SidecarQueryFilter
	post_filter_count int
	limit             int
}

// SidecarQueryRows keeps legacy top-level cursor fields and echoed request
// metadata for compatibility. Prefer SidecarQueryPage for new paged reads.
pub struct SidecarQueryRows {
pub:
	branch_name             string
	table_name              string
	column_name             string
	plugin_name             string
	selector                string
	field_selector_meta     SidecarFieldSelectorMeta
	query_kind              string
	value                   string
	general_fts             SidecarGeneralFtsClause
	select_columns          []string
	start_primary_key       string
	start_index_value       string
	continuation_token      string
	plan                    SidecarQueryPlan
	cursor                  SidecarQueryCursor
	general_fts_hits        []SidecarGeneralFtsHit
	has_more                bool
	next_primary_key        string
	next_index_value        string
	next_continuation_token string
	rows                    []SidecarTypedRow
}

pub struct SidecarQueryCursor {
pub:
	has_more                bool
	next_primary_key        string
	next_index_value        string
	next_continuation_token string
}

pub struct SidecarGeneralFtsClause {
pub:
	index_name string
	query_kind string
	terms      []string
}

pub struct SidecarQueryPage {
pub:
	rows                []SidecarTypedRow
	plan                SidecarQueryPlan
	cursor              SidecarQueryCursor
	general_fts_hits    []SidecarGeneralFtsHit
	field_selector_meta SidecarFieldSelectorMeta
}

pub struct SidecarFtsQueryPlan {
pub:
	strategy   string
	index_name string
	selector   string
	scope      string
	query_kind string
	term_count int
	limit      int
}

pub struct SidecarFtsQueryRequest {
pub:
	branch_name    string
	table_name     string
	column_name    string
	scope          string
	query_kind     string
	terms          []string
	select_columns []string
	limit          int
}

pub struct SidecarFtsQueryPreview {
pub:
	branch_name string
	table_name  string
	column_name string
	scope       string
	query_kind  string
	terms       []string
	plan        SidecarFtsQueryPlan
	explain     SidecarQuerySamplePlanExplain
	warnings    []string
	notes       []string
}

pub struct SidecarFtsQueryResult {
pub:
	branch_name    string
	table_name     string
	column_name    string
	scope          string
	query_kind     string
	terms          []string
	select_columns []string
	plan           SidecarFtsQueryPlan
	hits           []SidecarFtsHit
	rows           []SidecarTypedRow
}

pub struct SidecarFtsHit {
pub:
	primary_key    string
	score          int
	matched_terms  []string
	matched_scopes []string
	summary        string
}

pub struct SidecarBranchLogEntry {
pub:
	cid          string
	root_cid     string
	parent_count int
	author       string
	message      string
	timestamp    i64
}

pub struct SidecarRepoActivityEntry {
pub:
	repo_name    string
	branch       Branch
	root_cid     string
	parent_count int
	author       string
	message      string
	timestamp    i64
}

struct SidecarGlobalActivityDto {
	entries []SidecarRepoActivityEntryDto
}

struct SyncOfferEnvelopeDto {
	offer        SyncOfferDto
	manifest     SyncManifestDto
	has_manifest bool
}

struct SyncOfferDto {
	request_local_root_hash string
	request_branch_name     string
	expected_old_commit_cid string
	target_commit_cid       string
	target_root_cid         string
}

struct SyncManifestDto {
	offer            SyncOfferDto
	prediction_depth int
	level_1_hashes   []string
	predicted_hashes []string
}

struct SyncMissingSetDto {
	missing_commit_cids []string
	missing_node_cids   []string
}

struct SyncExchangeDto {
	session SyncSessionDto
	plan    SyncPlanDto
	packets []DataPacketDto
}

struct SyncSessionDto {
	request_local_root_hash string
	request_branch_name     string
	expected_old_commit_cid string
	target_commit_cid       string
}

struct SyncPlanDto {
	request_local_root_hash string
	request_branch_name     string
	target_commit_cid       string
	target_root_cid         string
	missing_commit_cids     []string
	missing_node_cids       []string
}

struct DataPacketDto {
	kind     string
	cid      string
	data_b64 string
}

pub struct BranchDto {
pub:
	name       string
	commit_cid string
}

struct ErrorDto {
	error string
}

fn sync_offer_to_dto(offer SyncOffer) SyncOfferDto {
	return SyncOfferDto{
		request_local_root_hash: offer.request.local_root_hash
		request_branch_name:     offer.request.branch_name
		expected_old_commit_cid: offer.expected_old_commit_cid
		target_commit_cid:       offer.target_commit_cid
		target_root_cid:         offer.target_root_cid
	}
}

fn sync_offer_from_dto(dto SyncOfferDto) SyncOffer {
	return SyncOffer{
		request:                 SyncRequest{
			local_root_hash: dto.request_local_root_hash
			branch_name:     dto.request_branch_name
		}
		expected_old_commit_cid: dto.expected_old_commit_cid
		target_commit_cid:       dto.target_commit_cid
		target_root_cid:         dto.target_root_cid
	}
}

fn sync_manifest_to_dto(manifest SyncManifest) SyncManifestDto {
	return SyncManifestDto{
		offer:            sync_offer_to_dto(manifest.offer)
		prediction_depth: manifest.prediction_depth
		level_1_hashes:   manifest.level_1_hashes.clone()
		predicted_hashes: manifest.predicted_hashes.clone()
	}
}

fn sync_manifest_from_dto(dto SyncManifestDto) SyncManifest {
	return SyncManifest{
		offer:            sync_offer_from_dto(dto.offer)
		prediction_depth: dto.prediction_depth
		level_1_hashes:   dto.level_1_hashes.clone()
		predicted_hashes: dto.predicted_hashes.clone()
	}
}

fn sync_missing_set_to_dto(missing SyncMissingSet) SyncMissingSetDto {
	return SyncMissingSetDto{
		missing_commit_cids: missing.missing_commit_cids.clone()
		missing_node_cids:   missing.missing_node_cids.clone()
	}
}

fn sync_missing_set_from_dto(dto SyncMissingSetDto) SyncMissingSet {
	return SyncMissingSet{
		missing_commit_cids: dto.missing_commit_cids.clone()
		missing_node_cids:   dto.missing_node_cids.clone()
	}
}

fn sync_session_to_dto(session SyncSession) SyncSessionDto {
	return SyncSessionDto{
		request_local_root_hash: session.request.local_root_hash
		request_branch_name:     session.request.branch_name
		expected_old_commit_cid: session.expected_old_commit_cid
		target_commit_cid:       session.target_commit_cid
	}
}

fn sync_session_from_dto(dto SyncSessionDto) SyncSession {
	return SyncSession{
		request:                 SyncRequest{
			local_root_hash: dto.request_local_root_hash
			branch_name:     dto.request_branch_name
		}
		expected_old_commit_cid: dto.expected_old_commit_cid
		target_commit_cid:       dto.target_commit_cid
	}
}

fn sync_plan_to_dto(plan SyncPlan) SyncPlanDto {
	return SyncPlanDto{
		request_local_root_hash: plan.request.local_root_hash
		request_branch_name:     plan.request.branch_name
		target_commit_cid:       plan.target_commit_cid
		target_root_cid:         plan.target_root_cid
		missing_commit_cids:     plan.missing_commit_cids.clone()
		missing_node_cids:       plan.missing_node_cids.clone()
	}
}

fn sync_plan_from_dto(dto SyncPlanDto) SyncPlan {
	return SyncPlan{
		request:             SyncRequest{
			local_root_hash: dto.request_local_root_hash
			branch_name:     dto.request_branch_name
		}
		target_commit_cid:   dto.target_commit_cid
		target_root_cid:     dto.target_root_cid
		missing_commit_cids: dto.missing_commit_cids.clone()
		missing_node_cids:   dto.missing_node_cids.clone()
	}
}

fn data_packet_to_dto(packet DataPacket) DataPacketDto {
	return DataPacketDto{
		kind:     match packet.kind {
			.node { 'node' }
			.commit { 'commit' }
		}
		cid:      packet.cid
		data_b64: base64.encode(packet.data)
	}
}

fn data_packet_from_dto(dto DataPacketDto) !DataPacket {
	return DataPacket{
		kind: match dto.kind {
			'node' { SyncObjectKind.node }
			'commit' { SyncObjectKind.commit }
			else { return error('invalid packet kind: ${dto.kind}') }
		}
		cid:  dto.cid
		data: base64.decode(dto.data_b64)
	}
}

fn sync_exchange_to_dto(exchange SyncExchange) SyncExchangeDto {
	mut packets := []DataPacketDto{cap: exchange.packets.len}
	for packet in exchange.packets {
		packets << data_packet_to_dto(packet)
	}
	return SyncExchangeDto{
		session: sync_session_to_dto(exchange.session)
		plan:    sync_plan_to_dto(exchange.plan)
		packets: packets
	}
}

fn sync_exchange_from_dto(dto SyncExchangeDto) !SyncExchange {
	mut packets := []DataPacket{cap: dto.packets.len}
	for packet in dto.packets {
		packets << data_packet_from_dto(packet)!
	}
	return SyncExchange{
		session: sync_session_from_dto(dto.session)
		plan:    sync_plan_from_dto(dto.plan)
		packets: packets
	}
}

fn branch_to_dto(branch Branch) BranchDto {
	return BranchDto{
		name:       branch.name
		commit_cid: branch.commit_cid
	}
}

fn branch_from_dto(dto BranchDto) Branch {
	return Branch{
		name:       dto.name
		commit_cid: dto.commit_cid
	}
}

fn commit_to_dto(commit Commit) CommitDto {
	return CommitDto{
		cid:          commit.cid
		root_cid:     commit.root_cid
		parent_count: commit.parent_cids.len
		author:       commit.meta.author
		message:      commit.meta.message
		timestamp:    commit.meta.timestamp
	}
}

fn sidecar_repo_activity_entry(mut repo PersistentRepository, repo_name string, branch Branch) !SidecarRepoActivityEntryDto {
	commit := repo.commit_store.get(branch.commit_cid)!
	return SidecarRepoActivityEntryDto{
		repo_name:    if repo_name.len == 0 { '.' } else { repo_name }
		branch:       branch_to_dto(branch)
		root_cid:     commit.root_cid
		parent_count: commit.parent_cids.len
		author:       commit.meta.author
		message:      commit.meta.message
		timestamp:    commit.meta.timestamp
	}
}

fn json_ok(body string) http.Response {
	mut resp := http.Response{
		body: body
	}
	resp.header = http.new_header(key: .content_type, value: 'application/json')
	resp.set_status(.ok)
	return resp
}

fn json_error(status http.Status, message string) http.Response {
	payload := json.encode(ErrorDto{
		error: message
	})
	mut resp := http.Response{
		body: payload
	}
	resp.header = http.new_header(key: .content_type, value: 'application/json')
	resp.set_status(status)
	return resp
}

fn sidecar_repo_meta_path(root_dir string) string {
	return os.join_path(root_dir, '.pollydb', 'repo.meta')
}

fn sidecar_repo_root_dir(root_dir string, repo_name string) string {
	name := repo_name.trim_space()
	if name.len == 0 || name == '.' {
		return root_dir
	}
	return os.join_path(root_dir, name)
}

fn sidecar_query_value(url string, key string) string {
	if !url.contains('?') {
		return ''
	}
	query := url.all_after('?')
	for part in query.split('&') {
		if part.len == 0 {
			continue
		}
		pair := part.split_nth('=', 2)
		if pair.len == 2 && pair[0] == key {
			return pair[1]
		}
	}
	return ''
}

fn sidecar_decode_index_query_value(raw string, column ColumnDef) !ColumnValue {
	return match column.typ {
		.bool_ {
			if raw == 'true' {
				ColumnValue(true)
			} else if raw == 'false' {
				ColumnValue(false)
			} else {
				return error('invalid bool index value: ${raw}')
			}
		}
		.i64_ {
			ColumnValue(raw.i64())
		}
		.string_, .enum_, .json_, .datetime_ {
			ColumnValue(raw)
		}
		.bytes_ {
			ColumnValue(raw.bytes())
		}
		.markdown_ {
			return error('markdown ref values are not supported for sidecar index lookup')
		}
	}
}

fn sidecar_render_column_value(value ColumnValue) string {
	return match value {
		MarkdownRef {
			'markdown:${value.doc_root_id}'
		}
		NullValue {
			'null'
		}
		bool {
			if value {
				'true'
			} else {
				'false'
			}
		}
		i64 {
			value.str()
		}
		string {
			value
		}
		[]u8 {
			'hex:${value.hex()}'
		}
	}
}

fn sidecar_column_type_name(typ ColumnType) string {
	return match typ {
		.bool_ { 'bool' }
		.i64_ { 'i64' }
		.string_ { 'string' }
		.bytes_ { 'bytes' }
		.enum_ { 'enum' }
		.json_ { 'json' }
		.datetime_ { 'datetime' }
		.markdown_ { 'markdown' }
	}
}

fn sidecar_field_selector_meta_dto(index SchemaIndexDef) SidecarFieldSelectorMetaDto {
	selector_meta := index.field_selector_meta() or { FieldSelectorMeta{} }
	return SidecarFieldSelectorMetaDto{
		plugin_name: selector_meta.plugin_name
		selector:    selector_meta.selector
		value_type:  if selector_meta.plugin_name.len > 0 {
			sidecar_column_type_name(selector_meta.value_type)
		} else {
			''
		}
		stores_row:  selector_meta.stores_row
	}
}

fn sidecar_metric_field_selector_meta_dto(selector string) SidecarFieldSelectorMetaDto {
	return SidecarFieldSelectorMetaDto{
		plugin_name: 'markdown'
		selector:    selector
		value_type:  'i64'
		stores_row:  false
	}
}

fn sidecar_field_selector_meta_for_filter(plugin_name string, selector string, value_type ColumnType) SidecarFieldSelectorMetaDto {
	if plugin_name.len == 0 || selector.len == 0 {
		return SidecarFieldSelectorMetaDto{}
	}
	return SidecarFieldSelectorMetaDto{
		plugin_name: plugin_name
		selector:    selector
		value_type:  sidecar_column_type_name(value_type)
		stores_row:  false
	}
}

fn sidecar_parse_select_columns(raw string) []string {
	if raw.len == 0 {
		return []string{}
	}
	mut out := []string{}
	for part in raw.split(',') {
		name := part.trim_space()
		if name.len == 0 {
			continue
		}
		out << name
	}
	return out
}

fn sidecar_guess_field_selector_value_type(spec TypedTableSpec, column_name string, plugin_name string, selector string) !ColumnType {
	for index in spec.indexes {
		if index.is_field_selector() && index.column == column_name
			&& index.field_selector_plugin() == plugin_name && index.field_selector() == selector {
			return index.json_field_type
		}
	}
	if plugin_name == 'markdown' {
		if selector in ['links', 'images', 'code_spans', 'code_blocks', 'blocks', 'headings']
			|| selector.starts_with('headings:') || selector.starts_with('blocks:')
			|| selector.starts_with('code_blocks:') {
			return .i64_
		}
		return .string_
	}
	return error('unsupported field selector plugin: ${plugin_name}')
}

fn sidecar_query_filter_from_inputs(spec TypedTableSpec, column_name string, plugin_name string, selector string, query_kind string, value_raw string, second_value_raw string) !(QueryFilter, SidecarFieldSelectorMetaDto) {
	column := spec.table.column(column_name)!
	if query_kind !in ['eq', 'prefix', 'after', 'before', 'between'] {
		return error('query kind must be eq, prefix, after, before, or between')
	}
	if plugin_name.len > 0 || selector.len > 0 {
		if plugin_name.len == 0 || selector.len == 0 {
			return error('field selector query requires plugin and selector')
		}
		value_type := sidecar_guess_field_selector_value_type(spec, column_name, plugin_name,
			selector)!
		query_value := sidecar_decode_index_query_value(value_raw, ColumnDef.new('field_query_value',
			value_type, false)!)!
		second_value := if query_kind == 'between' {
			sidecar_decode_index_query_value(second_value_raw, ColumnDef.new('field_query_value',
				value_type, false)!)!
		} else {
			NullValue{}
		}
		filter := match query_kind {
			'prefix' {
				QueryFilter.field_prefix(column_name, plugin_name, selector, query_value)
			}
			'after' {
				QueryFilter.field_after(column_name, plugin_name, selector, query_value)
			}
			'before' {
				QueryFilter.field_before(column_name, plugin_name, selector, query_value)
			}
			'between' {
				QueryFilter.field_between(column_name, plugin_name, selector, query_value,
					second_value)
			}
			else {
				QueryFilter.field_eq(column_name, plugin_name, selector, query_value)
			}
		}
		return filter, sidecar_field_selector_meta_for_filter(plugin_name, selector, value_type)
	}
	query_value := sidecar_decode_index_query_value(value_raw, column)!
	second_value := if query_kind == 'between' {
		sidecar_decode_index_query_value(second_value_raw, column)!
	} else {
		NullValue{}
	}
	filter := match query_kind {
		'prefix' { QueryFilter.prefix(column_name, query_value) }
		'after' { QueryFilter.after(column_name, query_value) }
		'before' { QueryFilter.before(column_name, query_value) }
		'between' { QueryFilter.between(column_name, query_value, second_value) }
		else { QueryFilter.eq(column_name, query_value) }
	}
	return filter, SidecarFieldSelectorMetaDto{}
}

fn sidecar_decode_query_anchor_value(spec TypedTableSpec, column_name string, plugin_name string, selector string, raw string) !ColumnValue {
	if raw.len == 0 {
		return NullValue{}
	}
	column := spec.table.column(column_name)!
	if plugin_name.len > 0 || selector.len > 0 {
		value_type := sidecar_guess_field_selector_value_type(spec, column_name, plugin_name,
			selector)!
		return sidecar_decode_index_query_value(raw, ColumnDef.new('field_query_anchor',
			value_type, false)!)
	}
	return sidecar_decode_index_query_value(raw, column)
}

fn sidecar_column_aggregate_name(aggregate ColumnAggregate) string {
	return match aggregate {
		.none { 'none' }
		.sum { 'sum' }
	}
}

fn sidecar_projection_cost_hint_name(cost_hint AggregateProjectionCostHint) string {
	return match cost_hint {
		.low { 'low' }
		.medium { 'medium' }
		.high { 'high' }
	}
}

fn sidecar_query_filter_op_names(ops []QueryFilterOp) []string {
	mut out := []string{cap: ops.len}
	for op in ops {
		out << query_filter_op_name(op)
	}
	return out
}

fn sidecar_query_planner_hint_dto(hint QueryPlannerHint) SidecarQueryPlannerHintDto {
	return SidecarQueryPlannerHintDto{
		op:         query_filter_op_name(hint.op)
		strategy:   hint.strategy
		index_name: hint.index_name
		stores_row: hint.stores_row
		score:      hint.score
	}
}

fn sidecar_query_filter_shape_dto(shape QueryFilterShapeCapability) SidecarQueryFilterShapeDto {
	return SidecarQueryFilterShapeDto{
		op:                  query_filter_op_name(shape.op)
		value_type:          sidecar_column_type_name(shape.value_type)
		indexed:             shape.indexed
		index_name:          shape.index_name
		planner_strategy:    shape.planner_strategy
		planner_score:       shape.planner_score
		projection_only:     shape.projection_only
		continuation_anchor: shape.continuation_anchor
		sample_explain:      sidecar_query_sample_plan_explain_dto(shape.sample_explain)
	}
}

fn sidecar_fts_kind_name(kind FtsQueryKind) string {
	return fts_query_kind_name(kind)
}

fn sidecar_fts_shape_dto(shape QueryFtsShapeCapability) SidecarFtsShapeDto {
	return SidecarFtsShapeDto{
		kind:             sidecar_fts_kind_name(shape.kind)
		indexed:          shape.indexed
		index_name:       shape.index_name
		planner_strategy: shape.planner_strategy
		sample_explain:   sidecar_query_sample_plan_explain_dto(shape.sample_explain)
	}
}

fn sidecar_fts_query_plan_dto(plan FtsQueryPlan) SidecarFtsQueryPlanDto {
	return SidecarFtsQueryPlanDto{
		strategy:   plan.strategy
		index_name: plan.index_name
		selector:   plan.selector
		scope:      fts_scope_name(plan.scope)
		query_kind: sidecar_fts_kind_name(plan.kind)
		term_count: plan.term_count
		limit:      plan.limit
	}
}

fn sidecar_general_fts_query_plan_dto(plan GeneralFtsQueryPlan, kind FtsQueryKind) SidecarGeneralFtsQueryPlanDto {
	return SidecarGeneralFtsQueryPlanDto{
		strategy:    plan.strategy
		index_name:  plan.index_name
		column_name: plan.column_name
		backend:     plan.backend
		query_kind:  sidecar_fts_kind_name(kind)
		term_count:  plan.term_count
		limit:       plan.limit
	}
}

fn sidecar_general_fts_clause_dto(clause SidecarGeneralFtsClause) SidecarGeneralFtsClauseDto {
	return SidecarGeneralFtsClauseDto{
		index_name: clause.index_name
		query_kind: clause.query_kind
		terms:      clause.terms.clone()
	}
}

fn sidecar_general_fts_clause_from_dto(dto SidecarGeneralFtsClauseDto) SidecarGeneralFtsClause {
	return SidecarGeneralFtsClause{
		index_name: dto.index_name
		query_kind: dto.query_kind
		terms:      dto.terms.clone()
	}
}

fn sidecar_fts_hit_dto(hit FtsHit) SidecarFtsHitDto {
	mut scopes := []string{cap: hit.matched_scopes.len}
	for scope in hit.matched_scopes {
		scopes << fts_scope_name(scope)
	}
	return SidecarFtsHitDto{
		primary_key:    hit.primary_key.bytestr()
		score:          hit.score
		matched_terms:  hit.matched_terms.clone()
		matched_scopes: scopes
		summary:        hit.summary
	}
}

fn sidecar_query_sample_plan_explain_dto(explain QuerySamplePlanExplain) SidecarQuerySamplePlanExplainDto {
	return SidecarQuerySamplePlanExplainDto{
		strategy:                    explain.strategy
		index_name:                  explain.index_name
		warnings:                    explain.warnings.clone()
		notes:                       explain.notes.clone()
		default_result_shape:        explain.default_result_shape
		supports_continuation_token: explain.supports_continuation_token
	}
}

fn sidecar_query_sample_plan_explain(dto SidecarQuerySamplePlanExplainDto) SidecarQuerySamplePlanExplain {
	return SidecarQuerySamplePlanExplain{
		strategy:                    dto.strategy
		index_name:                  dto.index_name
		warnings:                    dto.warnings.clone()
		notes:                       dto.notes.clone()
		default_result_shape:        dto.default_result_shape
		supports_continuation_token: dto.supports_continuation_token
	}
}

fn sidecar_fts_scope_from_string(raw string) !FtsScope {
	return match raw {
		'', 'any' { .any }
		'heading' { .heading }
		'paragraph' { .paragraph }
		'code_block' { .code_block }
		'list_item' { .list_item }
		else { return error('unsupported fts scope: ${raw}') }
	}
}

fn sidecar_fts_kind_from_string(raw string) !FtsQueryKind {
	return match raw {
		'term' { .term }
		'prefix' { .prefix }
		'all' { .all }
		'any' { .any }
		else { return error('unsupported fts query kind: ${raw}') }
	}
}

fn sidecar_typed_row_dto(row TypedSchemaRow) SidecarTypedRowDto {
	mut values := map[string]string{}
	for name, value in row.data.fields() {
		values[name] = sidecar_render_column_value(value)
	}
	return SidecarTypedRowDto{
		primary_key: row.primary_key.bytestr()
		values:      values
	}
}

fn sidecar_typed_row(dto SidecarTypedRowDto) SidecarTypedRow {
	return SidecarTypedRow{
		primary_key: dto.primary_key
		values:      dto.values.clone()
	}
}

fn sidecar_query_filter_kind_name(op QueryFilterOp) string {
	return match op {
		.eq { 'eq' }
		.prefix { 'prefix' }
		.after { 'after' }
		.before { 'before' }
		.between { 'between' }
	}
}

fn sidecar_query_filter_dto(filter QueryFilter) SidecarQueryFilterDto {
	return SidecarQueryFilterDto{
		column_name:  filter.column_name
		plugin_name:  filter.plugin_name
		selector:     filter.selector
		query_kind:   sidecar_query_filter_kind_name(filter.op)
		value:        sidecar_render_column_value(filter.value)
		second_value: if filter.has_second_value {
			sidecar_render_column_value(filter.second_value)
		} else {
			''
		}
	}
}

fn open_sidecar_repository(root_dir string, repo_name string, default_branch string) !PersistentRepository {
	repo_root := sidecar_repo_root_dir(root_dir, repo_name)
	if os.exists(sidecar_repo_meta_path(repo_root)) {
		return PersistentRepository.open_default(repo_root, default_branch)
	}
	return PersistentRepository.init(repo_root, default_branch)
}

fn list_sidecar_repositories(root_dir string) ![]string {
	mut names := []string{}
	if os.exists(sidecar_repo_meta_path(root_dir)) {
		names << '.'
	}
	for entry in os.ls(root_dir)! {
		path := os.join_path(root_dir, entry)
		if !os.is_dir(path) {
			continue
		}
		if os.exists(sidecar_repo_meta_path(path)) {
			names << entry
		}
	}
	names.sort()
	return names
}

fn sidecar_repository_info(root_dir string, mut repo PersistentRepository, repo_name string) SidecarRepositoryInfoDto {
	mut latest_branch := ''
	mut latest_commit_cid := ''
	mut latest_timestamp := i64(0)
	for branch_name in repo.branch_names() {
		branch := repo.branch(branch_name) or { continue }
		commit := repo.commit_store.get(branch.commit_cid) or { continue }
		if latest_branch.len == 0 || commit.meta.timestamp > latest_timestamp {
			latest_branch = branch.name
			latest_commit_cid = branch.commit_cid
			latest_timestamp = commit.meta.timestamp
		}
	}
	auth_enabled := pollyhub_auth_enabled(root_dir) or { false }
	policy := pollyhub_repo_policy(root_dir, repo_name) or {
		PollyHubRepoPolicy{
			repo_name:             pollyhub_normalize_repo_name(repo_name)
			allow_push_to_default: true
			require_auto_merge:    false
			default_sync_policy:   'auto'
		}
	}
	protection_summary := if policy.allow_push_to_default {
		if policy.require_auto_merge {
			'default:merge_only,sync=${policy.default_sync_policy}'
		} else {
			'default:open,sync=${policy.default_sync_policy}'
		}
	} else {
		'default:protected,sync=${policy.default_sync_policy}'
	}
	return SidecarRepositoryInfoDto{
		repo_name:             if repo_name.len == 0 { '.' } else { repo_name }
		default_branch:        repo.repo.default_branch
		branch_count:          repo.repo.branch_names().len
		latest_branch:         latest_branch
		latest_commit_cid:     latest_commit_cid
		latest_timestamp:      latest_timestamp
		auth_enabled:          auth_enabled
		allow_push_to_default: policy.allow_push_to_default
		require_auto_merge:    policy.require_auto_merge
		default_sync_policy:   policy.default_sync_policy
		protection_summary:    protection_summary
	}
}

fn sidecar_branch_merge_relation(mut db PersistentDatabase, branch_name string) string {
	if branch_name == db.default_branch {
		return 'default'
	}
	if !db.engine.repository.has_branch(db.default_branch) {
		return 'no_default_branch'
	}
	branch_commit := db.engine.checkout(branch_name) or { return 'unknown' }
	default_commit := db.engine.checkout(db.default_branch) or { return 'unknown' }
	if branch_commit.cid == default_commit.cid {
		return 'same_as_default'
	}
	base := db.merge_base_branch(db.default_branch, branch_name) or { return 'unknown' }
	if base.cid == default_commit.cid {
		return 'ahead_of_default'
	}
	if base.cid == branch_commit.cid {
		return 'behind_default'
	}
	return 'diverged'
}

fn sidecar_branch_policy_info(root_dir string, default_branch string, repo_name string, branch_name string) SidecarBranchPolicyInfo {
	if branch_policy := find_pollyhub_branch_policy(root_dir, repo_name, branch_name) {
		return SidecarBranchPolicyInfo{
			policy_scope:        'branch'
			allow_push:          branch_policy.allow_push
			require_auto_merge:  branch_policy.require_auto_merge
			default_sync_policy: branch_policy.default_sync_policy
		}
	}
	if branch_name == default_branch {
		repo_policy := pollyhub_repo_policy(root_dir, repo_name) or {
			PollyHubRepoPolicy{
				repo_name:             pollyhub_normalize_repo_name(repo_name)
				allow_push_to_default: true
				require_auto_merge:    false
				default_sync_policy:   'auto'
			}
		}
		return SidecarBranchPolicyInfo{
			policy_scope:        'repo_default'
			allow_push:          repo_policy.allow_push_to_default
			require_auto_merge:  repo_policy.require_auto_merge
			default_sync_policy: repo_policy.default_sync_policy
		}
	}
	return SidecarBranchPolicyInfo{
		policy_scope:        'open'
		allow_push:          true
		require_auto_merge:  false
		default_sync_policy: 'auto'
	}
}

fn sidecar_branch_protection_summary(policy SidecarBranchPolicyInfo) string {
	mut parts := []string{}
	parts << 'scope=${policy.policy_scope}'
	parts << if policy.allow_push { 'push=open' } else { 'push=blocked' }
	if policy.require_auto_merge {
		parts << 'merge=required'
	}
	parts << 'sync=${policy.default_sync_policy}'
	return parts.join(',')
}

fn sidecar_branch_status(root_dir string, repo_name string, mut db PersistentDatabase, branch_name string) !SidecarBranchStatusDto {
	branch := db.branch(branch_name)!
	commit := db.engine.checkout(branch_name)!
	policy := sidecar_branch_policy_info(root_dir, db.default_branch, repo_name, branch_name)
	mut fresh := 0
	mut stale := 0
	mut stale_projectors := []string{}
	for state in db.projection_states_at_branch(branch_name) or { []AggregateProjectorState{} } {
		if state.fresh {
			fresh++
		} else {
			stale++
			stale_projectors << state.projection.name
		}
	}
	stale_projectors.sort()
	return SidecarBranchStatusDto{
		branch:                                branch_to_dto(branch)
		root_cid:                              commit.root_cid
		parent_count:                          commit.parent_cids.len
		author:                                commit.meta.author
		message:                               commit.meta.message
		timestamp:                             commit.meta.timestamp
		merge_relation:                        sidecar_branch_merge_relation(mut db, branch_name)
		projector_fresh:                       fresh
		projector_stale:                       stale
		stale_projectors:                      stale_projectors
		recommended_projection_refresh_policy: 'stale_one'
		policy_scope:                          policy.policy_scope
		allow_push:                            policy.allow_push
		require_auto_merge:                    policy.require_auto_merge
		default_sync_policy:                   policy.default_sync_policy
		protection_summary:                    sidecar_branch_protection_summary(policy)
	}
}

fn list_sidecar_branch_statuses(root_dir string, repo_name string, default_branch string) ![]SidecarBranchStatusDto {
	repo_root := sidecar_repo_root_dir(root_dir, repo_name)
	mut db := PersistentDatabase.open(repo_root, default_branch)!
	defer {
		db.close() or {}
	}
	mut rows := []SidecarBranchStatusDto{}
	for branch_name in db.branch_names() {
		rows << sidecar_branch_status(root_dir, repo_name, mut db, branch_name) or { continue }
	}
	rows.sort(a.timestamp > b.timestamp)
	return rows
}

fn list_sidecar_repository_infos(root_dir string, default_branch string) ![]SidecarRepositoryInfoDto {
	names := list_sidecar_repositories(root_dir)!
	mut infos := []SidecarRepositoryInfoDto{cap: names.len}
	for name in names {
		mut repo := open_sidecar_repository(root_dir, if name == '.' { '' } else { name },
			default_branch) or { continue }
		infos << sidecar_repository_info(root_dir, mut repo, if name == '.' { '' } else { name })
		repo.close() or {}
	}
	infos.sort(a.latest_timestamp > b.latest_timestamp)
	return infos
}

fn list_sidecar_global_activity(root_dir string, default_branch string, limit int) ![]SidecarRepoActivityEntryDto {
	names := list_sidecar_repositories(root_dir)!
	mut entries := []SidecarRepoActivityEntryDto{}
	for name in names {
		effective_name := if name == '.' { '' } else { name }
		mut repo := open_sidecar_repository(root_dir, effective_name, default_branch) or {
			continue
		}
		for branch_name in repo.branch_names() {
			branch := repo.branch(branch_name) or { continue }
			entries << sidecar_repo_activity_entry(mut repo, effective_name, branch) or { continue }
		}
		repo.close() or {}
	}
	entries.sort(a.timestamp > b.timestamp)
	if limit > 0 && entries.len > limit {
		return entries[..limit].clone()
	}
	return entries
}

pub struct PollyLinkSidecarHandler {
pub:
	root_dir       string
	default_branch string
}

fn (handler PollyLinkSidecarHandler) request_identity(req http.Request) !PollyHubRequestIdentity {
	authorization := req.header.get(.authorization) or { '' }
	return authenticate_pollyhub_request(handler.root_dir, authorization)
}

fn (handler PollyLinkSidecarHandler) audit(identity PollyHubRequestIdentity, action string, repo_name string, branch_name string, allowed bool, detail string) {
	append_pollyhub_audit_entry(handler.root_dir, PollyHubAuditEntry{
		timestamp:   pollyhub_now_unix()
		actor:       identity.actor
		action:      action
		repo_name:   pollyhub_normalize_repo_name(repo_name)
		branch_name: branch_name
		allowed:     allowed
		detail:      detail
	}) or {}
}

fn (handler PollyLinkSidecarHandler) audit_auth_failure(action string, repo_name string, branch_name string, detail string) {
	append_pollyhub_audit_entry(handler.root_dir, PollyHubAuditEntry{
		timestamp:   pollyhub_now_unix()
		actor:       'anonymous'
		action:      action
		repo_name:   pollyhub_normalize_repo_name(repo_name)
		branch_name: branch_name
		allowed:     false
		detail:      detail
	}) or {}
}

fn (handler PollyLinkSidecarHandler) enforce_rate_limit(identity PollyHubRequestIdentity, action string, repo_name string, branch_name string) ! {
	policy := pollyhub_rate_limit_policy(handler.root_dir) or { return }
	if policy.requests_per_minute <= 0 {
		return
	}
	actor := if identity.actor.len > 0 { identity.actor } else { 'anonymous' }
	requests, _ := summarize_pollyhub_actor_audit_since(handler.root_dir, actor, pollyhub_now_unix() - 60) or {
		return
	}
	if requests >= policy.requests_per_minute {
		handler.audit(identity, action, repo_name, branch_name, false, 'rate limit exceeded')
		return error('rate limit exceeded')
	}
}

fn sidecar_target_commit_from_exchange(exchange SyncExchange) !Commit {
	for packet in exchange.packets {
		if packet.kind == .commit && packet.cid == exchange.plan.target_commit_cid {
			commit := Commit.from_data(packet.data)!
			if commit.cid != exchange.plan.target_commit_cid {
				return error('sync target commit packet cid mismatch')
			}
			return commit
		}
	}
	return error('missing target commit packet in sync exchange')
}

fn (handler PollyLinkSidecarHandler) serve_offer(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('sync_offer', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SyncOfferRequestDto, req.data) or {
		handler.audit(identity, 'sync_offer', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.enforce_rate_limit(identity, 'sync_offer', payload.repo_name, payload.branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name, .reader) or {
		handler.audit(identity, 'sync_offer', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, payload.repo_name, handler.default_branch) or {
		handler.audit(identity, 'sync_offer', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	offer := sync_offer_for_branch(mut repo, payload.branch_name) or {
		return json_error(.bad_request, err.msg())
	}
	mut effective_offer := offer
	if payload.target_branch.len > 0 {
		effective_offer = SyncOffer{
			request:                 SyncRequest{
				local_root_hash: offer.request.local_root_hash
				branch_name:     payload.target_branch
			}
			expected_old_commit_cid: offer.expected_old_commit_cid
			target_commit_cid:       offer.target_commit_cid
			target_root_cid:         offer.target_root_cid
		}
	}
	if payload.prediction_depth > 0 {
		manifest := effective_offer.manifest_with_depth(payload.prediction_depth, mut
			repo.node_store) or {
			handler.audit(identity, 'sync_offer', payload.repo_name, payload.branch_name,
				false, err.msg())
			return json_error(.internal_server_error, err.msg())
		}
		handler.audit(identity, 'sync_offer', payload.repo_name, payload.branch_name,
			true, 'manifest')
		return json_ok(json.encode(SyncOfferEnvelopeDto{
			offer:        sync_offer_to_dto(effective_offer)
			manifest:     sync_manifest_to_dto(manifest)
			has_manifest: true
		}))
	}
	handler.audit(identity, 'sync_offer', payload.repo_name, payload.branch_name, true,
		'regular')
	return json_ok(json.encode(SyncOfferEnvelopeDto{
		offer:        sync_offer_to_dto(effective_offer)
		has_manifest: false
	}))
}

fn (handler PollyLinkSidecarHandler) serve_missing(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('sync_missing', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SyncNegotiateRequestDto, req.data) or {
		handler.audit(identity, 'sync_missing', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.enforce_rate_limit(identity, 'sync_missing', payload.repo_name, payload.offer.request_branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name, .reader) or {
		handler.audit(identity, 'sync_missing', payload.repo_name, payload.offer.request_branch_name,
			false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, payload.repo_name, handler.default_branch) or {
		handler.audit(identity, 'sync_missing', payload.repo_name, payload.offer.request_branch_name,
			false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	missing := if payload.use_manifest {
		sync_missing_for_manifest(mut repo, sync_manifest_from_dto(payload.manifest)) or {
			handler.audit(identity, 'sync_missing', payload.repo_name, payload.offer.request_branch_name,
				false, err.msg())
			return json_error(.bad_request, err.msg())
		}
	} else {
		sync_missing_for_offer(mut repo, sync_offer_from_dto(payload.offer)) or {
			handler.audit(identity, 'sync_missing', payload.repo_name, payload.offer.request_branch_name,
				false, err.msg())
			return json_error(.bad_request, err.msg())
		}
	}
	handler.audit(identity, 'sync_missing', payload.repo_name, payload.offer.request_branch_name,
		true, '')
	return json_ok(json.encode(sync_missing_set_to_dto(missing)))
}

fn (handler PollyLinkSidecarHandler) serve_exchange(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('sync_exchange', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SyncExchangeRequestDto, req.data) or {
		handler.audit(identity, 'sync_exchange', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.enforce_rate_limit(identity, 'sync_exchange', payload.repo_name, payload.offer.request_branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name, .reader) or {
		handler.audit(identity, 'sync_exchange', payload.repo_name, payload.offer.request_branch_name,
			false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, payload.repo_name, handler.default_branch) or {
		handler.audit(identity, 'sync_exchange', payload.repo_name, payload.offer.request_branch_name,
			false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	exchange := sync_exchange_for_missing(mut repo, sync_offer_from_dto(payload.offer),
		sync_missing_set_from_dto(payload.missing)) or {
		handler.audit(identity, 'sync_exchange', payload.repo_name, payload.offer.request_branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.audit(identity, 'sync_exchange', payload.repo_name, payload.offer.request_branch_name,
		true, 'packets=${exchange.packets.len}')
	return json_ok(json.encode(sync_exchange_to_dto(exchange)))
}

fn (handler PollyLinkSidecarHandler) serve_exchange_full(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('sync_exchange_full', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SyncFullExchangeRequestDto, req.data) or {
		handler.audit(identity, 'sync_exchange_full', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.enforce_rate_limit(identity, 'sync_exchange_full', payload.repo_name, payload.offer.request_branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name, .reader) or {
		handler.audit(identity, 'sync_exchange_full', payload.repo_name, payload.offer.request_branch_name,
			false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, payload.repo_name, handler.default_branch) or {
		handler.audit(identity, 'sync_exchange_full', payload.repo_name, payload.offer.request_branch_name,
			false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	exchange := full_sync_exchange_for_offer(mut repo, sync_offer_from_dto(payload.offer)) or {
		handler.audit(identity, 'sync_exchange_full', payload.repo_name, payload.offer.request_branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.audit(identity, 'sync_exchange_full', payload.repo_name, payload.offer.request_branch_name,
		true, 'packets=${exchange.packets.len}')
	return json_ok(json.encode(sync_exchange_to_dto(exchange)))
}

fn (handler PollyLinkSidecarHandler) serve_apply(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('sync_apply', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SyncApplyRequestDto, req.data) or {
		handler.audit(identity, 'sync_apply', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	exchange := sync_exchange_from_dto(payload.exchange) or {
		handler.audit(identity, 'sync_apply', payload.repo_name, '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.enforce_rate_limit(identity, 'sync_apply', payload.repo_name, exchange.session.request.branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name, .writer) or {
		handler.audit(identity, 'sync_apply', payload.repo_name, exchange.session.request.branch_name,
			false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, payload.repo_name, handler.default_branch) or {
		handler.audit(identity, 'sync_apply', payload.repo_name, exchange.session.request.branch_name,
			false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	policy := sidecar_branch_policy_info(handler.root_dir, repo.repo.default_branch, payload.repo_name,
		exchange.session.request.branch_name)
	if !policy.allow_push {
		handler.audit(identity, 'sync_apply', payload.repo_name, exchange.session.request.branch_name,
			false, 'push to branch disabled by policy')
		return json_error(.unauthorized, 'push to branch disabled by policy')
	}
	if policy.require_auto_merge {
		target_commit := sidecar_target_commit_from_exchange(exchange) or {
			handler.audit(identity, 'sync_apply', payload.repo_name, exchange.session.request.branch_name,
				false, err.msg())
			return json_error(.bad_request, err.msg())
		}
		if target_commit.parent_cids.len < 2 {
			handler.audit(identity, 'sync_apply', payload.repo_name, exchange.session.request.branch_name,
				false, 'branch requires merge commit by policy')
			return json_error(.unauthorized, 'branch requires merge commit by policy')
		}
	}
	branch := apply_exchange_to_repo(mut repo, exchange) or {
		handler.audit(identity, 'sync_apply', payload.repo_name, exchange.session.request.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.audit(identity, 'sync_apply', payload.repo_name, branch.name, true, 'commit=${branch.commit_cid}')
	return json_ok(json.encode(branch_to_dto(branch)))
}

fn (handler PollyLinkSidecarHandler) serve_list_repos(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('list_repos', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repos := list_pollyhub_authorized_repositories(handler.root_dir, identity) or {
		return json_error(.internal_server_error, err.msg())
	}
	handler.enforce_rate_limit(identity, 'list_repos', '.', '') or {
		return json_error(.too_many_requests, err.msg())
	}
	handler.audit(identity, 'list_repos', '.', '', true, 'repos=${repos.len}')
	return json_ok(json.encode(SidecarRepoListDto{
		repos: repos
	}))
}

fn (handler PollyLinkSidecarHandler) serve_repo_summaries(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('repo_summaries', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	limit := sidecar_query_value(req.url, 'limit').int()
	handler.enforce_rate_limit(identity, 'repo_summaries', '.', '') or {
		return json_error(.too_many_requests, err.msg())
	}
	mut infos := list_sidecar_repository_infos(handler.root_dir, handler.default_branch) or {
		return json_error(.internal_server_error, err.msg())
	}
	if identity.auth_enabled && !identity.global_admin {
		allowed := list_pollyhub_authorized_repositories(handler.root_dir, identity) or {
			[]string{}
		}
		mut filtered := []SidecarRepositoryInfoDto{}
		for info in infos {
			if info.repo_name in allowed {
				filtered << info
			}
		}
		infos = filtered.clone()
	}
	if limit > 0 && infos.len > limit {
		infos = infos[..limit].clone()
	}
	handler.audit(identity, 'repo_summaries', '.', '', true, 'repos=${infos.len}')
	return json_ok(json.encode(SidecarRepoSummaryListDto{
		repos: infos
	}))
}

fn (handler PollyLinkSidecarHandler) serve_repo_info(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('repo_info', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	handler.enforce_rate_limit(identity, 'repo_info', repo_name, '') or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'repo_info', repo_name, '', false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, repo_name, handler.default_branch) or {
		handler.audit(identity, 'repo_info', repo_name, '', false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	info := sidecar_repository_info(handler.root_dir, mut repo, repo_name)
	handler.audit(identity, 'repo_info', repo_name, '', true, info.default_sync_policy)
	return json_ok(json.encode(SidecarRepoInfoQueryDto{
		repo: info
	}))
}

fn (handler PollyLinkSidecarHandler) serve_governance_status(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('governance_status', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	if identity.auth_enabled && !identity.global_admin {
		handler.audit(identity, 'governance_status', '.', '', false, 'governance status requires global admin')
		return json_error(.unauthorized, 'governance status requires global admin')
	}
	handler.enforce_rate_limit(identity, 'governance_status', '.', '') or {
		return json_error(.too_many_requests, err.msg())
	}
	governance := load_pollyhub_governance(handler.root_dir) or {
		return json_error(.internal_server_error, err.msg())
	}
	repo_count := list_sidecar_repositories(handler.root_dir) or { []string{} }.len
	recent_requests_1m, recent_denies_1m := summarize_pollyhub_audit_since(handler.root_dir,
		pollyhub_now_unix() - 60) or { 0, 0 }
	category_summaries := summarize_pollyhub_audit_by_category_since(handler.root_dir,
		pollyhub_now_unix() - 60) or { []PollyHubAuditCategorySummary{} }
	actor_summaries := summarize_pollyhub_audit_by_actor_since(handler.root_dir, pollyhub_now_unix() - 60) or {
		[]PollyHubActorAuditSummary{}
	}
	action_summaries := summarize_pollyhub_audit_by_action_since(handler.root_dir, pollyhub_now_unix() - 60) or {
		[]PollyHubActionAuditSummary{}
	}
	mut recent_categories := []SidecarGovernanceCategoryDto{cap: category_summaries.len}
	for summary in category_summaries {
		recent_categories << SidecarGovernanceCategoryDto{
			category:           summary.category
			recent_requests_1m: summary.total
			recent_denies_1m:   summary.denies
		}
	}
	mut recent_actors := []SidecarGovernanceActorDto{cap: actor_summaries.len}
	for summary in actor_summaries {
		recent_actors << SidecarGovernanceActorDto{
			actor:              summary.actor
			recent_requests_1m: summary.total
			recent_denies_1m:   summary.denies
		}
	}
	mut recent_actions := []SidecarGovernanceActionDto{cap: action_summaries.len}
	for summary in action_summaries {
		recent_actions << SidecarGovernanceActionDto{
			action:             summary.action
			recent_requests_1m: summary.total
			recent_denies_1m:   summary.denies
		}
	}
	handler.audit(identity, 'governance_status', '.', '', true, 'repos=${repo_count}')
	return json_ok(json.encode(SidecarGovernanceStatusDto{
		auth_enabled:        governance.tokens.len > 0
		token_count:         governance.tokens.len
		repo_count:          repo_count
		requests_per_minute: governance.rate_limit.requests_per_minute
		recent_requests_1m:  recent_requests_1m
		recent_denies_1m:    recent_denies_1m
		recent_categories:   recent_categories
		recent_actors:       recent_actors
		recent_actions:      recent_actions
	}))
}

fn (handler PollyLinkSidecarHandler) serve_list_branches(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('list_branches', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	handler.enforce_rate_limit(identity, 'list_branches', repo_name, '') or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'list_branches', repo_name, '', false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, repo_name, handler.default_branch) or {
		handler.audit(identity, 'list_branches', repo_name, '', false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	mut branches := []BranchDto{}
	for name in repo.branch_names() {
		branches << branch_to_dto(repo.branch(name) or { continue })
	}
	handler.audit(identity, 'list_branches', repo_name, '', true, 'branches=${branches.len}')
	return json_ok(json.encode(SidecarBranchListDto{
		branches: branches
	}))
}

fn (handler PollyLinkSidecarHandler) serve_branch_status(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('branch_status', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	branch_name := sidecar_query_value(req.url, 'branch')
	if branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch query parameter')
	}
	handler.enforce_rate_limit(identity, 'branch_status', repo_name, branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'branch_status', repo_name, branch_name, false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'branch_status', repo_name, branch_name, false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	status := sidecar_branch_status(handler.root_dir, repo_name, mut db, branch_name) or {
		handler.audit(identity, 'branch_status', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.audit(identity, 'branch_status', repo_name, branch_name, true, status.merge_relation)
	return json_ok(json.encode(status))
}

fn (handler PollyLinkSidecarHandler) serve_branch_statuses(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('branch_statuses', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	handler.enforce_rate_limit(identity, 'branch_statuses', repo_name, '') or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'branch_statuses', repo_name, '', false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	rows := list_sidecar_branch_statuses(handler.root_dir, repo_name, handler.default_branch) or {
		handler.audit(identity, 'branch_statuses', repo_name, '', false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	handler.audit(identity, 'branch_statuses', repo_name, '', true, 'branches=${rows.len}')
	return json_ok(json.encode(SidecarBranchStatusListDto{
		branches: rows
	}))
}

fn (handler PollyLinkSidecarHandler) serve_projector_value(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('projector_value', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	branch_name := sidecar_query_value(req.url, 'branch')
	projector_name := sidecar_query_value(req.url, 'name')
	if branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch query parameter')
	}
	if projector_name.len == 0 {
		return json_error(.bad_request, 'missing name query parameter')
	}
	handler.enforce_rate_limit(identity, 'projector_value', repo_name, branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'projector_value', repo_name, branch_name, false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'projector_value', repo_name, branch_name, false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	value := db.projection_value_at_branch(branch_name, projector_name) or {
		handler.audit(identity, 'projector_value', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.audit(identity, 'projector_value', repo_name, branch_name, true, projector_name)
	return json_ok(json.encode(SidecarProjectorValueDto{
		name:                         value.projection.name
		branch_name:                  value.branch_name
		value:                        value.value
		current_data_root_cid:        value.current_data_root_cid
		source_data_root_cid:         value.source_data_root_cid
		virtual_root_cid:             value.virtual_root_cid
		fresh:                        value.fresh
		stale_reason:                 value.stale_reason
		source_json_path:             value.projection.source_json_path
		source_field_selector_meta:   if selector_meta := value.projection.field_projection_meta() {
			SidecarFieldSelectorMetaDto{
				plugin_name: selector_meta.plugin_name
				selector:    selector_meta.selector
				value_type:  sidecar_column_type_name(selector_meta.value_type)
				stores_row:  selector_meta.stores_row
			}
		} else {
			SidecarFieldSelectorMetaDto{}
		}
		source_field_selector_plugin: value.projection.field_projection_plugin()
		source_field_selector:        value.projection.field_projection_selector()
		source_markdown_selector:     value.projection.source_markdown_selector
	}))
}

fn (handler PollyLinkSidecarHandler) serve_markdown_metric(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('markdown_metric', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	branch_name := sidecar_query_value(req.url, 'branch')
	table_name := sidecar_query_value(req.url, 'table')
	column_name := sidecar_query_value(req.url, 'column')
	selector := sidecar_query_value(req.url, 'selector')
	if branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch query parameter')
	}
	if table_name.len == 0 {
		return json_error(.bad_request, 'missing table query parameter')
	}
	if column_name.len == 0 {
		return json_error(.bad_request, 'missing column query parameter')
	}
	if selector.len == 0 {
		return json_error(.bad_request, 'missing selector query parameter')
	}
	handler.enforce_rate_limit(identity, 'markdown_metric', repo_name, branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'markdown_metric', repo_name, branch_name, false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'markdown_metric', repo_name, branch_name, false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	value := db.markdown_projection_i64_at_branch(branch_name, table_name, column_name,
		selector) or {
		handler.audit(identity, 'markdown_metric', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.audit(identity, 'markdown_metric', repo_name, branch_name, true, '${table_name}.${column_name}:${selector}')
	return json_ok(json.encode(SidecarMarkdownMetricDto{
		branch_name: branch_name
		table_name:  table_name
		column_name: column_name
		selector:    selector
		value:       value
	}))
}

fn (handler PollyLinkSidecarHandler) serve_table_spec(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('table_spec', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	branch_name := sidecar_query_value(req.url, 'branch')
	table_name := sidecar_query_value(req.url, 'table')
	if branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch query parameter')
	}
	if table_name.len == 0 {
		return json_error(.bad_request, 'missing table query parameter')
	}
	handler.enforce_rate_limit(identity, 'table_spec', repo_name, branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'table_spec', repo_name, branch_name, false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'table_spec', repo_name, branch_name, false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	session := db.open_session(branch_name) or {
		handler.audit(identity, 'table_spec', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	spec := session.table_spec(table_name) or {
		handler.audit(identity, 'table_spec', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	mut columns := []SidecarColumnDefDto{cap: spec.table.columns.len}
	for column in spec.table.columns {
		columns << SidecarColumnDefDto{
			name:        column.name
			typ:         sidecar_column_type_name(column.typ)
			nullable:    column.nullable
			aggregate:   sidecar_column_aggregate_name(column.aggregate)
			enum_values: column.enum_values.clone()
		}
	}
	mut indexes := []SidecarIndexDefDto{cap: spec.indexes.len}
	for index in spec.indexes {
		value_column := index.value_column(spec.table) or {
			handler.audit(identity, 'table_spec', repo_name, branch_name, false, err.msg())
			return json_error(.bad_request, err.msg())
		}
		indexes << SidecarIndexDefDto{
			name:                index.name
			column:              index.column
			stores_row:          index.stores_row
			json_field:          index.json_field
			value_type:          sidecar_column_type_name(value_column.typ)
			field_selector_meta: sidecar_field_selector_meta_dto(index)
		}
	}
	handler.audit(identity, 'table_spec', repo_name, branch_name, true, table_name)
	return json_ok(json.encode(SidecarTableSpecDto{
		branch_name: branch_name
		table_name:  spec.table.name
		primary_key: spec.table.primary_key.clone()
		columns:     columns
		indexes:     indexes
	}))
}

fn (handler PollyLinkSidecarHandler) serve_query_schema(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('query_schema', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	branch_name := sidecar_query_value(req.url, 'branch')
	table_name := sidecar_query_value(req.url, 'table')
	if branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch query parameter')
	}
	if table_name.len == 0 {
		return json_error(.bad_request, 'missing table query parameter')
	}
	handler.enforce_rate_limit(identity, 'query_schema', repo_name, branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'query_schema', repo_name, branch_name, false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'query_schema', repo_name, branch_name, false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	schema := db.table_query_schema(table_name) or {
		handler.audit(identity, 'query_schema', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	mut columns := []SidecarQuerySchemaColumnDto{cap: schema.columns.len}
	for column in schema.columns {
		mut planner_hints := []SidecarQueryPlannerHintDto{cap: column.planner_hints.len}
		for hint in column.planner_hints {
			planner_hints << sidecar_query_planner_hint_dto(hint)
		}
		mut filter_shapes := []SidecarQueryFilterShapeDto{cap: column.filter_shapes.len}
		for shape in column.filter_shapes {
			filter_shapes << sidecar_query_filter_shape_dto(shape)
		}
		columns << SidecarQuerySchemaColumnDto{
			name:          column.name
			typ:           sidecar_column_type_name(column.typ)
			nullable:      column.nullable
			filter_ops:    sidecar_query_filter_op_names(column.filter_ops)
			index_names:   column.index_names.clone()
			planner_hints: planner_hints
			filter_shapes: filter_shapes
		}
	}
	mut indexes := []SidecarQuerySchemaIndexDto{cap: schema.indexes.len}
	for index in schema.indexes {
		mut fts_shapes := []SidecarFtsShapeDto{cap: index.fts_shapes.len}
		for shape in index.fts_shapes {
			fts_shapes << sidecar_fts_shape_dto(shape)
		}
		indexes << SidecarQuerySchemaIndexDto{
			name:                index.name
			column_name:         index.column_name
			value_type:          sidecar_column_type_name(index.value_type)
			stores_row:          index.stores_row
			is_fts:              index.is_fts
			fts_query_kinds:     index.fts_query_kinds.map(sidecar_fts_kind_name(it))
			fts_shapes:          fts_shapes
			json_field:          index.json_field
			field_selector_meta: SidecarFieldSelectorMetaDto{
				plugin_name: index.field_selector_meta.plugin_name
				selector:    index.field_selector_meta.selector
				value_type:  if index.field_selector_meta.plugin_name.len > 0 {
					sidecar_column_type_name(index.field_selector_meta.value_type)
				} else {
					''
				}
				stores_row:  index.field_selector_meta.stores_row
			}
			filter_ops:          sidecar_query_filter_op_names(index.filter_ops)
		}
	}
	mut field_selectors := []SidecarQuerySchemaFieldSelectorDto{cap: schema.field_selectors.len}
	for selector in schema.field_selectors {
		mut planner_hints := []SidecarQueryPlannerHintDto{cap: selector.planner_hints.len}
		for hint in selector.planner_hints {
			planner_hints << sidecar_query_planner_hint_dto(hint)
		}
		mut filter_shapes := []SidecarQueryFilterShapeDto{cap: selector.filter_shapes.len}
		for shape in selector.filter_shapes {
			filter_shapes << sidecar_query_filter_shape_dto(shape)
		}
		mut fts_shapes := []SidecarFtsShapeDto{cap: selector.fts_shapes.len}
		for shape in selector.fts_shapes {
			fts_shapes << sidecar_fts_shape_dto(shape)
		}
		mut fts_query_kinds := []string{cap: selector.fts_query_kinds.len}
		for kind in selector.fts_query_kinds {
			fts_query_kinds << sidecar_fts_kind_name(kind)
		}
		field_selectors << SidecarQuerySchemaFieldSelectorDto{
			column_name:      selector.column_name
			plugin_name:      selector.plugin_name
			selector:         selector.selector
			value_type:       sidecar_column_type_name(selector.value_type)
			stores_row:       selector.stores_row
			filter_ops:       sidecar_query_filter_op_names(selector.filter_ops)
			index_names:      selector.index_names.clone()
			projection_names: selector.projection_names.clone()
			planner_hints:    planner_hints
			filter_shapes:    filter_shapes
			fts_query_kinds:  fts_query_kinds
			fts_shapes:       fts_shapes
		}
	}
	mut projection_metrics := []SidecarQuerySchemaProjectionDto{cap: schema.projection_metrics.len}
	for projection in schema.projection_metrics {
		projection_metrics << SidecarQuerySchemaProjectionDto{
			name:             projection.name
			column_name:      projection.column_name
			source_json_path: projection.source_json_path
			plugin_name:      projection.plugin_name
			selector:         projection.selector
			value_type:       sidecar_column_type_name(projection.value_type)
			aggregate:        sidecar_column_aggregate_name(projection.aggregate)
			priority:         projection.priority
			cost_hint:        sidecar_projection_cost_hint_name(projection.cost_hint)
		}
	}
	handler.audit(identity, 'query_schema', repo_name, branch_name, true, table_name)
	return json_ok(json.encode(SidecarQuerySchemaDto{
		branch_name:                 branch_name
		table_name:                  schema.table_name
		primary_key:                 schema.primary_key.clone()
		columns:                     columns
		indexes:                     indexes
		field_selectors:             field_selectors
		projection_metrics:          projection_metrics
		supported_filter_ops:        sidecar_query_filter_op_names(schema.supported_filter_ops)
		default_result_shape:        schema.default_result_shape
		supports_continuation_token: schema.supports_continuation_token
		supports_select_projection:  schema.supports_select_projection
	}))
}

fn (handler PollyLinkSidecarHandler) serve_query_plan_preview(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('query_plan_preview', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SidecarQueryRowsPostRequestDto, req.data) or {
		handler.audit(identity, 'query_plan_preview', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	if payload.branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch_name in request body')
	}
	if payload.table_name.len == 0 {
		return json_error(.bad_request, 'missing table_name in request body')
	}
	if payload.filters.len == 0 && payload.general_fts.index_name.len == 0 {
		return json_error(.bad_request, 'query requires at least one filter or general_fts clause')
	}
	handler.enforce_rate_limit(identity, 'query_plan_preview', payload.repo_name, payload.branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name, .reader) or {
		handler.audit(identity, 'query_plan_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, payload.repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'query_plan_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	session := db.open_session(payload.branch_name) or {
		handler.audit(identity, 'query_plan_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	spec := session.table_spec(payload.table_name) or {
		handler.audit(identity, 'query_plan_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	mut filters := []QueryFilter{cap: payload.filters.len}
	for filter_dto in payload.filters {
		filter, _ := sidecar_query_filter_from_inputs(spec, filter_dto.column_name, filter_dto.plugin_name,
			filter_dto.selector, filter_dto.query_kind, filter_dto.value, filter_dto.second_value) or {
			handler.audit(identity, 'query_plan_preview', payload.repo_name, payload.branch_name,
				false, err.msg())
			return json_error(.bad_request, err.msg())
		}
		filters << filter
	}
	general_fts_clause := if payload.general_fts.index_name.len > 0 {
		QueryGeneralFtsClause{
			index_name: payload.general_fts.index_name
			kind:       sidecar_fts_kind_from_string(payload.general_fts.query_kind) or {
				handler.audit(identity, 'query_plan_preview', payload.repo_name, payload.branch_name,
					false, err.msg())
				return json_error(.bad_request, err.msg())
			}
			terms:      payload.general_fts.terms.clone()
		}
	} else {
		QueryGeneralFtsClause{}
	}
	request := QueryRequest{
		table_name:     payload.table_name
		filters:        filters
		general_fts:    general_fts_clause
		select_columns: payload.select_columns
		limit:          payload.limit
	}
	preview := db.preview_query_plan_details(request) or {
		handler.audit(identity, 'query_plan_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.audit(identity, 'query_plan_preview', payload.repo_name, payload.branch_name,
		true, '${payload.table_name}:${preview.plan.strategy}')
	return json_ok(json.encode(SidecarQueryPlanPreviewDto{
		branch_name:                 payload.branch_name
		table_name:                  payload.table_name
		filters:                     payload.filters.clone()
		general_fts:                 payload.general_fts
		select_columns:              payload.select_columns.clone()
		plan:                        SidecarQueryPlanDto{
			strategy:          preview.plan.strategy
			index_name:        preview.plan.index_name
			index_filter:      sidecar_query_filter_dto(preview.plan.index_filter)
			post_filters:      preview.plan.post_filters.map(sidecar_query_filter_dto(it))
			post_filter_count: preview.plan.post_filter_count
			limit:             preview.plan.limit
		}
		explain:                     sidecar_query_sample_plan_explain_dto(preview.sample_explain())
		warnings:                    preview.warnings.clone()
		notes:                       preview.notes.clone()
		default_result_shape:        preview.default_result_shape
		supports_continuation_token: preview.supports_continuation_token
	}))
}

fn (handler PollyLinkSidecarHandler) serve_query_fts_preview(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('query_fts_preview', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SidecarFtsQueryRequestDto, req.data) or {
		handler.audit(identity, 'query_fts_preview', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	if payload.branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch_name in request body')
	}
	if payload.table_name.len == 0 || payload.column_name.len == 0 {
		return json_error(.bad_request, 'missing table_name or column_name in request body')
	}
	handler.enforce_rate_limit(identity, 'query_fts_preview', payload.repo_name, payload.branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name, .reader) or {
		handler.audit(identity, 'query_fts_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, payload.repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'query_fts_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	session := db.open_session(payload.branch_name) or {
		handler.audit(identity, 'query_fts_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	query := FtsQuery{
		table_name:     payload.table_name
		column_name:    payload.column_name
		scope:          sidecar_fts_scope_from_string(payload.scope) or {
			handler.audit(identity, 'query_fts_preview', payload.repo_name, payload.branch_name,
				false, err.msg())
			return json_error(.bad_request, err.msg())
		}
		kind:           sidecar_fts_kind_from_string(payload.query_kind) or {
			handler.audit(identity, 'query_fts_preview', payload.repo_name, payload.branch_name,
				false, err.msg())
			return json_error(.bad_request, err.msg())
		}
		terms:          payload.terms.clone()
		select_columns: payload.select_columns.clone()
		limit:          payload.limit
	}
	preview := session.preview_fts_query_details(query) or {
		handler.audit(identity, 'query_fts_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.audit(identity, 'query_fts_preview', payload.repo_name, payload.branch_name,
		true, '${payload.table_name}:${preview.plan.strategy}')
	return json_ok(json.encode(SidecarFtsQueryPreviewDto{
		branch_name: payload.branch_name
		table_name:  payload.table_name
		column_name: payload.column_name
		scope:       payload.scope
		query_kind:  payload.query_kind
		terms:       payload.terms.clone()
		plan:        sidecar_fts_query_plan_dto(preview.plan)
		explain:     sidecar_query_sample_plan_explain_dto(QuerySamplePlanExplain{
			strategy:                    preview.plan.strategy
			index_name:                  preview.plan.index_name
			warnings:                    preview.warnings.clone()
			notes:                       preview.notes.clone()
			default_result_shape:        'rows'
			supports_continuation_token: false
		})
		warnings:    preview.warnings.clone()
		notes:       preview.notes.clone()
	}))
}

fn (handler PollyLinkSidecarHandler) serve_query_fts(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('query_fts', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SidecarFtsQueryRequestDto, req.data) or {
		handler.audit(identity, 'query_fts', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	if payload.branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch_name in request body')
	}
	if payload.table_name.len == 0 || payload.column_name.len == 0 {
		return json_error(.bad_request, 'missing table_name or column_name in request body')
	}
	handler.enforce_rate_limit(identity, 'query_fts', payload.repo_name, payload.branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name, .reader) or {
		handler.audit(identity, 'query_fts', payload.repo_name, payload.branch_name, false,
			err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, payload.repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'query_fts', payload.repo_name, payload.branch_name, false,
			err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	session := db.open_session(payload.branch_name) or {
		handler.audit(identity, 'query_fts', payload.repo_name, payload.branch_name, false,
			err.msg())
		return json_error(.bad_request, err.msg())
	}
	query := FtsQuery{
		table_name:     payload.table_name
		column_name:    payload.column_name
		scope:          sidecar_fts_scope_from_string(payload.scope) or {
			handler.audit(identity, 'query_fts', payload.repo_name, payload.branch_name,
				false, err.msg())
			return json_error(.bad_request, err.msg())
		}
		kind:           sidecar_fts_kind_from_string(payload.query_kind) or {
			handler.audit(identity, 'query_fts', payload.repo_name, payload.branch_name,
				false, err.msg())
			return json_error(.bad_request, err.msg())
		}
		terms:          payload.terms.clone()
		select_columns: payload.select_columns.clone()
		limit:          payload.limit
	}
	result := session.query_fts(mut db, query) or {
		handler.audit(identity, 'query_fts', payload.repo_name, payload.branch_name, false,
			err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.audit(identity, 'query_fts', payload.repo_name, payload.branch_name, true,
		'${payload.table_name}:${result.plan.strategy}')
	return json_ok(json.encode(SidecarFtsQueryResultDto{
		branch_name:    payload.branch_name
		table_name:     payload.table_name
		column_name:    payload.column_name
		scope:          payload.scope
		query_kind:     payload.query_kind
		terms:          payload.terms.clone()
		select_columns: payload.select_columns.clone()
		plan:           sidecar_fts_query_plan_dto(result.plan)
		hits:           result.hits.map(sidecar_fts_hit_dto(it))
		rows:           result.rows.map(sidecar_typed_row_dto(it))
	}))
}

fn (handler PollyLinkSidecarHandler) serve_general_query_fts_preview(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('general_query_fts_preview', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SidecarGeneralFtsQueryRequestDto, req.data) or {
		handler.audit(identity, 'general_query_fts_preview', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	if payload.branch_name.len == 0 || payload.table_name.len == 0 || payload.index_name.len == 0 {
		return json_error(.bad_request, 'missing branch_name, table_name, or index_name in request body')
	}
	handler.enforce_rate_limit(identity, 'general_query_fts_preview', payload.repo_name,
		payload.branch_name) or { return json_error(.too_many_requests, err.msg()) }
	authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name, .reader) or {
		handler.audit(identity, 'general_query_fts_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, payload.repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'general_query_fts_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	session := db.open_session(payload.branch_name) or {
		handler.audit(identity, 'general_query_fts_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	kind := sidecar_fts_kind_from_string(payload.query_kind) or {
		handler.audit(identity, 'general_query_fts_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	query := GeneralFtsQuery{
		table_name:     payload.table_name
		index_name:     payload.index_name
		kind:           kind
		terms:          payload.terms.clone()
		select_columns: payload.select_columns.clone()
		limit:          payload.limit
	}
	plan := session.preview_general_fts_query(query) or {
		handler.audit(identity, 'general_query_fts_preview', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.audit(identity, 'general_query_fts_preview', payload.repo_name, payload.branch_name,
		true, '${payload.table_name}:${plan.strategy}')
	return json_ok(json.encode(SidecarGeneralFtsQueryPreviewDto{
		branch_name: payload.branch_name
		table_name:  payload.table_name
		index_name:  payload.index_name
		query_kind:  payload.query_kind
		terms:       payload.terms.clone()
		plan:        sidecar_general_fts_query_plan_dto(plan, kind)
	}))
}

fn (handler PollyLinkSidecarHandler) serve_general_query_fts(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('general_query_fts', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SidecarGeneralFtsQueryRequestDto, req.data) or {
		handler.audit(identity, 'general_query_fts', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	if payload.branch_name.len == 0 || payload.table_name.len == 0 || payload.index_name.len == 0 {
		return json_error(.bad_request, 'missing branch_name, table_name, or index_name in request body')
	}
	handler.enforce_rate_limit(identity, 'general_query_fts', payload.repo_name, payload.branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name, .reader) or {
		handler.audit(identity, 'general_query_fts', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, payload.repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'general_query_fts', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	session := db.open_session(payload.branch_name) or {
		handler.audit(identity, 'general_query_fts', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	kind := sidecar_fts_kind_from_string(payload.query_kind) or {
		handler.audit(identity, 'general_query_fts', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	query := GeneralFtsQuery{
		table_name:     payload.table_name
		index_name:     payload.index_name
		kind:           kind
		terms:          payload.terms.clone()
		select_columns: payload.select_columns.clone()
		limit:          payload.limit
	}
	result := session.query_general_fts(mut db, query) or {
		handler.audit(identity, 'general_query_fts', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.audit(identity, 'general_query_fts', payload.repo_name, payload.branch_name,
		true, '${payload.table_name}:${result.plan.strategy}')
	return json_ok(json.encode(SidecarGeneralFtsQueryResultDto{
		branch_name:    payload.branch_name
		table_name:     payload.table_name
		index_name:     payload.index_name
		query_kind:     payload.query_kind
		terms:          payload.terms.clone()
		select_columns: payload.select_columns.clone()
		plan:           sidecar_general_fts_query_plan_dto(result.plan, kind)
		hits:           result.hits.map(SidecarGeneralFtsHitDto{
			primary_key: it.primary_key.bytestr()
			score:       it.score
			snippet:     it.snippet
		})
		rows:           result.rows.map(sidecar_typed_row_dto(it))
	}))
}

fn (handler PollyLinkSidecarHandler) serve_markdown_query(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('markdown_query', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	branch_name := sidecar_query_value(req.url, 'branch')
	table_name := sidecar_query_value(req.url, 'table')
	column_name := sidecar_query_value(req.url, 'column')
	selector := sidecar_query_value(req.url, 'selector')
	index_name := sidecar_query_value(req.url, 'index')
	query_kind := sidecar_query_value(req.url, 'kind')
	value_raw := sidecar_query_value(req.url, 'value')
	limit := sidecar_query_value(req.url, 'limit').int()
	if branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch query parameter')
	}
	if table_name.len == 0 {
		return json_error(.bad_request, 'missing table query parameter')
	}
	if query_kind.len == 0 {
		return json_error(.bad_request, 'missing kind query parameter')
	}
	handler.enforce_rate_limit(identity, 'markdown_query', repo_name, branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'markdown_query', repo_name, branch_name, false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'markdown_query', repo_name, branch_name, false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	if query_kind == 'metric' {
		if column_name.len == 0 {
			return json_error(.bad_request, 'missing column query parameter')
		}
		if selector.len == 0 {
			return json_error(.bad_request, 'missing selector query parameter')
		}
		value := db.markdown_projection_i64_at_branch(branch_name, table_name, column_name,
			selector) or {
			handler.audit(identity, 'markdown_query', repo_name, branch_name, false, err.msg())
			return json_error(.bad_request, err.msg())
		}
		handler.audit(identity, 'markdown_query', repo_name, branch_name, true, '${table_name}.${column_name}:${selector}')
		return json_ok(json.encode(SidecarMarkdownQueryDto{
			branch_name:         branch_name
			table_name:          table_name
			column_name:         column_name
			selector:            selector
			query_kind:          'metric'
			field_selector_meta: sidecar_metric_field_selector_meta_dto(selector)
			metric_value:        value
		}))
	}
	if query_kind != 'exact' && query_kind != 'prefix' {
		return json_error(.bad_request, 'unsupported markdown query kind: ${query_kind}')
	}
	if index_name.len == 0 {
		return json_error(.bad_request, 'missing index query parameter')
	}
	session := db.open_session(branch_name) or {
		handler.audit(identity, 'markdown_query', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	spec := session.table_spec(table_name) or {
		handler.audit(identity, 'markdown_query', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	mut target_index := SchemaIndexDef{}
	mut found := false
	for index in spec.indexes {
		if index.name == index_name {
			target_index = index
			found = true
			break
		}
	}
	if !found {
		handler.audit(identity, 'markdown_query', repo_name, branch_name, false, 'typed schema index not found: ${index_name}')
		return json_error(.bad_request, 'typed schema index not found: ${index_name}')
	}
	query_value := sidecar_decode_index_query_value(value_raw, target_index.value_column(spec.table) or {
		return json_error(.bad_request, err.msg())
	}) or {
		handler.audit(identity, 'markdown_query', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	rows := if query_kind == 'prefix' {
		session.lookup_index_prefix(mut db, table_name, index_name, query_value, limit) or {
			handler.audit(identity, 'markdown_query', repo_name, branch_name, false, err.msg())
			return json_error(.bad_request, err.msg())
		}
	} else {
		session.lookup_index(mut db, table_name, index_name, query_value, limit) or {
			handler.audit(identity, 'markdown_query', repo_name, branch_name, false, err.msg())
			return json_error(.bad_request, err.msg())
		}
	}
	mut dto_rows := []SidecarTypedRowDto{cap: rows.len}
	for row in rows {
		dto_rows << sidecar_typed_row_dto(row)
	}
	handler.audit(identity, 'markdown_query', repo_name, branch_name, true, '${table_name}.${index_name}:${rows.len}')
	return json_ok(json.encode(SidecarMarkdownQueryDto{
		branch_name:         branch_name
		table_name:          table_name
		index_name:          index_name
		field_selector_meta: sidecar_field_selector_meta_dto(target_index)
		query_kind:          query_kind
		value:               value_raw
		rows:                dto_rows
	}))
}

// Historical GET query endpoint. The path name is retained for compatibility,
// but execution and pagination semantics are driven by QueryCursorPage.
fn (handler PollyLinkSidecarHandler) serve_query_rows(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('query_rows', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	branch_name := sidecar_query_value(req.url, 'branch')
	table_name := sidecar_query_value(req.url, 'table')
	column_name := sidecar_query_value(req.url, 'column')
	plugin_name := sidecar_query_value(req.url, 'plugin')
	selector := sidecar_query_value(req.url, 'selector')
	query_kind := sidecar_query_value(req.url, 'kind')
	value_raw := sidecar_query_value(req.url, 'value')
	second_value_raw := sidecar_query_value(req.url, 'second_value')
	select_raw := sidecar_query_value(req.url, 'select')
	mut start_primary_key := sidecar_query_value(req.url, 'start_primary_key')
	mut start_index_value_raw := sidecar_query_value(req.url, 'start_index_value')
	continuation_token := sidecar_query_value(req.url, 'continuation_token')
	limit := sidecar_query_value(req.url, 'limit').int()
	if branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch query parameter')
	}
	if table_name.len == 0 {
		return json_error(.bad_request, 'missing table query parameter')
	}
	if column_name.len == 0 {
		return json_error(.bad_request, 'missing column query parameter')
	}
	if query_kind !in ['eq', 'prefix'] {
		return json_error(.bad_request, 'query kind must be eq or prefix')
	}
	handler.enforce_rate_limit(identity, 'query_rows', repo_name, branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'query_rows', repo_name, branch_name, false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'query_rows', repo_name, branch_name, false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	session := db.open_session(branch_name) or {
		handler.audit(identity, 'query_rows', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	spec := session.table_spec(table_name) or {
		handler.audit(identity, 'query_rows', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	select_columns := sidecar_parse_select_columns(select_raw)
	filter, field_selector_meta := sidecar_query_filter_from_inputs(spec, column_name,
		plugin_name, selector, query_kind, value_raw, second_value_raw) or {
		handler.audit(identity, 'query_rows', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	start_index_value := sidecar_decode_query_anchor_value(spec, column_name, plugin_name,
		selector, start_index_value_raw) or {
		handler.audit(identity, 'query_rows', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	page := session.query_page(mut db, QueryRequest{
		table_name:            table_name
		filters:               [filter]
		select_columns:        select_columns
		start_primary_key:     start_primary_key.bytes()
		start_index_value:     start_index_value
		has_start_index_value: start_index_value_raw.len > 0
		continuation_token:    continuation_token
		limit:                 limit
	}) or {
		handler.audit(identity, 'query_rows', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	dto := sidecar_query_compat_rows_dto_from_page(branch_name, table_name, column_name,
		plugin_name, selector, field_selector_meta, query_kind, value_raw, SidecarGeneralFtsClauseDto{}, select_columns,
		start_primary_key, start_index_value_raw, continuation_token, page)
	handler.audit(identity, 'query_rows', repo_name, branch_name, true, '${table_name}.${column_name}:${page.rows.len}')
	return json_ok(json.encode(dto))
}

// Historical POST query endpoint. The path name is retained for compatibility,
// but execution and pagination semantics are driven by QueryCursorPage.
fn (handler PollyLinkSidecarHandler) serve_query_rows_post(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('query_rows', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SidecarQueryRowsPostRequestDto, req.data) or {
		handler.audit(identity, 'query_rows', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	if payload.branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch_name in request body')
	}
	if payload.table_name.len == 0 {
		return json_error(.bad_request, 'missing table_name in request body')
	}
	if payload.filters.len == 0 && payload.general_fts.index_name.len == 0 {
		return json_error(.bad_request, 'query requires at least one filter or general_fts clause')
	}
	handler.enforce_rate_limit(identity, 'query_rows', payload.repo_name, payload.branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name, .reader) or {
		handler.audit(identity, 'query_rows', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, payload.repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'query_rows', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	session := db.open_session(payload.branch_name) or {
		handler.audit(identity, 'query_rows', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	spec := session.table_spec(payload.table_name) or {
		handler.audit(identity, 'query_rows', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	mut filters := []QueryFilter{cap: payload.filters.len}
	mut field_selector_meta := SidecarFieldSelectorMetaDto{}
	mut first_column_name := ''
	mut first_plugin_name := ''
	mut first_selector := ''
	for filter_dto in payload.filters {
		filter, meta := sidecar_query_filter_from_inputs(spec, filter_dto.column_name,
			filter_dto.plugin_name, filter_dto.selector, filter_dto.query_kind, filter_dto.value,
			filter_dto.second_value) or {
			handler.audit(identity, 'query_rows', payload.repo_name, payload.branch_name,
				false, err.msg())
			return json_error(.bad_request, err.msg())
		}
		if first_column_name.len == 0 {
			first_column_name = filter_dto.column_name
			first_plugin_name = filter_dto.plugin_name
			first_selector = filter_dto.selector
		}
		if meta.plugin_name.len > 0 && field_selector_meta.plugin_name.len == 0 {
			field_selector_meta = meta
		}
		filters << filter
	}
	mut start_primary_key := payload.start_primary_key
	mut start_index_value_raw := payload.start_index_value
	mut start_index_value := ColumnValue(NullValue{})
	general_fts_clause := if payload.general_fts.index_name.len > 0 {
		QueryGeneralFtsClause{
			index_name: payload.general_fts.index_name
			kind:       sidecar_fts_kind_from_string(payload.general_fts.query_kind) or {
				handler.audit(identity, 'query_rows', payload.repo_name, payload.branch_name,
					false, err.msg())
				return json_error(.bad_request, err.msg())
			}
			terms:      payload.general_fts.terms.clone()
		}
	} else {
		QueryGeneralFtsClause{}
	}
	if payload.general_fts.index_name.len == 0 {
		start_index_value = sidecar_decode_query_anchor_value(spec, first_column_name, first_plugin_name,
			first_selector, start_index_value_raw) or {
			handler.audit(identity, 'query_rows', payload.repo_name, payload.branch_name,
				false, err.msg())
			return json_error(.bad_request, err.msg())
		}
	}
	request := QueryRequest{
		table_name:            payload.table_name
		filters:               filters
		general_fts:           general_fts_clause
		select_columns:        payload.select_columns
		start_primary_key:     if payload.general_fts.index_name.len == 0 { start_primary_key.bytes() } else { []u8{} }
		start_index_value:     start_index_value
		has_start_index_value: payload.general_fts.index_name.len == 0 && start_index_value_raw.len > 0
		continuation_token:    payload.continuation_token
		limit:                 payload.limit
	}
	page := session.query_page(mut db, request) or {
		handler.audit(identity, 'query_rows', payload.repo_name, payload.branch_name,
			false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	dto := sidecar_query_compat_rows_dto_from_page(payload.branch_name, payload.table_name,
		if payload.filters.len > 0 {
		payload.filters[0].column_name
	} else {
		''
	}, if payload.filters.len > 0 {
		payload.filters[0].plugin_name
	} else {
		''
	}, if payload.filters.len > 0 {
		payload.filters[0].selector
	} else {
		''
	}, field_selector_meta, if payload.filters.len > 0 {
		payload.filters[0].query_kind
	} else {
		''
	}, if payload.filters.len > 0 {
		payload.filters[0].value
	} else {
		''
	}, payload.general_fts, payload.select_columns.clone(), start_primary_key, start_index_value_raw, payload.continuation_token,
		page)
	handler.audit(identity, 'query_rows', payload.repo_name, payload.branch_name, true,
		'${payload.table_name}:${page.rows.len}')
	return json_ok(json.encode(dto))
}

// Builds the legacy `/v1/query-rows` envelope from the canonical page result.
fn sidecar_query_compat_rows_dto_from_page(branch_name string, table_name string, column_name string, plugin_name string, selector string, field_selector_meta SidecarFieldSelectorMetaDto, query_kind string, value string, general_fts SidecarGeneralFtsClauseDto, select_columns []string, start_primary_key string, start_index_value string, continuation_token string, page QueryCursorPage) SidecarQueryRowsDto {
	mut dto_rows := []SidecarTypedRowDto{cap: page.rows.len}
	for row in page.rows {
		dto_rows << sidecar_typed_row_dto(row)
	}
	mut general_fts_hits := []SidecarGeneralFtsHitDto{cap: page.general_fts_hits.len}
	for hit in page.general_fts_hits {
		general_fts_hits << SidecarGeneralFtsHitDto{
			primary_key: hit.primary_key.bytestr()
			score:       hit.score
			snippet:     hit.snippet
		}
	}
	return SidecarQueryRowsDto{
		branch_name:             branch_name
		table_name:              table_name
		column_name:             column_name
		plugin_name:             plugin_name
		selector:                selector
		field_selector_meta:     field_selector_meta
		query_kind:              query_kind
		value:                   value
		general_fts:             general_fts
		select_columns:          select_columns
		start_primary_key:       start_primary_key
		start_index_value:       start_index_value
		continuation_token:      continuation_token
		plan:                    SidecarQueryPlanDto{
			strategy:          page.plan.strategy
			index_name:        page.plan.index_name
			index_filter:      sidecar_query_filter_dto(page.plan.index_filter)
			post_filters:      page.plan.post_filters.map(sidecar_query_filter_dto(it))
			post_filter_count: page.plan.post_filter_count
			limit:             page.plan.limit
		}
		cursor:                  SidecarQueryCursorDto{
			has_more:                page.cursor.has_more
			next_primary_key:        page.cursor.next_primary_key.bytestr()
			next_index_value:        if page.cursor.next_index_value is NullValue {
				''
			} else {
				sidecar_render_column_value(page.cursor.next_index_value)
			}
			next_continuation_token: page.cursor.next_continuation_token
		}
		general_fts_hits:        general_fts_hits
		has_more:                page.cursor.has_more
		next_primary_key:        page.cursor.next_primary_key.bytestr()
		next_index_value:        if page.cursor.next_index_value is NullValue {
			''
		} else {
			sidecar_render_column_value(page.cursor.next_index_value)
		}
		next_continuation_token: page.cursor.next_continuation_token
		rows:                    dto_rows
	}
}

fn (handler PollyLinkSidecarHandler) serve_index_lookup(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('index_lookup', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	branch_name := sidecar_query_value(req.url, 'branch')
	table_name := sidecar_query_value(req.url, 'table')
	index_name := sidecar_query_value(req.url, 'index')
	value_raw := sidecar_query_value(req.url, 'value')
	limit := sidecar_query_value(req.url, 'limit').int()
	if branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch query parameter')
	}
	if table_name.len == 0 {
		return json_error(.bad_request, 'missing table query parameter')
	}
	if index_name.len == 0 {
		return json_error(.bad_request, 'missing index query parameter')
	}
	handler.enforce_rate_limit(identity, 'index_lookup', repo_name, branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'index_lookup', repo_name, branch_name, false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'index_lookup', repo_name, branch_name, false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	session := db.open_session(branch_name) or {
		handler.audit(identity, 'index_lookup', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	spec := session.table_spec(table_name) or {
		handler.audit(identity, 'index_lookup', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	mut target_index := SchemaIndexDef{}
	mut found := false
	for index in spec.indexes {
		if index.name == index_name {
			target_index = index
			found = true
			break
		}
	}
	if !found {
		handler.audit(identity, 'index_lookup', repo_name, branch_name, false, 'typed schema index not found: ${index_name}')
		return json_error(.bad_request, 'typed schema index not found: ${index_name}')
	}
	query_value := sidecar_decode_index_query_value(value_raw, target_index.value_column(spec.table) or {
		return json_error(.bad_request, err.msg())
	}) or {
		handler.audit(identity, 'index_lookup', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	rows := session.lookup_index(mut db, table_name, index_name, query_value, limit) or {
		handler.audit(identity, 'index_lookup', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	mut dto_rows := []SidecarTypedRowDto{cap: rows.len}
	for row in rows {
		dto_rows << sidecar_typed_row_dto(row)
	}
	handler.audit(identity, 'index_lookup', repo_name, branch_name, true, '${table_name}.${index_name}:${rows.len}')
	return json_ok(json.encode(SidecarIndexLookupDto{
		branch_name:         branch_name
		table_name:          table_name
		index_name:          index_name
		field_selector_meta: sidecar_field_selector_meta_dto(target_index)
		query_kind:          'exact'
		value:               value_raw
		rows:                dto_rows
	}))
}

fn (handler PollyLinkSidecarHandler) serve_index_lookup_prefix(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('index_lookup_prefix', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	branch_name := sidecar_query_value(req.url, 'branch')
	table_name := sidecar_query_value(req.url, 'table')
	index_name := sidecar_query_value(req.url, 'index')
	value_raw := sidecar_query_value(req.url, 'value')
	limit := sidecar_query_value(req.url, 'limit').int()
	if branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch query parameter')
	}
	if table_name.len == 0 {
		return json_error(.bad_request, 'missing table query parameter')
	}
	if index_name.len == 0 {
		return json_error(.bad_request, 'missing index query parameter')
	}
	handler.enforce_rate_limit(identity, 'index_lookup_prefix', repo_name, branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'index_lookup_prefix', repo_name, branch_name, false,
			err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'index_lookup_prefix', repo_name, branch_name, false,
			err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	session := db.open_session(branch_name) or {
		handler.audit(identity, 'index_lookup_prefix', repo_name, branch_name, false,
			err.msg())
		return json_error(.bad_request, err.msg())
	}
	spec := session.table_spec(table_name) or {
		handler.audit(identity, 'index_lookup_prefix', repo_name, branch_name, false,
			err.msg())
		return json_error(.bad_request, err.msg())
	}
	mut target_index := SchemaIndexDef{}
	mut found := false
	for index in spec.indexes {
		if index.name == index_name {
			target_index = index
			found = true
			break
		}
	}
	if !found {
		handler.audit(identity, 'index_lookup_prefix', repo_name, branch_name, false,
			'typed schema index not found: ${index_name}')
		return json_error(.bad_request, 'typed schema index not found: ${index_name}')
	}
	query_value := sidecar_decode_index_query_value(value_raw, target_index.value_column(spec.table) or {
		return json_error(.bad_request, err.msg())
	}) or {
		handler.audit(identity, 'index_lookup_prefix', repo_name, branch_name, false,
			err.msg())
		return json_error(.bad_request, err.msg())
	}
	rows := session.lookup_index_prefix(mut db, table_name, index_name, query_value, limit) or {
		handler.audit(identity, 'index_lookup_prefix', repo_name, branch_name, false,
			err.msg())
		return json_error(.bad_request, err.msg())
	}
	mut dto_rows := []SidecarTypedRowDto{cap: rows.len}
	for row in rows {
		dto_rows << sidecar_typed_row_dto(row)
	}
	handler.audit(identity, 'index_lookup_prefix', repo_name, branch_name, true, '${table_name}.${index_name}:${rows.len}')
	return json_ok(json.encode(SidecarIndexLookupDto{
		branch_name:         branch_name
		table_name:          table_name
		index_name:          index_name
		field_selector_meta: sidecar_field_selector_meta_dto(target_index)
		query_kind:          'prefix'
		value:               value_raw
		rows:                dto_rows
	}))
}

fn (handler PollyLinkSidecarHandler) serve_open_repo(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('open_repo', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	payload := json.decode(SidecarRepoOpenRequestDto, req.data) or {
		handler.audit(identity, 'open_repo', '', '', false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	handler.enforce_rate_limit(identity, 'open_repo', payload.repo_name, '') or {
		return json_error(.too_many_requests, err.msg())
	}
	existing_repo_root := sidecar_repo_root_dir(handler.root_dir, payload.repo_name)
	if os.exists(sidecar_repo_meta_path(existing_repo_root)) {
		authorize_pollyhub_repo_access(handler.root_dir, identity, payload.repo_name,
			.admin) or {
			handler.audit(identity, 'open_repo', payload.repo_name, '', false, err.msg())
			return json_error(.unauthorized, err.msg())
		}
	} else if identity.auth_enabled && !identity.global_admin {
		handler.audit(identity, 'open_repo', payload.repo_name, '', false, 'repo create requires global admin')
		return json_error(.unauthorized, 'repo create requires global admin')
	}
	mut repo := open_sidecar_repository(handler.root_dir, payload.repo_name, if payload.default_branch.len > 0 {
		payload.default_branch
	} else {
		handler.default_branch
	}) or {
		handler.audit(identity, 'open_repo', payload.repo_name, '', false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	info := sidecar_repository_info(handler.root_dir, mut repo, payload.repo_name)
	handler.audit(identity, 'open_repo', payload.repo_name, '', true, info.default_branch)
	return json_ok(json.encode(info))
}

fn (handler PollyLinkSidecarHandler) serve_branch_activity(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('branch_activity', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	branch_name := sidecar_query_value(req.url, 'branch')
	if branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch query parameter')
	}
	handler.enforce_rate_limit(identity, 'branch_activity', repo_name, branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'branch_activity', repo_name, branch_name, false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, repo_name, handler.default_branch) or {
		handler.audit(identity, 'branch_activity', repo_name, branch_name, false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	branch := repo.branch(branch_name) or {
		handler.audit(identity, 'branch_activity', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	commit := repo.checkout(branch_name) or {
		handler.audit(identity, 'branch_activity', repo_name, branch_name, false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	handler.audit(identity, 'branch_activity', repo_name, branch_name, true, '')
	return json_ok(json.encode(SidecarBranchActivityDto{
		branch:       branch_to_dto(branch)
		root_cid:     commit.root_cid
		parent_count: commit.parent_cids.len
		author:       commit.meta.author
		message:      commit.meta.message
		timestamp:    commit.meta.timestamp
	}))
}

fn (handler PollyLinkSidecarHandler) serve_branch_log(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('branch_log', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	branch_name := sidecar_query_value(req.url, 'branch')
	if branch_name.len == 0 {
		return json_error(.bad_request, 'missing branch query parameter')
	}
	limit := sidecar_query_value(req.url, 'limit').int()
	handler.enforce_rate_limit(identity, 'branch_log', repo_name, branch_name) or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'branch_log', repo_name, branch_name, false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_root := sidecar_repo_root_dir(handler.root_dir, repo_name)
	mut db := PersistentDatabase.open(repo_root, handler.default_branch) or {
		handler.audit(identity, 'branch_log', repo_name, branch_name, false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		db.close() or {}
	}
	commits := db.branch_log(branch_name, limit) or {
		handler.audit(identity, 'branch_log', repo_name, branch_name, false, err.msg())
		return json_error(.bad_request, err.msg())
	}
	mut rows := []CommitDto{cap: commits.len}
	for commit in commits {
		rows << commit_to_dto(commit)
	}
	handler.audit(identity, 'branch_log', repo_name, branch_name, true, 'commits=${rows.len}')
	return json_ok(json.encode(SidecarBranchLogDto{
		commits: rows
	}))
}

fn (handler PollyLinkSidecarHandler) serve_repo_activity(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('repo_activity', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	repo_name := sidecar_query_value(req.url, 'repo')
	limit := sidecar_query_value(req.url, 'limit').int()
	handler.enforce_rate_limit(identity, 'repo_activity', repo_name, '') or {
		return json_error(.too_many_requests, err.msg())
	}
	authorize_pollyhub_repo_access(handler.root_dir, identity, repo_name, .reader) or {
		handler.audit(identity, 'repo_activity', repo_name, '', false, err.msg())
		return json_error(.unauthorized, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, repo_name, handler.default_branch) or {
		handler.audit(identity, 'repo_activity', repo_name, '', false, err.msg())
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	mut entries := []SidecarRepoActivityEntryDto{}
	for branch_name in repo.branch_names() {
		branch := repo.branch(branch_name) or { continue }
		entries << sidecar_repo_activity_entry(mut repo, repo_name, branch) or { continue }
	}
	entries.sort(a.timestamp > b.timestamp)
	if limit > 0 && entries.len > limit {
		entries = entries[..limit].clone()
	}
	handler.audit(identity, 'repo_activity', repo_name, '', true, 'entries=${entries.len}')
	return json_ok(json.encode(SidecarRepoActivityDto{
		entries: entries
	}))
}

fn (handler PollyLinkSidecarHandler) serve_global_activity(req http.Request) http.Response {
	identity := handler.request_identity(req) or {
		handler.audit_auth_failure('global_activity', '', '', err.msg())
		return json_error(.unauthorized, err.msg())
	}
	limit := sidecar_query_value(req.url, 'limit').int()
	handler.enforce_rate_limit(identity, 'global_activity', '.', '') or {
		return json_error(.too_many_requests, err.msg())
	}
	mut entries := list_sidecar_global_activity(handler.root_dir, handler.default_branch,
		limit) or { return json_error(.internal_server_error, err.msg()) }
	if identity.auth_enabled && !identity.global_admin {
		allowed := list_pollyhub_authorized_repositories(handler.root_dir, identity) or {
			[]string{}
		}
		mut filtered := []SidecarRepoActivityEntryDto{}
		for entry in entries {
			if entry.repo_name in allowed {
				filtered << entry
			}
		}
		entries = filtered.clone()
		if limit > 0 && entries.len > limit {
			entries = entries[..limit].clone()
		}
	}
	handler.audit(identity, 'global_activity', '.', '', true, 'entries=${entries.len}')
	return json_ok(json.encode(SidecarGlobalActivityDto{
		entries: entries
	}))
}

pub fn (handler PollyLinkSidecarHandler) handle(req http.Request) http.Response {
	path := req.url.all_before('?')
	if req.method == .get && path == '/health' {
		return json_ok('{"status":"ok"}')
	}
	if req.method == .get && path == '/v1/repos' {
		return handler.serve_list_repos(req)
	}
	if req.method == .get && path == '/v1/repos/summaries' {
		return handler.serve_repo_summaries(req)
	}
	if req.method == .get && path == '/v1/repo-info' {
		return handler.serve_repo_info(req)
	}
	if req.method == .get && path == '/v1/governance-status' {
		return handler.serve_governance_status(req)
	}
	if req.method == .get && path == '/v1/branches' {
		return handler.serve_list_branches(req)
	}
	if req.method == .get && path == '/v1/branch-status' {
		return handler.serve_branch_status(req)
	}
	if req.method == .get && path == '/v1/branch-statuses' {
		return handler.serve_branch_statuses(req)
	}
	if req.method == .get && path == '/v1/projector-value' {
		return handler.serve_projector_value(req)
	}
	if req.method == .get && path == '/v1/table-spec' {
		return handler.serve_table_spec(req)
	}
	if req.method == .get && path == '/v1/query-schema' {
		return handler.serve_query_schema(req)
	}
	if req.method == .post && path == '/v1/query-plan-preview' {
		return handler.serve_query_plan_preview(req)
	}
	if req.method == .post && path == '/v1/query-fts-preview' {
		return handler.serve_query_fts_preview(req)
	}
	if req.method == .post && path == '/v1/query-fts' {
		return handler.serve_query_fts(req)
	}
	if req.method == .post && path == '/v1/general-query-fts-preview' {
		return handler.serve_general_query_fts_preview(req)
	}
	if req.method == .post && path == '/v1/general-query-fts' {
		return handler.serve_general_query_fts(req)
	}
	if req.method == .get && path == '/v1/markdown-metric' {
		return handler.serve_markdown_metric(req)
	}
	if req.method == .get && path == '/v1/markdown-query' {
		return handler.serve_markdown_query(req)
	}
	// Keep `/v1/query-rows` as the stable public path while the canonical
	// in-memory result shape has moved to page/cursor objects.
	if req.method == .get && path == '/v1/query-rows' {
		return handler.serve_query_rows(req)
	}
	if req.method == .post && path == '/v1/query-rows' {
		return handler.serve_query_rows_post(req)
	}
	if req.method == .get && path == '/v1/index-lookup' {
		return handler.serve_index_lookup(req)
	}
	if req.method == .get && path == '/v1/index-lookup-prefix' {
		return handler.serve_index_lookup_prefix(req)
	}
	if req.method == .get && path == '/v1/branch-activity' {
		return handler.serve_branch_activity(req)
	}
	if req.method == .get && path == '/v1/branch-log' {
		return handler.serve_branch_log(req)
	}
	if req.method == .get && path == '/v1/repo-activity' {
		return handler.serve_repo_activity(req)
	}
	if req.method == .get && path == '/v1/global-activity' {
		return handler.serve_global_activity(req)
	}
	if req.method == .post && path == '/v1/repos/open' {
		return handler.serve_open_repo(req)
	}
	if req.method == .post && path == '/v1/sync/offer' {
		return handler.serve_offer(req)
	}
	if req.method == .post && path == '/v1/sync/missing' {
		return handler.serve_missing(req)
	}
	if req.method == .post && path == '/v1/sync/exchange' {
		return handler.serve_exchange(req)
	}
	if req.method == .post && path == '/v1/sync/exchange-full' {
		return handler.serve_exchange_full(req)
	}
	if req.method == .post && path == '/v1/sync/apply' {
		return handler.serve_apply(req)
	}
	return json_error(.not_found, 'unknown route: ${path}')
}

pub fn start_pollylink_sidecar(root_dir string, default_branch string, addr string) !&http.Server {
	mut server := &http.Server{
		addr:                 addr
		handler:              PollyLinkSidecarHandler{
			root_dir:       root_dir
			default_branch: default_branch
		}
		show_startup_message: false
	}
	spawn server.listen_and_serve()
	server.wait_till_running()!
	return server
}

pub struct PollyLinkClient {
pub:
	base_url   string
	repo_name  string
	auth_token string
}

pub struct SidecarGovernanceStatus {
pub:
	auth_enabled        bool
	token_count         int
	repo_count          int
	requests_per_minute int
	recent_requests_1m  int
	recent_denies_1m    int
	recent_categories   []SidecarGovernanceCategory
	recent_actors       []SidecarGovernanceActor
	recent_actions      []SidecarGovernanceAction
}

pub struct SidecarGovernanceCategory {
pub:
	category           string
	recent_requests_1m int
	recent_denies_1m   int
}

pub struct SidecarGovernanceActor {
pub:
	actor              string
	recent_requests_1m int
	recent_denies_1m   int
}

pub struct SidecarGovernanceAction {
pub:
	action             string
	recent_requests_1m int
	recent_denies_1m   int
}

struct ApplyExchangeResult {
	ok        bool
	branch    Branch
	error_msg string
}

fn is_branch_head_changed_error(err_msg string) bool {
	return err_msg.contains('branch head changed during compare-and-swap')
}

fn (client PollyLinkClient) endpoint(path string) string {
	return client.base_url.trim_right('/') + path
}

fn (client PollyLinkClient) auth_header() http.Header {
	mut header := http.new_header()
	if client.auth_token.len > 0 {
		header.add(.authorization, 'Bearer ${client.auth_token}')
	}
	return header
}

fn (client PollyLinkClient) post_json(path string, body string) !http.Response {
	mut header := client.auth_header()
	header.add(.content_type, 'application/json')
	response := http.fetch(
		method: .post
		url:    client.endpoint(path)
		data:   body
		header: header
	)!
	if response.status_code >= 400 {
		return error(response.body)
	}
	return response
}

fn (client PollyLinkClient) post_json_raw(path string, body string) !http.Response {
	mut header := client.auth_header()
	header.add(.content_type, 'application/json')
	return http.fetch(
		method: .post
		url:    client.endpoint(path)
		data:   body
		header: header
	)
}

fn (client PollyLinkClient) get(path string) !http.Response {
	response := http.fetch(
		method: .get
		url:    client.endpoint(path)
		header: client.auth_header()
	)!
	if response.status_code >= 400 {
		return error(response.body)
	}
	return response
}

pub fn (client PollyLinkClient) offer(branch_name string, target_branch string, prediction_depth int) !PollyLinkOfferEnvelope {
	response := client.post_json('/v1/sync/offer', json.encode(SyncOfferRequestDto{
		repo_name:        client.repo_name
		branch_name:      branch_name
		target_branch:    target_branch
		prediction_depth: prediction_depth
	}))!
	payload := json.decode(SyncOfferEnvelopeDto, response.body)!
	return PollyLinkOfferEnvelope{
		offer:    sync_offer_from_dto(payload.offer)
		manifest: sync_manifest_from_dto(payload.manifest)
	}
}

pub fn (client PollyLinkClient) negotiate_missing(offer SyncOffer, manifest SyncManifest, use_manifest bool) !SyncMissingSet {
	response := client.post_json('/v1/sync/missing', json.encode(SyncNegotiateRequestDto{
		repo_name:    client.repo_name
		offer:        sync_offer_to_dto(offer)
		manifest:     sync_manifest_to_dto(manifest)
		use_manifest: use_manifest
	}))!
	payload := json.decode(SyncMissingSetDto, response.body)!
	return sync_missing_set_from_dto(payload)
}

pub fn (client PollyLinkClient) fetch_exchange(offer SyncOffer, missing SyncMissingSet) !SyncExchange {
	response := client.post_json('/v1/sync/exchange', json.encode(SyncExchangeRequestDto{
		repo_name: client.repo_name
		offer:     sync_offer_to_dto(offer)
		missing:   sync_missing_set_to_dto(missing)
	}))!
	payload := json.decode(SyncExchangeDto, response.body)!
	return sync_exchange_from_dto(payload)
}

pub fn (client PollyLinkClient) fetch_full_exchange(offer SyncOffer) !SyncExchange {
	response := client.post_json('/v1/sync/exchange-full', json.encode(SyncFullExchangeRequestDto{
		repo_name: client.repo_name
		offer:     sync_offer_to_dto(offer)
	}))!
	payload := json.decode(SyncExchangeDto, response.body)!
	return sync_exchange_from_dto(payload)
}

pub fn (client PollyLinkClient) apply_exchange(exchange SyncExchange) !Branch {
	response := client.post_json('/v1/sync/apply', json.encode(SyncApplyRequestDto{
		repo_name: client.repo_name
		exchange:  sync_exchange_to_dto(exchange)
	}))!
	payload := json.decode(BranchDto, response.body)!
	return branch_from_dto(payload)
}

fn (client PollyLinkClient) try_apply_exchange(exchange SyncExchange) !ApplyExchangeResult {
	response := client.post_json_raw('/v1/sync/apply', json.encode(SyncApplyRequestDto{
		repo_name: client.repo_name
		exchange:  sync_exchange_to_dto(exchange)
	}))!
	if response.status_code >= 400 {
		payload := json.decode(ErrorDto, response.body) or {
			return ApplyExchangeResult{
				ok:        false
				error_msg: response.body
			}
		}
		return ApplyExchangeResult{
			ok:        false
			error_msg: payload.error
		}
	}
	payload := json.decode(BranchDto, response.body)!
	return ApplyExchangeResult{
		ok:     true
		branch: branch_from_dto(payload)
	}
}

pub fn (client PollyLinkClient) list_repositories() ![]string {
	response := client.get('/v1/repos')!
	payload := json.decode(SidecarRepoListDto, response.body)!
	return payload.repos
}

pub fn (client PollyLinkClient) list_repository_summaries(limit int) ![]SidecarRepositoryInfo {
	path := '/v1/repos/summaries?limit=${limit}'
	response := client.get(path)!
	payload := json.decode(SidecarRepoSummaryListDto, response.body)!
	mut infos := []SidecarRepositoryInfo{cap: payload.repos.len}
	for dto in payload.repos {
		infos << SidecarRepositoryInfo{
			repo_name:             dto.repo_name
			default_branch:        dto.default_branch
			branch_count:          dto.branch_count
			latest_branch:         dto.latest_branch
			latest_commit_cid:     dto.latest_commit_cid
			latest_timestamp:      dto.latest_timestamp
			auth_enabled:          dto.auth_enabled
			allow_push_to_default: dto.allow_push_to_default
			require_auto_merge:    dto.require_auto_merge
			default_sync_policy:   dto.default_sync_policy
			protection_summary:    dto.protection_summary
		}
	}
	return infos
}

pub fn (client PollyLinkClient) repository_info() !SidecarRepositoryInfo {
	path := if client.repo_name.len == 0 {
		'/v1/repo-info'
	} else {
		'/v1/repo-info?repo=${client.repo_name}'
	}
	response := client.get(path)!
	payload := json.decode(SidecarRepoInfoQueryDto, response.body)!
	dto := payload.repo
	return SidecarRepositoryInfo{
		repo_name:             dto.repo_name
		default_branch:        dto.default_branch
		branch_count:          dto.branch_count
		latest_branch:         dto.latest_branch
		latest_commit_cid:     dto.latest_commit_cid
		latest_timestamp:      dto.latest_timestamp
		auth_enabled:          dto.auth_enabled
		allow_push_to_default: dto.allow_push_to_default
		require_auto_merge:    dto.require_auto_merge
		default_sync_policy:   dto.default_sync_policy
		protection_summary:    dto.protection_summary
	}
}

pub fn (client PollyLinkClient) governance_status() !SidecarGovernanceStatus {
	response := client.get('/v1/governance-status')!
	dto := json.decode(SidecarGovernanceStatusDto, response.body)!
	mut recent_categories := []SidecarGovernanceCategory{cap: dto.recent_categories.len}
	for row in dto.recent_categories {
		recent_categories << SidecarGovernanceCategory{
			category:           row.category
			recent_requests_1m: row.recent_requests_1m
			recent_denies_1m:   row.recent_denies_1m
		}
	}
	mut recent_actors := []SidecarGovernanceActor{cap: dto.recent_actors.len}
	for row in dto.recent_actors {
		recent_actors << SidecarGovernanceActor{
			actor:              row.actor
			recent_requests_1m: row.recent_requests_1m
			recent_denies_1m:   row.recent_denies_1m
		}
	}
	mut recent_actions := []SidecarGovernanceAction{cap: dto.recent_actions.len}
	for row in dto.recent_actions {
		recent_actions << SidecarGovernanceAction{
			action:             row.action
			recent_requests_1m: row.recent_requests_1m
			recent_denies_1m:   row.recent_denies_1m
		}
	}
	return SidecarGovernanceStatus{
		auth_enabled:        dto.auth_enabled
		token_count:         dto.token_count
		repo_count:          dto.repo_count
		requests_per_minute: dto.requests_per_minute
		recent_requests_1m:  dto.recent_requests_1m
		recent_denies_1m:    dto.recent_denies_1m
		recent_categories:   recent_categories
		recent_actors:       recent_actors
		recent_actions:      recent_actions
	}
}

pub fn (client PollyLinkClient) list_branches() ![]Branch {
	path := if client.repo_name.len == 0 {
		'/v1/branches'
	} else {
		'/v1/branches?repo=${client.repo_name}'
	}
	response := client.get(path)!
	payload := json.decode(SidecarBranchListDto, response.body)!
	mut branches := []Branch{cap: payload.branches.len}
	for branch in payload.branches {
		branches << branch_from_dto(branch)
	}
	return branches
}

pub fn (client PollyLinkClient) branch_status(branch_name string) !SidecarBranchStatus {
	path := if client.repo_name.len == 0 {
		'/v1/branch-status?branch=${branch_name}'
	} else {
		'/v1/branch-status?repo=${client.repo_name}&branch=${branch_name}'
	}
	response := client.get(path)!
	dto := json.decode(SidecarBranchStatusDto, response.body)!
	return SidecarBranchStatus{
		branch:                                branch_from_dto(dto.branch)
		root_cid:                              dto.root_cid
		parent_count:                          dto.parent_count
		author:                                dto.author
		message:                               dto.message
		timestamp:                             dto.timestamp
		merge_relation:                        dto.merge_relation
		projector_fresh:                       dto.projector_fresh
		projector_stale:                       dto.projector_stale
		stale_projectors:                      dto.stale_projectors.clone()
		recommended_projection_refresh_policy: dto.recommended_projection_refresh_policy
		policy_scope:                          dto.policy_scope
		allow_push:                            dto.allow_push
		require_auto_merge:                    dto.require_auto_merge
		default_sync_policy:                   dto.default_sync_policy
		protection_summary:                    dto.protection_summary
	}
}

pub fn (client PollyLinkClient) branch_statuses() ![]SidecarBranchStatus {
	path := if client.repo_name.len == 0 {
		'/v1/branch-statuses'
	} else {
		'/v1/branch-statuses?repo=${client.repo_name}'
	}
	response := client.get(path)!
	payload := json.decode(SidecarBranchStatusListDto, response.body)!
	mut rows := []SidecarBranchStatus{cap: payload.branches.len}
	for dto in payload.branches {
		rows << SidecarBranchStatus{
			branch:                                branch_from_dto(dto.branch)
			root_cid:                              dto.root_cid
			parent_count:                          dto.parent_count
			author:                                dto.author
			message:                               dto.message
			timestamp:                             dto.timestamp
			merge_relation:                        dto.merge_relation
			projector_fresh:                       dto.projector_fresh
			projector_stale:                       dto.projector_stale
			stale_projectors:                      dto.stale_projectors.clone()
			recommended_projection_refresh_policy: dto.recommended_projection_refresh_policy
			policy_scope:                          dto.policy_scope
			allow_push:                            dto.allow_push
			require_auto_merge:                    dto.require_auto_merge
			default_sync_policy:                   dto.default_sync_policy
			protection_summary:                    dto.protection_summary
		}
	}
	return rows
}

pub fn (client PollyLinkClient) projector_value(branch_name string, projector_name string) !SidecarProjectorValue {
	path := if client.repo_name.len == 0 {
		'/v1/projector-value?branch=${branch_name}&name=${projector_name}'
	} else {
		'/v1/projector-value?repo=${client.repo_name}&branch=${branch_name}&name=${projector_name}'
	}
	response := client.get(path)!
	dto := json.decode(SidecarProjectorValueDto, response.body)!
	return SidecarProjectorValue{
		name:                         dto.name
		branch_name:                  dto.branch_name
		value:                        dto.value
		current_data_root_cid:        dto.current_data_root_cid
		source_data_root_cid:         dto.source_data_root_cid
		virtual_root_cid:             dto.virtual_root_cid
		fresh:                        dto.fresh
		stale_reason:                 dto.stale_reason
		source_json_path:             dto.source_json_path
		source_field_selector_meta:   SidecarFieldSelectorMeta{
			plugin_name: dto.source_field_selector_meta.plugin_name
			selector:    dto.source_field_selector_meta.selector
			value_type:  dto.source_field_selector_meta.value_type
			stores_row:  dto.source_field_selector_meta.stores_row
		}
		source_field_selector_plugin: dto.source_field_selector_plugin
		source_field_selector:        dto.source_field_selector
		source_markdown_selector:     dto.source_markdown_selector
	}
}

pub fn (client PollyLinkClient) table_spec(branch_name string, table_name string) !SidecarTableSpec {
	path := if client.repo_name.len == 0 {
		'/v1/table-spec?branch=${branch_name}&table=${table_name}'
	} else {
		'/v1/table-spec?repo=${client.repo_name}&branch=${branch_name}&table=${table_name}'
	}
	response := client.get(path)!
	dto := json.decode(SidecarTableSpecDto, response.body)!
	mut columns := []SidecarColumnDef{cap: dto.columns.len}
	for column in dto.columns {
		columns << SidecarColumnDef{
			name:        column.name
			typ:         column.typ
			nullable:    column.nullable
			aggregate:   column.aggregate
			enum_values: column.enum_values.clone()
		}
	}
	mut indexes := []SidecarIndexDef{cap: dto.indexes.len}
	for index in dto.indexes {
		indexes << SidecarIndexDef{
			name:                index.name
			column:              index.column
			stores_row:          index.stores_row
			json_field:          index.json_field
			value_type:          index.value_type
			field_selector_meta: SidecarFieldSelectorMeta{
				plugin_name: index.field_selector_meta.plugin_name
				selector:    index.field_selector_meta.selector
				value_type:  index.field_selector_meta.value_type
				stores_row:  index.field_selector_meta.stores_row
			}
		}
	}
	return SidecarTableSpec{
		branch_name: dto.branch_name
		table_name:  dto.table_name
		primary_key: dto.primary_key.clone()
		columns:     columns
		indexes:     indexes
	}
}

pub fn (client PollyLinkClient) query_schema(branch_name string, table_name string) !SidecarQuerySchema {
	path := if client.repo_name.len == 0 {
		'/v1/query-schema?branch=${branch_name}&table=${table_name}'
	} else {
		'/v1/query-schema?repo=${client.repo_name}&branch=${branch_name}&table=${table_name}'
	}
	response := client.get(path)!
	dto := json.decode(SidecarQuerySchemaDto, response.body)!
	mut columns := []SidecarQuerySchemaColumn{cap: dto.columns.len}
	for column in dto.columns {
		mut planner_hints := []SidecarQueryPlannerHint{cap: column.planner_hints.len}
		for hint in column.planner_hints {
			planner_hints << SidecarQueryPlannerHint{
				op:         hint.op
				strategy:   hint.strategy
				index_name: hint.index_name
				stores_row: hint.stores_row
				score:      hint.score
			}
		}
		mut filter_shapes := []SidecarQueryFilterShape{cap: column.filter_shapes.len}
		for shape in column.filter_shapes {
			filter_shapes << SidecarQueryFilterShape{
				op:                  shape.op
				value_type:          shape.value_type
				indexed:             shape.indexed
				index_name:          shape.index_name
				planner_strategy:    shape.planner_strategy
				planner_score:       shape.planner_score
				projection_only:     shape.projection_only
				continuation_anchor: shape.continuation_anchor
				sample_explain:      sidecar_query_sample_plan_explain(shape.sample_explain)
			}
		}
		columns << SidecarQuerySchemaColumn{
			name:          column.name
			typ:           column.typ
			nullable:      column.nullable
			filter_ops:    column.filter_ops.clone()
			index_names:   column.index_names.clone()
			planner_hints: planner_hints
			filter_shapes: filter_shapes
		}
	}
	mut indexes := []SidecarQuerySchemaIndex{cap: dto.indexes.len}
	for index in dto.indexes {
		mut fts_shapes := []SidecarFtsShape{cap: index.fts_shapes.len}
		for shape in index.fts_shapes {
			fts_shapes << SidecarFtsShape{
				kind:             shape.kind
				indexed:          shape.indexed
				index_name:       shape.index_name
				planner_strategy: shape.planner_strategy
				sample_explain:   sidecar_query_sample_plan_explain(shape.sample_explain)
			}
		}
		indexes << SidecarQuerySchemaIndex{
			name:                index.name
			column_name:         index.column_name
			value_type:          index.value_type
			stores_row:          index.stores_row
			is_fts:              index.is_fts
			fts_query_kinds:     index.fts_query_kinds.clone()
			fts_shapes:          fts_shapes
			json_field:          index.json_field
			field_selector_meta: SidecarFieldSelectorMeta{
				plugin_name: index.field_selector_meta.plugin_name
				selector:    index.field_selector_meta.selector
				value_type:  index.field_selector_meta.value_type
				stores_row:  index.field_selector_meta.stores_row
			}
			filter_ops:          index.filter_ops.clone()
		}
	}
	mut field_selectors := []SidecarQuerySchemaFieldSelector{cap: dto.field_selectors.len}
	for selector in dto.field_selectors {
		mut planner_hints := []SidecarQueryPlannerHint{cap: selector.planner_hints.len}
		for hint in selector.planner_hints {
			planner_hints << SidecarQueryPlannerHint{
				op:         hint.op
				strategy:   hint.strategy
				index_name: hint.index_name
				stores_row: hint.stores_row
				score:      hint.score
			}
		}
		mut filter_shapes := []SidecarQueryFilterShape{cap: selector.filter_shapes.len}
		for shape in selector.filter_shapes {
			filter_shapes << SidecarQueryFilterShape{
				op:                  shape.op
				value_type:          shape.value_type
				indexed:             shape.indexed
				index_name:          shape.index_name
				planner_strategy:    shape.planner_strategy
				planner_score:       shape.planner_score
				projection_only:     shape.projection_only
				continuation_anchor: shape.continuation_anchor
				sample_explain:      sidecar_query_sample_plan_explain(shape.sample_explain)
			}
		}
		mut fts_shapes := []SidecarFtsShape{cap: selector.fts_shapes.len}
		for shape in selector.fts_shapes {
			fts_shapes << SidecarFtsShape{
				kind:             shape.kind
				indexed:          shape.indexed
				index_name:       shape.index_name
				planner_strategy: shape.planner_strategy
				sample_explain:   sidecar_query_sample_plan_explain(shape.sample_explain)
			}
		}
		field_selectors << SidecarQuerySchemaFieldSelector{
			column_name:      selector.column_name
			plugin_name:      selector.plugin_name
			selector:         selector.selector
			value_type:       selector.value_type
			stores_row:       selector.stores_row
			filter_ops:       selector.filter_ops.clone()
			index_names:      selector.index_names.clone()
			projection_names: selector.projection_names.clone()
			planner_hints:    planner_hints
			filter_shapes:    filter_shapes
			fts_query_kinds:  selector.fts_query_kinds.clone()
			fts_shapes:       fts_shapes
		}
	}
	mut projection_metrics := []SidecarQuerySchemaProjection{cap: dto.projection_metrics.len}
	for projection in dto.projection_metrics {
		projection_metrics << SidecarQuerySchemaProjection{
			name:             projection.name
			column_name:      projection.column_name
			source_json_path: projection.source_json_path
			plugin_name:      projection.plugin_name
			selector:         projection.selector
			value_type:       projection.value_type
			aggregate:        projection.aggregate
			priority:         projection.priority
			cost_hint:        projection.cost_hint
		}
	}
	return SidecarQuerySchema{
		branch_name:                 dto.branch_name
		table_name:                  dto.table_name
		primary_key:                 dto.primary_key.clone()
		columns:                     columns
		indexes:                     indexes
		field_selectors:             field_selectors
		projection_metrics:          projection_metrics
		supported_filter_ops:        dto.supported_filter_ops.clone()
		default_result_shape:        dto.default_result_shape
		supports_continuation_token: dto.supports_continuation_token
		supports_select_projection:  dto.supports_select_projection
	}
}

pub fn (client PollyLinkClient) query_fts_preview(query SidecarFtsQueryRequest) !SidecarFtsQueryPreview {
	response := client.post_json('/v1/query-fts-preview', json.encode(SidecarFtsQueryRequestDto{
		repo_name:      client.repo_name
		branch_name:    query.branch_name
		table_name:     query.table_name
		column_name:    query.column_name
		scope:          query.scope
		query_kind:     query.query_kind
		terms:          query.terms.clone()
		select_columns: query.select_columns.clone()
		limit:          query.limit
	}))!
	dto := json.decode(SidecarFtsQueryPreviewDto, response.body)!
	return SidecarFtsQueryPreview{
		branch_name: dto.branch_name
		table_name:  dto.table_name
		column_name: dto.column_name
		scope:       dto.scope
		query_kind:  dto.query_kind
		terms:       dto.terms.clone()
		plan:        SidecarFtsQueryPlan{
			strategy:   dto.plan.strategy
			index_name: dto.plan.index_name
			selector:   dto.plan.selector
			scope:      dto.plan.scope
			query_kind: dto.plan.query_kind
			term_count: dto.plan.term_count
			limit:      dto.plan.limit
		}
		explain:     sidecar_query_sample_plan_explain(dto.explain)
		warnings:    dto.warnings.clone()
		notes:       dto.notes.clone()
	}
}

pub fn (client PollyLinkClient) query_fts(query SidecarFtsQueryRequest) !SidecarFtsQueryResult {
	response := client.post_json('/v1/query-fts', json.encode(SidecarFtsQueryRequestDto{
		repo_name:      client.repo_name
		branch_name:    query.branch_name
		table_name:     query.table_name
		column_name:    query.column_name
		scope:          query.scope
		query_kind:     query.query_kind
		terms:          query.terms.clone()
		select_columns: query.select_columns.clone()
		limit:          query.limit
	}))!
	dto := json.decode(SidecarFtsQueryResultDto, response.body)!
	mut rows := []SidecarTypedRow{cap: dto.rows.len}
	for row in dto.rows {
		rows << sidecar_typed_row(row)
	}
	mut hits := []SidecarFtsHit{cap: dto.hits.len}
	for hit in dto.hits {
		hits << SidecarFtsHit{
			primary_key:    hit.primary_key
			score:          hit.score
			matched_terms:  hit.matched_terms.clone()
			matched_scopes: hit.matched_scopes.clone()
			summary:        hit.summary
		}
	}
	return SidecarFtsQueryResult{
		branch_name:    dto.branch_name
		table_name:     dto.table_name
		column_name:    dto.column_name
		scope:          dto.scope
		query_kind:     dto.query_kind
		terms:          dto.terms.clone()
		select_columns: dto.select_columns.clone()
		plan:           SidecarFtsQueryPlan{
			strategy:   dto.plan.strategy
			index_name: dto.plan.index_name
			selector:   dto.plan.selector
			scope:      dto.plan.scope
			query_kind: dto.plan.query_kind
			term_count: dto.plan.term_count
			limit:      dto.plan.limit
		}
		hits:           hits
		rows:           rows
	}
}

pub fn (client PollyLinkClient) general_query_fts_preview(query SidecarGeneralFtsQueryRequest) !SidecarGeneralFtsQueryPreview {
	response := client.post_json('/v1/general-query-fts-preview', json.encode(SidecarGeneralFtsQueryRequestDto{
		repo_name:      client.repo_name
		branch_name:    query.branch_name
		table_name:     query.table_name
		index_name:     query.index_name
		query_kind:     query.query_kind
		terms:          query.terms.clone()
		select_columns: query.select_columns.clone()
		limit:          query.limit
	}))!
	dto := json.decode(SidecarGeneralFtsQueryPreviewDto, response.body)!
	return SidecarGeneralFtsQueryPreview{
		branch_name: dto.branch_name
		table_name:  dto.table_name
		index_name:  dto.index_name
		query_kind:  dto.query_kind
		terms:       dto.terms.clone()
		plan:        SidecarGeneralFtsQueryPlan{
			strategy:    dto.plan.strategy
			index_name:  dto.plan.index_name
			column_name: dto.plan.column_name
			backend:     dto.plan.backend
			query_kind:  dto.plan.query_kind
			term_count:  dto.plan.term_count
			limit:       dto.plan.limit
		}
	}
}

pub fn (client PollyLinkClient) general_query_fts(query SidecarGeneralFtsQueryRequest) !SidecarGeneralFtsQueryResult {
	response := client.post_json('/v1/general-query-fts', json.encode(SidecarGeneralFtsQueryRequestDto{
		repo_name:      client.repo_name
		branch_name:    query.branch_name
		table_name:     query.table_name
		index_name:     query.index_name
		query_kind:     query.query_kind
		terms:          query.terms.clone()
		select_columns: query.select_columns.clone()
		limit:          query.limit
	}))!
	dto := json.decode(SidecarGeneralFtsQueryResultDto, response.body)!
	mut rows := []SidecarTypedRow{cap: dto.rows.len}
	for row in dto.rows {
		rows << sidecar_typed_row(row)
	}
	mut hits := []SidecarGeneralFtsHit{cap: dto.hits.len}
	for hit in dto.hits {
		hits << SidecarGeneralFtsHit{
			primary_key: hit.primary_key
			score:       hit.score
			snippet:     hit.snippet
		}
	}
	return SidecarGeneralFtsQueryResult{
		branch_name:    dto.branch_name
		table_name:     dto.table_name
		index_name:     dto.index_name
		query_kind:     dto.query_kind
		terms:          dto.terms.clone()
		select_columns: dto.select_columns.clone()
		plan:           SidecarGeneralFtsQueryPlan{
			strategy:    dto.plan.strategy
			index_name:  dto.plan.index_name
			column_name: dto.plan.column_name
			backend:     dto.plan.backend
			query_kind:  dto.plan.query_kind
			term_count:  dto.plan.term_count
			limit:       dto.plan.limit
		}
		hits:           hits
		rows:           rows
	}
}

pub fn (client PollyLinkClient) query_plan_preview(query SidecarQueryRowsPostRequest) !SidecarQueryPlanPreview {
	mut filters := []SidecarQueryFilterDto{cap: query.filters.len}
	for filter in query.filters {
		filters << SidecarQueryFilterDto{
			column_name:  filter.column_name
			plugin_name:  filter.plugin_name
			selector:     filter.selector
			query_kind:   filter.query_kind
			value:        filter.value
			second_value: filter.second_value
		}
	}
	response := client.post_json('/v1/query-plan-preview', json.encode(SidecarQueryRowsPostRequestDto{
		repo_name:          client.repo_name
		branch_name:        query.branch_name
		table_name:         query.table_name
		filters:            filters
		general_fts:        sidecar_general_fts_clause_dto(query.general_fts)
		select_columns:     query.select_columns.clone()
		start_primary_key:  ''
		start_index_value:  ''
		continuation_token: ''
		limit:              query.limit
	}))!
	dto := json.decode(SidecarQueryPlanPreviewDto, response.body)!
	mut filter_models := []SidecarQueryFilter{cap: dto.filters.len}
	for filter in dto.filters {
		filter_models << SidecarQueryFilter{
			column_name:  filter.column_name
			plugin_name:  filter.plugin_name
			selector:     filter.selector
			query_kind:   filter.query_kind
			value:        filter.value
			second_value: filter.second_value
		}
	}
	mut post_filters := []SidecarQueryFilter{cap: dto.plan.post_filters.len}
	for filter in dto.plan.post_filters {
		post_filters << SidecarQueryFilter{
			column_name:  filter.column_name
			plugin_name:  filter.plugin_name
			selector:     filter.selector
			query_kind:   filter.query_kind
			value:        filter.value
			second_value: filter.second_value
		}
	}
	return SidecarQueryPlanPreview{
		branch_name:                 dto.branch_name
		table_name:                  dto.table_name
		filters:                     filter_models
		general_fts:                 sidecar_general_fts_clause_from_dto(dto.general_fts)
		select_columns:              dto.select_columns.clone()
		plan:                        SidecarQueryPlan{
			strategy:          dto.plan.strategy
			index_name:        dto.plan.index_name
			index_filter:      SidecarQueryFilter{
				column_name:  dto.plan.index_filter.column_name
				plugin_name:  dto.plan.index_filter.plugin_name
				selector:     dto.plan.index_filter.selector
				query_kind:   dto.plan.index_filter.query_kind
				value:        dto.plan.index_filter.value
				second_value: dto.plan.index_filter.second_value
			}
			post_filters:      post_filters
			post_filter_count: dto.plan.post_filter_count
			limit:             dto.plan.limit
		}
		explain:                     sidecar_query_sample_plan_explain(dto.explain)
		warnings:                    dto.warnings.clone()
		notes:                       dto.notes.clone()
		default_result_shape:        dto.default_result_shape
		supports_continuation_token: dto.supports_continuation_token
	}
}

pub fn (client PollyLinkClient) markdown_metric(branch_name string, table_name string, column_name string, selector string) !SidecarMarkdownMetric {
	path := if client.repo_name.len == 0 {
		'/v1/markdown-metric?branch=${branch_name}&table=${table_name}&column=${column_name}&selector=${selector}'
	} else {
		'/v1/markdown-metric?repo=${client.repo_name}&branch=${branch_name}&table=${table_name}&column=${column_name}&selector=${selector}'
	}
	response := client.get(path)!
	dto := json.decode(SidecarMarkdownMetricDto, response.body)!
	return SidecarMarkdownMetric{
		branch_name: dto.branch_name
		table_name:  dto.table_name
		column_name: dto.column_name
		selector:    dto.selector
		value:       dto.value
	}
}

pub fn (client PollyLinkClient) index_lookup(branch_name string, table_name string, index_name string, value string, limit int) !SidecarIndexLookup {
	path := if client.repo_name.len == 0 {
		'/v1/index-lookup?branch=${branch_name}&table=${table_name}&index=${index_name}&value=${value}&limit=${limit}'
	} else {
		'/v1/index-lookup?repo=${client.repo_name}&branch=${branch_name}&table=${table_name}&index=${index_name}&value=${value}&limit=${limit}'
	}
	response := client.get(path)!
	dto := json.decode(SidecarIndexLookupDto, response.body)!
	mut rows := []SidecarTypedRow{cap: dto.rows.len}
	for row in dto.rows {
		rows << SidecarTypedRow{
			primary_key: row.primary_key
			values:      row.values.clone()
		}
	}
	return SidecarIndexLookup{
		branch_name:         dto.branch_name
		table_name:          dto.table_name
		index_name:          dto.index_name
		field_selector_meta: SidecarFieldSelectorMeta{
			plugin_name: dto.field_selector_meta.plugin_name
			selector:    dto.field_selector_meta.selector
			value_type:  dto.field_selector_meta.value_type
			stores_row:  dto.field_selector_meta.stores_row
		}
		query_kind:          dto.query_kind
		value:               dto.value
		rows:                rows
	}
}

pub fn (client PollyLinkClient) index_lookup_prefix(branch_name string, table_name string, index_name string, value string, limit int) !SidecarIndexLookup {
	path := if client.repo_name.len == 0 {
		'/v1/index-lookup-prefix?branch=${branch_name}&table=${table_name}&index=${index_name}&value=${value}&limit=${limit}'
	} else {
		'/v1/index-lookup-prefix?repo=${client.repo_name}&branch=${branch_name}&table=${table_name}&index=${index_name}&value=${value}&limit=${limit}'
	}
	response := client.get(path)!
	dto := json.decode(SidecarIndexLookupDto, response.body)!
	mut rows := []SidecarTypedRow{cap: dto.rows.len}
	for row in dto.rows {
		rows << SidecarTypedRow{
			primary_key: row.primary_key
			values:      row.values.clone()
		}
	}
	return SidecarIndexLookup{
		branch_name:         dto.branch_name
		table_name:          dto.table_name
		index_name:          dto.index_name
		field_selector_meta: SidecarFieldSelectorMeta{
			plugin_name: dto.field_selector_meta.plugin_name
			selector:    dto.field_selector_meta.selector
			value_type:  dto.field_selector_meta.value_type
			stores_row:  dto.field_selector_meta.stores_row
		}
		query_kind:          dto.query_kind
		value:               dto.value
		rows:                rows
	}
}

pub fn (client PollyLinkClient) markdown_query(query SidecarMarkdownQueryRequest) !SidecarMarkdownQuery {
	mut path := if client.repo_name.len == 0 {
		'/v1/markdown-query?branch=${query.branch_name}&table=${query.table_name}&kind=${query.query_kind}'
	} else {
		'/v1/markdown-query?repo=${client.repo_name}&branch=${query.branch_name}&table=${query.table_name}&kind=${query.query_kind}'
	}
	if query.column_name.len > 0 {
		path += '&column=${query.column_name}'
	}
	if query.selector.len > 0 {
		path += '&selector=${query.selector}'
	}
	if query.index_name.len > 0 {
		path += '&index=${query.index_name}'
	}
	if query.value.len > 0 {
		path += '&value=${query.value}'
	}
	if query.limit > 0 {
		path += '&limit=${query.limit}'
	}
	response := client.get(path)!
	dto := json.decode(SidecarMarkdownQueryDto, response.body)!
	mut rows := []SidecarTypedRow{cap: dto.rows.len}
	for row in dto.rows {
		rows << SidecarTypedRow{
			primary_key: row.primary_key
			values:      row.values.clone()
		}
	}
	return SidecarMarkdownQuery{
		branch_name:         dto.branch_name
		table_name:          dto.table_name
		column_name:         dto.column_name
		selector:            dto.selector
		index_name:          dto.index_name
		field_selector_meta: SidecarFieldSelectorMeta{
			plugin_name: dto.field_selector_meta.plugin_name
			selector:    dto.field_selector_meta.selector
			value_type:  dto.field_selector_meta.value_type
			stores_row:  dto.field_selector_meta.stores_row
		}
		query_kind:          dto.query_kind
		value:               dto.value
		metric_value:        dto.metric_value
		rows:                rows
	}
}

fn sidecar_query_page_from_dto(dto SidecarQueryRowsDto) SidecarQueryPage {
	mut rows := []SidecarTypedRow{cap: dto.rows.len}
	for row in dto.rows {
		rows << SidecarTypedRow{
			primary_key: row.primary_key
			values:      row.values.clone()
		}
	}
	mut post_filters := []SidecarQueryFilter{cap: dto.plan.post_filters.len}
	for filter in dto.plan.post_filters {
		post_filters << SidecarQueryFilter{
			column_name:  filter.column_name
			plugin_name:  filter.plugin_name
			selector:     filter.selector
			query_kind:   filter.query_kind
			value:        filter.value
			second_value: filter.second_value
		}
	}
	mut general_fts_hits := []SidecarGeneralFtsHit{cap: dto.general_fts_hits.len}
	for hit in dto.general_fts_hits {
		general_fts_hits << SidecarGeneralFtsHit{
			primary_key: hit.primary_key
			score:       hit.score
			snippet:     hit.snippet
		}
	}
	return SidecarQueryPage{
		rows:                rows
		plan:                SidecarQueryPlan{
			strategy:          dto.plan.strategy
			index_name:        dto.plan.index_name
			index_filter:      SidecarQueryFilter{
				column_name:  dto.plan.index_filter.column_name
				plugin_name:  dto.plan.index_filter.plugin_name
				selector:     dto.plan.index_filter.selector
				query_kind:   dto.plan.index_filter.query_kind
				value:        dto.plan.index_filter.value
				second_value: dto.plan.index_filter.second_value
			}
			post_filters:      post_filters
			post_filter_count: dto.plan.post_filter_count
			limit:             dto.plan.limit
		}
		cursor:              SidecarQueryCursor{
			has_more:                dto.cursor.has_more
			next_primary_key:        dto.cursor.next_primary_key
			next_index_value:        dto.cursor.next_index_value
			next_continuation_token: dto.cursor.next_continuation_token
		}
		general_fts_hits:    general_fts_hits
		field_selector_meta: SidecarFieldSelectorMeta{
			plugin_name: dto.field_selector_meta.plugin_name
			selector:    dto.field_selector_meta.selector
			value_type:  dto.field_selector_meta.value_type
			stores_row:  dto.field_selector_meta.stores_row
		}
	}
}

fn sidecar_query_compat_rows_from_request(query SidecarQueryRowsRequest, page SidecarQueryPage) SidecarQueryRows {
	return SidecarQueryRows{
		branch_name:             query.branch_name
		table_name:              query.table_name
		column_name:             query.column_name
		plugin_name:             query.plugin_name
		selector:                query.selector
		field_selector_meta:     page.field_selector_meta
		query_kind:              query.query_kind
		value:                   query.value
		general_fts:             SidecarGeneralFtsClause{}
		select_columns:          query.select_columns.clone()
		start_primary_key:       query.start_primary_key
		start_index_value:       query.start_index_value
		continuation_token:      query.continuation_token
		plan:                    page.plan
		cursor:                  page.cursor
		general_fts_hits:        page.general_fts_hits.clone()
		has_more:                page.cursor.has_more
		next_primary_key:        page.cursor.next_primary_key
		next_index_value:        page.cursor.next_index_value
		next_continuation_token: page.cursor.next_continuation_token
		rows:                    page.rows.clone()
	}
}

fn sidecar_query_compat_rows_from_post_request(query SidecarQueryRowsPostRequest, page SidecarQueryPage) SidecarQueryRows {
	first := if query.filters.len > 0 { query.filters[0] } else { SidecarQueryFilter{} }
	return SidecarQueryRows{
		branch_name:             query.branch_name
		table_name:              query.table_name
		column_name:             first.column_name
		plugin_name:             first.plugin_name
		selector:                first.selector
		field_selector_meta:     page.field_selector_meta
		query_kind:              first.query_kind
		value:                   first.value
		general_fts:             query.general_fts
		select_columns:          query.select_columns.clone()
		start_primary_key:       query.start_primary_key
		start_index_value:       query.start_index_value
		continuation_token:      query.continuation_token
		plan:                    page.plan
		cursor:                  page.cursor
		general_fts_hits:        page.general_fts_hits.clone()
		has_more:                page.cursor.has_more
		next_primary_key:        page.cursor.next_primary_key
		next_index_value:        page.cursor.next_index_value
		next_continuation_token: page.cursor.next_continuation_token
		rows:                    page.rows.clone()
	}
}

// query_rows is the compatibility client helper. Prefer query_page for new code.
pub fn (client PollyLinkClient) query_rows(query SidecarQueryRowsRequest) !SidecarQueryRows {
	return sidecar_query_compat_rows_from_request(query, client.query_page(query)!)
}

// query_page is the preferred client helper for paged query results.
pub fn (client PollyLinkClient) query_page(query SidecarQueryRowsRequest) !SidecarQueryPage {
	mut path := if client.repo_name.len == 0 {
		'/v1/query-rows?branch=${query.branch_name}&table=${query.table_name}&column=${query.column_name}&kind=${query.query_kind}'
	} else {
		'/v1/query-rows?repo=${client.repo_name}&branch=${query.branch_name}&table=${query.table_name}&column=${query.column_name}&kind=${query.query_kind}'
	}
	if query.plugin_name.len > 0 {
		path += '&plugin=${query.plugin_name}'
	}
	if query.selector.len > 0 {
		path += '&selector=${query.selector}'
	}
	path += '&value=${query.value}'
	if query.select_columns.len > 0 {
		path += '&select=${query.select_columns.join(',')}'
	}
	if query.start_primary_key.len > 0 {
		path += '&start_primary_key=${query.start_primary_key}'
	}
	if query.start_index_value.len > 0 {
		path += '&start_index_value=${query.start_index_value}'
	}
	if query.continuation_token.len > 0 {
		path += '&continuation_token=${query.continuation_token}'
	}
	if query.limit > 0 {
		path += '&limit=${query.limit}'
	}
	response := client.get(path)!
	dto := json.decode(SidecarQueryRowsDto, response.body)!
	return sidecar_query_page_from_dto(dto)
}

// query_rows_post is the compatibility client helper. Prefer query_page_post.
pub fn (client PollyLinkClient) query_rows_post(query SidecarQueryRowsPostRequest) !SidecarQueryRows {
	return sidecar_query_compat_rows_from_post_request(query, client.query_page_post(query)!)
}

// query_page_post is the preferred client helper for paged POST query results.
pub fn (client PollyLinkClient) query_page_post(query SidecarQueryRowsPostRequest) !SidecarQueryPage {
	mut filters := []SidecarQueryFilterDto{cap: query.filters.len}
	for filter in query.filters {
		filters << SidecarQueryFilterDto{
			column_name:  filter.column_name
			plugin_name:  filter.plugin_name
			selector:     filter.selector
			query_kind:   filter.query_kind
			value:        filter.value
			second_value: filter.second_value
		}
	}
	response := client.post_json('/v1/query-rows', json.encode(SidecarQueryRowsPostRequestDto{
		repo_name:          client.repo_name
		branch_name:        query.branch_name
		table_name:         query.table_name
		filters:            filters
		general_fts:        sidecar_general_fts_clause_dto(query.general_fts)
		select_columns:     query.select_columns.clone()
		start_primary_key:  query.start_primary_key
		start_index_value:  query.start_index_value
		continuation_token: query.continuation_token
		limit:              query.limit
	}))!
	dto := json.decode(SidecarQueryRowsDto, response.body)!
	return sidecar_query_page_from_dto(dto)
}

pub fn (rows SidecarQueryRows) page() SidecarQueryPage {
	return SidecarQueryPage{
		rows:                rows.rows.clone()
		plan:                rows.plan
		cursor:              rows.cursor
		general_fts_hits:    rows.general_fts_hits.clone()
		field_selector_meta: rows.field_selector_meta
	}
}

pub fn (client PollyLinkClient) open_repository(default_branch string) !SidecarRepositoryInfo {
	response := client.post_json('/v1/repos/open', json.encode(SidecarRepoOpenRequestDto{
		repo_name:      client.repo_name
		default_branch: default_branch
	}))!
	dto := json.decode(SidecarRepositoryInfoDto, response.body)!
	return SidecarRepositoryInfo{
		repo_name:             dto.repo_name
		default_branch:        dto.default_branch
		branch_count:          dto.branch_count
		latest_branch:         dto.latest_branch
		latest_commit_cid:     dto.latest_commit_cid
		latest_timestamp:      dto.latest_timestamp
		auth_enabled:          dto.auth_enabled
		allow_push_to_default: dto.allow_push_to_default
		require_auto_merge:    dto.require_auto_merge
		default_sync_policy:   dto.default_sync_policy
		protection_summary:    dto.protection_summary
	}
}

pub fn (client PollyLinkClient) branch_activity(branch_name string) !SidecarBranchActivity {
	path := if client.repo_name.len == 0 {
		'/v1/branch-activity?branch=${branch_name}'
	} else {
		'/v1/branch-activity?repo=${client.repo_name}&branch=${branch_name}'
	}
	response := client.get(path)!
	dto := json.decode(SidecarBranchActivityDto, response.body)!
	return SidecarBranchActivity{
		branch:       branch_from_dto(dto.branch)
		root_cid:     dto.root_cid
		parent_count: dto.parent_count
		author:       dto.author
		message:      dto.message
		timestamp:    dto.timestamp
	}
}

pub fn (client PollyLinkClient) branch_log(branch_name string, limit int) ![]SidecarBranchLogEntry {
	path := if client.repo_name.len == 0 {
		'/v1/branch-log?branch=${branch_name}&limit=${limit}'
	} else {
		'/v1/branch-log?repo=${client.repo_name}&branch=${branch_name}&limit=${limit}'
	}
	response := client.get(path)!
	payload := json.decode(SidecarBranchLogDto, response.body)!
	mut commits := []SidecarBranchLogEntry{cap: payload.commits.len}
	for commit in payload.commits {
		commits << SidecarBranchLogEntry{
			cid:          commit.cid
			root_cid:     commit.root_cid
			parent_count: commit.parent_count
			author:       commit.author
			message:      commit.message
			timestamp:    commit.timestamp
		}
	}
	return commits
}

pub fn (client PollyLinkClient) repo_activity(limit int) ![]SidecarRepoActivityEntry {
	path := if client.repo_name.len == 0 {
		'/v1/repo-activity?limit=${limit}'
	} else {
		'/v1/repo-activity?repo=${client.repo_name}&limit=${limit}'
	}
	response := client.get(path)!
	payload := json.decode(SidecarRepoActivityDto, response.body)!
	mut entries := []SidecarRepoActivityEntry{cap: payload.entries.len}
	for entry in payload.entries {
		entries << SidecarRepoActivityEntry{
			repo_name:    entry.repo_name
			branch:       branch_from_dto(entry.branch)
			root_cid:     entry.root_cid
			parent_count: entry.parent_count
			author:       entry.author
			message:      entry.message
			timestamp:    entry.timestamp
		}
	}
	return entries
}

pub fn (client PollyLinkClient) global_activity(limit int) ![]SidecarRepoActivityEntry {
	response := client.get('/v1/global-activity?limit=${limit}')!
	payload := json.decode(SidecarGlobalActivityDto, response.body)!
	mut entries := []SidecarRepoActivityEntry{cap: payload.entries.len}
	for entry in payload.entries {
		entries << SidecarRepoActivityEntry{
			repo_name:    entry.repo_name
			branch:       branch_from_dto(entry.branch)
			root_cid:     entry.root_cid
			parent_count: entry.parent_count
			author:       entry.author
			message:      entry.message
			timestamp:    entry.timestamp
		}
	}
	return entries
}

fn fetch_remote_branch_into_repo(mut repo PersistentRepository, client PollyLinkClient, branch_name string) !SyncOffer {
	envelope := client.offer(branch_name, branch_name, 0)!
	exchange := client.fetch_full_exchange(envelope.offer)!
	import_sync_exchange_objects(mut repo, exchange)!
	return envelope.offer
}

pub fn build_auto_merge_offer_for_remote_offer(mut source_repo PersistentRepository, source_branch string, target_branch string, remote_offer SyncOffer) !SyncOffer {
	source_branch_head := source_repo.branch(source_branch)!
	source_commit := source_repo.commit_store.get(source_branch_head.commit_cid)!
	base_commit := source_repo.repo.merge_base_commit(source_commit.cid, remote_offer.target_commit_cid, mut
		source_repo.commit_store)!
	merge_result := auto_merge_by_roots(base_commit.root_cid, source_commit.root_cid,
		remote_offer.target_root_cid, ChunkConfig.default(), mut source_repo.node_store)!
	if merge_result.conflicts.len > 0 {
		return error('auto-merge required manual resolution: ${merge_result.conflicts.len} conflicts')
	}
	merge_meta := CommitMeta{
		author:    'pollylink'
		message:   'auto-merge ${source_branch} into ${target_branch}'
		timestamp: 0
	}
	snapshot := Snapshot.new(merge_result.tree, [source_commit.cid, remote_offer.target_commit_cid],
		merge_meta)
	snapshot.persist(mut source_repo.node_store, mut source_repo.commit_store)!
	return SyncOffer{
		request:                 SyncRequest{
			local_root_hash: snapshot.commit.root_cid
			branch_name:     target_branch
		}
		expected_old_commit_cid: remote_offer.target_commit_cid
		target_commit_cid:       snapshot.commit.cid
		target_root_cid:         snapshot.commit.root_cid
	}
}

fn build_auto_merge_sidecar_exchange(mut source_repo PersistentRepository, source_branch string, client PollyLinkClient, target_branch string) !SyncExchange {
	remote_offer := fetch_remote_branch_into_repo(mut source_repo, client, target_branch)!
	merged_offer := build_auto_merge_offer_for_remote_offer(mut source_repo, source_branch,
		target_branch, remote_offer)!
	return full_sync_exchange_for_offer(mut source_repo, merged_offer)
}

pub fn push_branch_to_sidecar(mut source_repo PersistentRepository, source_branch string, client PollyLinkClient, target_branch string, policy SyncNegotiationPolicy) !SyncPushResult {
	prediction_depth := match policy {
		.manifest_depth1, .auto { 1 }
		.manifest_depth2 { 2 }
		.regular { 0 }
	}
	envelope := client.offer(source_branch, target_branch, prediction_depth)!
	use_manifest := prediction_depth > 0
	missing := client.negotiate_missing(envelope.offer, envelope.manifest, use_manifest)!
	exchange := sync_exchange_for_missing(mut source_repo, envelope.offer, missing)!
	first_apply := client.try_apply_exchange(exchange)!
	if first_apply.ok {
		return SyncPushResult{
			session:  exchange.session
			exchange: exchange
			branch:   first_apply.branch
		}
	}
	err_msg := first_apply.error_msg
	if !is_branch_head_changed_error(err_msg) {
		return error(err_msg)
	}
	merged_exchange := build_auto_merge_sidecar_exchange(mut source_repo, source_branch,
		client, target_branch)!
	merged_branch := client.apply_exchange(merged_exchange)!
	return SyncPushResult{
		session:     merged_exchange.session
		exchange:    merged_exchange
		branch:      merged_branch
		auto_merged: true
	}
}

pub fn pull_branch_from_sidecar(mut target_repo PersistentRepository, target_branch string, client PollyLinkClient, source_branch string, policy SyncNegotiationPolicy) !SyncPullResult {
	prediction_depth := match policy {
		.manifest_depth1, .auto { 1 }
		.manifest_depth2 { 2 }
		.regular { 0 }
	}
	envelope := client.offer(source_branch, target_branch, prediction_depth)!
	missing := if prediction_depth > 0 {
		sync_missing_for_manifest(mut target_repo, envelope.manifest)!
	} else {
		sync_missing_for_offer(mut target_repo, envelope.offer)!
	}
	exchange := client.fetch_exchange(envelope.offer, missing)!
	branch := apply_exchange_to_repo(mut target_repo, exchange)!
	return SyncPullResult{
		session:  exchange.session
		exchange: exchange
		branch:   branch
	}
}
