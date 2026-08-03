module pollylink

import encoding.base64
import json
import net.http
import pollyhub
import storage

pub struct RepositoryInfo {
pub:
	repo_name             string
	default_branch        string
	branch_count          int
	branch_count_committed int
	latest_branch         string
	latest_commit_cid     string
	latest_timestamp      i64
	auth_enabled          bool
	allow_push_to_default bool
	require_auto_merge    bool
	default_sync_policy   string
	protection_summary    string
}

pub struct GovernanceCategory {
pub:
	category           string
	recent_requests_1m int
	recent_denies_1m   int
}

pub struct GovernanceActor {
pub:
	actor              string
	recent_requests_1m int
	recent_denies_1m   int
}

pub struct GovernanceAction {
pub:
	action             string
	recent_requests_1m int
	recent_denies_1m   int
}

pub struct GovernanceStatus {
pub:
	auth_enabled        bool
	token_count         int
	repo_count          int
	requests_per_minute int
	recent_requests_1m  int
	recent_denies_1m    int
	recent_categories   []GovernanceCategory
	recent_actors       []GovernanceActor
	recent_actions      []GovernanceAction
}

pub struct Branch {
pub:
	name       string
	commit_cid string
}

pub enum SyncPolicy {
	regular
	manifest_depth1
	manifest_depth2
	auto
}

pub enum RepoRole {
	reader
	writer
	admin
}

pub struct AuditEntry {
pub:
	timestamp   i64
	actor       string
	action      string
	repo_name   string
	branch_name string
	allowed     bool
	detail      string
}

pub struct SyncPushResult {
pub:
	branch       Branch
	packet_count int
	packet_bytes int
	auto_merged  bool
}

pub struct SyncPullResult {
pub:
	branch       Branch
	packet_count int
	packet_bytes int
}

struct SyncOfferEnvelope {
	offer    storage.SyncOffer
	manifest storage.SyncManifest
}

pub struct BranchStatus {
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

pub struct BranchActivity {
pub:
	branch       Branch
	root_cid     string
	parent_count int
	author       string
	message      string
	timestamp    i64
}

pub struct BranchLogEntry {
pub:
	cid          string
	root_cid     string
	parent_count int
	author       string
	message      string
	timestamp    i64
}

pub struct RepoActivityEntry {
pub:
	repo_name    string
	branch       Branch
	root_cid     string
	parent_count int
	author       string
	message      string
	timestamp    i64
}

pub struct FieldSelectorMeta {
pub:
	plugin_name string
	selector    string
	value_type  string
	stores_row  bool
}

pub struct ProjectorValue {
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
	source_field_selector_meta   FieldSelectorMeta
	source_field_selector_plugin string
	source_field_selector        string
	source_markdown_selector     string
}

pub struct MarkdownMetric {
pub:
	branch_name string
	table_name  string
	column_name string
	selector    string
	value       i64
}

pub struct TypedRow {
pub:
	primary_key string
	values      map[string]string
}

pub struct IndexLookup {
pub:
	branch_name         string
	table_name          string
	index_name          string
	field_selector_meta FieldSelectorMeta
	query_kind          string
	value               string
	rows                []TypedRow
}

pub struct ColumnDef {
pub:
	name        string
	typ         string
	nullable    bool
	aggregate   string
	enum_values []string
}

pub struct IndexDef {
pub:
	name                string
	column              string
	stores_row          bool
	json_field          string
	value_type          string
	field_selector_meta FieldSelectorMeta
}

pub struct TableSpec {
pub:
	branch_name string
	table_name  string
	primary_key []string
	columns     []ColumnDef
	indexes     []IndexDef
}

pub struct QueryPlannerHint {
pub:
	op         string
	strategy   string
	index_name string
	stores_row bool
	score      int
}

pub struct QuerySamplePlanExplain {
pub:
	strategy                    string
	index_name                  string
	warnings                    []string
	notes                       []string
	default_result_shape        string
	supports_continuation_token bool
}

pub struct QueryFilterShape {
pub:
	op                  string
	value_type          string
	indexed             bool
	index_name          string
	planner_strategy    string
	planner_score       int
	projection_only     bool
	continuation_anchor bool
	sample_explain      QuerySamplePlanExplain
}

pub struct FtsShape {
pub:
	kind             string
	indexed          bool
	index_name       string
	planner_strategy string
	sample_explain   QuerySamplePlanExplain
}

pub struct QuerySchemaColumn {
pub:
	name          string
	typ           string
	nullable      bool
	filter_ops    []string
	index_names   []string
	planner_hints []QueryPlannerHint
	filter_shapes []QueryFilterShape
}

pub struct QuerySchemaIndex {
pub:
	name                string
	column_name         string
	value_type          string
	stores_row          bool
	is_fts              bool
	fts_query_kinds     []string
	fts_shapes          []FtsShape
	json_field          string
	field_selector_meta FieldSelectorMeta
	filter_ops          []string
}

pub struct QuerySchemaFieldSelector {
pub:
	column_name      string
	plugin_name      string
	selector         string
	value_type       string
	stores_row       bool
	filter_ops       []string
	index_names      []string
	projection_names []string
	planner_hints    []QueryPlannerHint
	filter_shapes    []QueryFilterShape
	fts_query_kinds  []string
	fts_shapes       []FtsShape
}

pub struct QuerySchemaProjection {
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

pub struct QuerySchema {
pub:
	branch_name                 string
	table_name                  string
	primary_key                 []string
	columns                     []QuerySchemaColumn
	indexes                     []QuerySchemaIndex
	field_selectors             []QuerySchemaFieldSelector
	projection_metrics          []QuerySchemaProjection
	supported_filter_ops        []string
	default_result_shape        string
	supports_continuation_token bool
	supports_select_projection  bool
}

pub struct QueryFilter {
pub:
	column_name  string
	plugin_name  string
	selector     string
	query_kind   string
	value        string
	second_value string
}

pub struct GeneralFtsClause {
pub:
	index_name string
	query_kind string
	terms      []string
}

pub struct QueryPlan {
pub:
	strategy          string
	index_name        string
	index_filter      QueryFilter
	post_filters      []QueryFilter
	post_filter_count int
	limit             int
}

pub struct QueryCursor {
pub:
	has_more                bool
	next_primary_key        string
	next_index_value        string
	next_continuation_token string
}

pub struct QueryPlanPreview {
pub:
	branch_name                 string
	table_name                  string
	filters                     []QueryFilter
	general_fts                 GeneralFtsClause
	select_columns              []string
	plan                        QueryPlan
	explain                     QuerySamplePlanExplain
	warnings                    []string
	notes                       []string
	default_result_shape        string
	supports_continuation_token bool
}

pub struct MarkdownQueryRequest {
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

pub struct MarkdownQuery {
pub:
	branch_name         string
	table_name          string
	column_name         string
	selector            string
	index_name          string
	field_selector_meta FieldSelectorMeta
	query_kind          string
	value               string
	metric_value        i64
	rows                []TypedRow
}

pub struct QueryRowsRequest {
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

pub struct QueryRowsPostRequest {
pub:
	branch_name        string
	table_name         string
	filters            []QueryFilter
	general_fts        GeneralFtsClause
	select_columns     []string
	start_primary_key  string
	start_index_value  string
	continuation_token string
	limit              int
}

pub struct GeneralFtsQueryRequest {
pub:
	branch_name    string
	table_name     string
	index_name     string
	query_kind     string
	terms          []string
	select_columns []string
	limit          int
}

pub struct GeneralFtsQueryPlan {
pub:
	strategy    string
	index_name  string
	column_name string
	backend     string
	query_kind  string
	term_count  int
	limit       int
}

pub struct GeneralFtsHit {
pub:
	primary_key string
	score       f64
	snippet     string
}

pub struct GeneralFtsQueryPreview {
pub:
	branch_name string
	table_name  string
	index_name  string
	query_kind  string
	terms       []string
	plan        GeneralFtsQueryPlan
}

pub struct GeneralFtsQueryResult {
pub:
	branch_name    string
	table_name     string
	index_name     string
	query_kind     string
	terms          []string
	select_columns []string
	plan           GeneralFtsQueryPlan
	hits           []GeneralFtsHit
	rows           []TypedRow
}

pub struct QueryPage {
pub:
	rows                []TypedRow
	plan                QueryPlan
	cursor              QueryCursor
	general_fts_hits    []GeneralFtsHit
	field_selector_meta FieldSelectorMeta
}

fn (page QueryPage) rows_and_meta(query QueryRowsRequest) QueryRows {
	return QueryRows{
		branch_name:             query.branch_name
		table_name:              query.table_name
		column_name:             query.column_name
		plugin_name:             query.plugin_name
		selector:                query.selector
		field_selector_meta:     page.field_selector_meta
		query_kind:              query.query_kind
		value:                   query.value
		general_fts:             GeneralFtsClause{}
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

fn (page QueryPage) rows_and_meta_post(query QueryRowsPostRequest) QueryRows {
	first := if query.filters.len > 0 { query.filters[0] } else { QueryFilter{} }
	return QueryRows{
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

pub struct QueryRows {
pub:
	branch_name             string
	table_name              string
	column_name             string
	plugin_name             string
	selector                string
	field_selector_meta     FieldSelectorMeta
	query_kind              string
	value                   string
	general_fts             GeneralFtsClause
	select_columns          []string
	start_primary_key       string
	start_index_value       string
	continuation_token      string
	plan                    QueryPlan
	cursor                  QueryCursor
	general_fts_hits        []GeneralFtsHit
	has_more                bool
	next_primary_key        string
	next_index_value        string
	next_continuation_token string
	rows                    []TypedRow
}

pub struct FtsQueryPlan {
pub:
	strategy   string
	index_name string
	selector   string
	scope      string
	query_kind string
	term_count int
	limit      int
}

pub struct FtsQueryRequest {
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

pub struct FtsHit {
pub:
	primary_key    string
	score          int
	matched_terms  []string
	matched_scopes []string
	summary        string
}

pub struct FtsQueryPreview {
pub:
	branch_name string
	table_name  string
	column_name string
	scope       string
	query_kind  string
	terms       []string
	plan        FtsQueryPlan
	explain     QuerySamplePlanExplain
	warnings    []string
	notes       []string
}

pub struct FtsQueryResult {
pub:
	branch_name    string
	table_name     string
	column_name    string
	scope          string
	query_kind     string
	terms          []string
	select_columns []string
	plan           FtsQueryPlan
	hits           []FtsHit
	rows           []TypedRow
}

pub struct SidecarHandler {
pub:
	root_dir       string
	default_branch string
}

pub fn (handler SidecarHandler) handle(req http.Request) http.Response {
	return handle_sidecar_request(handler.root_dir, handler.default_branch, req)
}

pub fn start_sidecar(root_dir string, default_branch string, addr string) !&http.Server {
	mut server := &http.Server{
		addr: addr
		handler: SidecarHandler{
			root_dir:       root_dir
			default_branch: default_branch
		}
		show_startup_message: false
	}
	spawn server.listen_and_serve()
	server.wait_till_running()!
	return server
}

struct RepoListResponse {
	repos []string
}

struct RepoSummaryListResponse {
	repos []RepositoryInfo
}

struct RepoInfoQueryResponse {
	repo RepositoryInfo
}

struct BranchListResponse {
	branches []Branch
}

struct BranchStatusListResponse {
	branches []BranchStatus
}

struct BranchLogResponse {
	commits []BranchLogEntry
}

struct RepoActivityResponse {
	entries []RepoActivityEntry
}

struct QueryRowsPostRequestBody {
	repo_name          string
	branch_name        string
	table_name         string
	filters            []QueryFilter
	general_fts        GeneralFtsClause
	select_columns     []string
	start_primary_key  string
	start_index_value  string
	continuation_token string
	limit              int
}

struct FtsQueryRequestBody {
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

struct GeneralFtsQueryRequestBody {
	repo_name      string
	branch_name    string
	table_name     string
	index_name     string
	query_kind     string
	terms          []string
	select_columns []string
	limit          int
}

struct OpenRepoRequestBody {
	repo_name      string
	default_branch string
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

struct SyncExchangeDto {
	session SyncSessionDto
	plan    SyncPlanDto
	packets []DataPacketDto
}

struct SyncOfferEnvelopeDto {
	offer        SyncOfferDto
	manifest     SyncManifestDto
	has_manifest bool
}

struct SyncOfferRequestBody {
	repo_name        string
	branch_name      string
	target_branch    string
	prediction_depth int
}

struct SyncNegotiateRequestBody {
	repo_name    string
	offer        SyncOfferDto
	manifest     SyncManifestDto
	use_manifest bool
}

struct SyncExchangeRequestBody {
	repo_name string
	offer     SyncOfferDto
	missing   SyncMissingSetDto
}

struct SyncFullExchangeRequestBody {
	repo_name string
	offer     SyncOfferDto
}

struct SyncApplyRequestBody {
	repo_name string
	exchange  SyncExchangeDto
}

struct SyncErrorDto {
	error string
}

pub struct Client {
pub:
	base_url   string
	repo_name  string
	auth_token string
}

pub struct LocalRepo {
mut:
	repo storage.PersistentRepository
}

pub fn open_local_repo(root_dir string, default_branch string) !LocalRepo {
	return LocalRepo{
		repo: storage.PersistentRepository.open_default(root_dir, default_branch)!
	}
}

pub fn (mut repo LocalRepo) close() ! {
	repo.repo.close()!
}

fn audit_entry_from_pollyhub(entry pollyhub.AuditEntry) AuditEntry {
	return AuditEntry{
		timestamp:   entry.timestamp
		actor:       entry.actor
		action:      entry.action
		repo_name:   entry.repo_name
		branch_name: entry.branch_name
		allowed:     entry.allowed
		detail:      entry.detail
	}
}

pub fn sync_policy_from_string(value string) !SyncPolicy {
	return match value {
		'regular' { .regular }
		'manifest_depth1' { .manifest_depth1 }
		'manifest_depth2' { .manifest_depth2 }
		'auto' { .auto }
		else { error('invalid sync negotiation policy: ${value}') }
	}
}

pub fn (policy SyncPolicy) label() string {
	return match policy {
		.regular { 'regular' }
		.manifest_depth1 { 'manifest_depth1' }
		.manifest_depth2 { 'manifest_depth2' }
		.auto { 'auto' }
	}
}

fn sync_packet_bytes_storage(packets []storage.DataPacket) int {
	mut total := 0
	for packet in packets {
		total += packet.data.len
	}
	return total
}

struct ApplyExchangeResult {
	ok        bool
	branch    Branch
	error_msg string
}

fn is_branch_head_changed_error(err_msg string) bool {
	return err_msg.contains('branch head changed during compare-and-swap')
}

fn sync_offer_to_dto(offer storage.SyncOffer) SyncOfferDto {
	return SyncOfferDto{
		request_local_root_hash: offer.request.local_root_hash
		request_branch_name:     offer.request.branch_name
		expected_old_commit_cid: offer.expected_old_commit_cid
		target_commit_cid:       offer.target_commit_cid
		target_root_cid:         offer.target_root_cid
	}
}

fn sync_offer_from_dto(dto SyncOfferDto) storage.SyncOffer {
	return storage.SyncOffer{
		request: storage.SyncRequest{
			local_root_hash: dto.request_local_root_hash
			branch_name:     dto.request_branch_name
		}
		expected_old_commit_cid: dto.expected_old_commit_cid
		target_commit_cid:       dto.target_commit_cid
		target_root_cid:         dto.target_root_cid
	}
}

fn sync_manifest_to_dto(manifest storage.SyncManifest) SyncManifestDto {
	return SyncManifestDto{
		offer:            sync_offer_to_dto(manifest.offer)
		prediction_depth: manifest.prediction_depth
		level_1_hashes:   manifest.level_1_hashes.clone()
		predicted_hashes: manifest.predicted_hashes.clone()
	}
}

fn sync_manifest_from_dto(dto SyncManifestDto) storage.SyncManifest {
	return storage.SyncManifest{
		offer:            sync_offer_from_dto(dto.offer)
		prediction_depth: dto.prediction_depth
		level_1_hashes:   dto.level_1_hashes.clone()
		predicted_hashes: dto.predicted_hashes.clone()
	}
}

fn sync_missing_set_to_dto(missing storage.SyncMissingSet) SyncMissingSetDto {
	return SyncMissingSetDto{
		missing_commit_cids: missing.missing_commit_cids.clone()
		missing_node_cids:   missing.missing_node_cids.clone()
	}
}

fn sync_missing_set_from_dto(dto SyncMissingSetDto) storage.SyncMissingSet {
	return storage.SyncMissingSet{
		missing_commit_cids: dto.missing_commit_cids.clone()
		missing_node_cids:   dto.missing_node_cids.clone()
	}
}

fn sync_session_to_dto(session storage.SyncSession) SyncSessionDto {
	return SyncSessionDto{
		request_local_root_hash: session.request.local_root_hash
		request_branch_name:     session.request.branch_name
		expected_old_commit_cid: session.expected_old_commit_cid
		target_commit_cid:       session.target_commit_cid
	}
}

fn sync_session_from_dto(dto SyncSessionDto) storage.SyncSession {
	return storage.SyncSession{
		request: storage.SyncRequest{
			local_root_hash: dto.request_local_root_hash
			branch_name:     dto.request_branch_name
		}
		expected_old_commit_cid: dto.expected_old_commit_cid
		target_commit_cid:       dto.target_commit_cid
	}
}

fn sync_plan_to_dto(plan storage.SyncPlan) SyncPlanDto {
	return SyncPlanDto{
		request_local_root_hash: plan.request.local_root_hash
		request_branch_name:     plan.request.branch_name
		target_commit_cid:       plan.target_commit_cid
		target_root_cid:         plan.target_root_cid
		missing_commit_cids:     plan.missing_commit_cids.clone()
		missing_node_cids:       plan.missing_node_cids.clone()
	}
}

fn sync_plan_from_dto(dto SyncPlanDto) storage.SyncPlan {
	return storage.SyncPlan{
		request: storage.SyncRequest{
			local_root_hash: dto.request_local_root_hash
			branch_name:     dto.request_branch_name
		}
		target_commit_cid:   dto.target_commit_cid
		target_root_cid:     dto.target_root_cid
		missing_commit_cids: dto.missing_commit_cids.clone()
		missing_node_cids:   dto.missing_node_cids.clone()
	}
}

fn data_packet_to_dto(packet storage.DataPacket) DataPacketDto {
	return DataPacketDto{
		kind: match packet.kind {
			.node { 'node' }
			.commit { 'commit' }
		}
		cid:      packet.cid
		data_b64: base64.encode(packet.data)
	}
}

fn data_packet_from_dto(dto DataPacketDto) !storage.DataPacket {
	return storage.DataPacket{
		kind: match dto.kind {
			'node' { storage.SyncObjectKind.node }
			'commit' { storage.SyncObjectKind.commit }
			else { return error('invalid packet kind: ${dto.kind}') }
		}
		cid:  dto.cid
		data: base64.decode(dto.data_b64)
	}
}

fn sync_exchange_to_dto(exchange storage.SyncExchange) SyncExchangeDto {
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

fn sync_exchange_from_dto(dto SyncExchangeDto) !storage.SyncExchange {
	mut packets := []storage.DataPacket{cap: dto.packets.len}
	for packet in dto.packets {
		packets << data_packet_from_dto(packet)!
	}
	return storage.SyncExchange{
		session: sync_session_from_dto(dto.session)
		plan:    sync_plan_from_dto(dto.plan)
		packets: packets
	}
}

fn (client Client) endpoint(path string) string {
	return client.base_url.trim_right('/') + path
}

fn (client Client) auth_header() http.Header {
	mut header := http.new_header()
	if client.auth_token.len > 0 {
		header.add(.authorization, 'Bearer ${client.auth_token}')
	}
	return header
}

fn (client Client) get(path string) !http.Response {
	response := http.fetch(http.FetchConfig{
		url:    client.endpoint(path)
		method: .get
		header: client.auth_header()
	})!
	if response.status_code >= 400 {
		return error('pollylink GET ${path} failed: ${response.status_code} ${response.body}')
	}
	return response
}

fn (client Client) post_json(path string, body string) !http.Response {
	mut header := client.auth_header()
	header.add(.content_type, 'application/json')
	response := http.fetch(http.FetchConfig{
		url:    client.endpoint(path)
		method: .post
		header: header
		data:   body
	})!
	if response.status_code >= 400 {
		return error('pollylink POST ${path} failed: ${response.status_code} ${response.body}')
	}
	return response
}

fn (client Client) post_json_raw(path string, body string) !http.Response {
	mut header := client.auth_header()
	header.add(.content_type, 'application/json')
	return http.fetch(http.FetchConfig{
		url:    client.endpoint(path)
		method: .post
		header: header
		data:   body
	})!
}

pub fn (client Client) list_repositories() ![]string {
	response := client.get('/v1/repos')!
	return json.decode(RepoListResponse, response.body)!.repos
}

fn (client Client) offer_sync(branch_name string, target_branch string, prediction_depth int) !SyncOfferEnvelope {
	response := client.post_json('/v1/sync/offer', json.encode(SyncOfferRequestBody{
		repo_name:        client.repo_name
		branch_name:      branch_name
		target_branch:    target_branch
		prediction_depth: prediction_depth
	}))!
	payload := json.decode(SyncOfferEnvelopeDto, response.body)!
	return SyncOfferEnvelope{
		offer:    sync_offer_from_dto(payload.offer)
		manifest: sync_manifest_from_dto(payload.manifest)
	}
}

fn (client Client) negotiate_missing_sync(offer storage.SyncOffer, manifest storage.SyncManifest, use_manifest bool) !storage.SyncMissingSet {
	response := client.post_json('/v1/sync/missing', json.encode(SyncNegotiateRequestBody{
		repo_name:    client.repo_name
		offer:        sync_offer_to_dto(offer)
		manifest:     sync_manifest_to_dto(manifest)
		use_manifest: use_manifest
	}))!
	payload := json.decode(SyncMissingSetDto, response.body)!
	return sync_missing_set_from_dto(payload)
}

fn (client Client) fetch_exchange_sync(offer storage.SyncOffer, missing storage.SyncMissingSet) !storage.SyncExchange {
	response := client.post_json('/v1/sync/exchange', json.encode(SyncExchangeRequestBody{
		repo_name: client.repo_name
		offer:     sync_offer_to_dto(offer)
		missing:   sync_missing_set_to_dto(missing)
	}))!
	payload := json.decode(SyncExchangeDto, response.body)!
	return sync_exchange_from_dto(payload)
}

fn (client Client) fetch_full_exchange_sync(offer storage.SyncOffer) !storage.SyncExchange {
	response := client.post_json('/v1/sync/exchange-full', json.encode(SyncFullExchangeRequestBody{
		repo_name: client.repo_name
		offer:     sync_offer_to_dto(offer)
	}))!
	payload := json.decode(SyncExchangeDto, response.body)!
	return sync_exchange_from_dto(payload)
}

fn (client Client) apply_exchange_sync(exchange storage.SyncExchange) !Branch {
	response := client.post_json('/v1/sync/apply', json.encode(SyncApplyRequestBody{
		repo_name: client.repo_name
		exchange:  sync_exchange_to_dto(exchange)
	}))!
	return json.decode(Branch, response.body)!
}

fn (client Client) try_apply_exchange_sync(exchange storage.SyncExchange) !ApplyExchangeResult {
	response := client.post_json_raw('/v1/sync/apply', json.encode(SyncApplyRequestBody{
		repo_name: client.repo_name
		exchange:  sync_exchange_to_dto(exchange)
	}))!
	if response.status_code >= 400 {
		payload := json.decode(SyncErrorDto, response.body) or {
			return ApplyExchangeResult{
				error_msg: response.body
			}
		}
		return ApplyExchangeResult{
			error_msg: payload.error
		}
	}
	return ApplyExchangeResult{
		ok:     true
		branch: json.decode(Branch, response.body)!
	}
}

pub fn (client Client) list_repository_summaries(limit int) ![]RepositoryInfo {
	response := client.get('/v1/repos/summaries?limit=${limit}')!
	return json.decode(RepoSummaryListResponse, response.body)!.repos
}

pub fn (client Client) repository_info() !RepositoryInfo {
	path := if client.repo_name.len == 0 {
		'/v1/repo-info'
	} else {
		'/v1/repo-info?repo=${client.repo_name}'
	}
	response := client.get(path)!
	return json.decode(RepoInfoQueryResponse, response.body)!.repo
}

pub fn (client Client) governance_status() !GovernanceStatus {
	response := client.get('/v1/governance-status')!
	return json.decode(GovernanceStatus, response.body)!
}

pub fn init_governance(root_dir string, actor string, token string) ! {
	pollyhub.init_governance(root_dir, actor, token)!
}

pub fn grant_repo_access(root_dir string, repo_name string, actor string, role RepoRole) ! {
	pollyhub.grant_repo_access(root_dir, repo_name, actor, match role {
		.reader { pollyhub.RepoRole.reader }
		.writer { pollyhub.RepoRole.writer }
		.admin { pollyhub.RepoRole.admin }
	})!
}

pub fn set_repo_policy(root_dir string, repo_name string, allow_push_to_default bool, require_auto_merge bool, default_sync_policy string) ! {
	pollyhub.set_repo_policy(root_dir, repo_name, allow_push_to_default, require_auto_merge,
		default_sync_policy)!
}

pub fn set_branch_policy(root_dir string, repo_name string, branch_name string, allow_push bool, require_auto_merge bool, default_sync_policy string) ! {
	pollyhub.set_branch_policy(root_dir, repo_name, branch_name, allow_push, require_auto_merge,
		default_sync_policy)!
}

pub fn set_rate_limit_policy(root_dir string, requests_per_minute int) ! {
	pollyhub.set_rate_limit_policy(root_dir, requests_per_minute)!
}

pub fn read_audit_entries(root_dir string, limit int) ![]AuditEntry {
	entries := pollyhub.read_audit_entries(root_dir, limit)!
	mut out := []AuditEntry{cap: entries.len}
	for entry in entries {
		out << audit_entry_from_pollyhub(entry)
	}
	return out
}

pub fn (client Client) list_branches() ![]Branch {
	path := if client.repo_name.len == 0 {
		'/v1/branches'
	} else {
		'/v1/branches?repo=${client.repo_name}'
	}
	response := client.get(path)!
	return json.decode(BranchListResponse, response.body)!.branches
}

pub fn (client Client) branch_status(branch_name string) !BranchStatus {
	path := if client.repo_name.len == 0 {
		'/v1/branch-status?branch=${branch_name}'
	} else {
		'/v1/branch-status?repo=${client.repo_name}&branch=${branch_name}'
	}
	response := client.get(path)!
	return json.decode(BranchStatus, response.body)!
}

pub fn (client Client) branch_statuses() ![]BranchStatus {
	path := if client.repo_name.len == 0 {
		'/v1/branch-statuses'
	} else {
		'/v1/branch-statuses?repo=${client.repo_name}'
	}
	response := client.get(path)!
	return json.decode(BranchStatusListResponse, response.body)!.branches
}

pub fn (client Client) open_repository(default_branch string) !RepositoryInfo {
	response := client.post_json('/v1/repos/open', json.encode(OpenRepoRequestBody{
		repo_name:      client.repo_name
		default_branch: default_branch
	}))!
	return json.decode(RepositoryInfo, response.body)!
}

pub fn (client Client) repo_activity(limit int) ![]RepoActivityEntry {
	path := if client.repo_name.len == 0 {
		'/v1/repo-activity?limit=${limit}'
	} else {
		'/v1/repo-activity?repo=${client.repo_name}&limit=${limit}'
	}
	response := client.get(path)!
	return json.decode(RepoActivityResponse, response.body)!.entries
}

pub fn (client Client) global_activity(limit int) ![]RepoActivityEntry {
	response := client.get('/v1/global-activity?limit=${limit}')!
	return json.decode(RepoActivityResponse, response.body)!.entries
}

pub fn (client Client) branch_activity(branch_name string) !BranchActivity {
	path := if client.repo_name.len == 0 {
		'/v1/branch-activity?branch=${branch_name}'
	} else {
		'/v1/branch-activity?repo=${client.repo_name}&branch=${branch_name}'
	}
	response := client.get(path)!
	return json.decode(BranchActivity, response.body)!
}

pub fn (client Client) branch_log(branch_name string, limit int) ![]BranchLogEntry {
	path := if client.repo_name.len == 0 {
		'/v1/branch-log?branch=${branch_name}&limit=${limit}'
	} else {
		'/v1/branch-log?repo=${client.repo_name}&branch=${branch_name}&limit=${limit}'
	}
	response := client.get(path)!
	return json.decode(BranchLogResponse, response.body)!.commits
}

pub fn (client Client) projector_value(branch_name string, projector_name string) !ProjectorValue {
	path := if client.repo_name.len == 0 {
		'/v1/projector-value?branch=${branch_name}&name=${projector_name}'
	} else {
		'/v1/projector-value?repo=${client.repo_name}&branch=${branch_name}&name=${projector_name}'
	}
	response := client.get(path)!
	return json.decode(ProjectorValue, response.body)!
}

pub fn (client Client) markdown_metric(branch_name string, table_name string, column_name string, selector string) !MarkdownMetric {
	path := if client.repo_name.len == 0 {
		'/v1/markdown-metric?branch=${branch_name}&table=${table_name}&column=${column_name}&selector=${selector}'
	} else {
		'/v1/markdown-metric?repo=${client.repo_name}&branch=${branch_name}&table=${table_name}&column=${column_name}&selector=${selector}'
	}
	response := client.get(path)!
	return json.decode(MarkdownMetric, response.body)!
}

pub fn (client Client) table_spec(branch_name string, table_name string) !TableSpec {
	path := if client.repo_name.len == 0 {
		'/v1/table-spec?branch=${branch_name}&table=${table_name}'
	} else {
		'/v1/table-spec?repo=${client.repo_name}&branch=${branch_name}&table=${table_name}'
	}
	response := client.get(path)!
	return json.decode(TableSpec, response.body)!
}

pub fn (client Client) query_schema(branch_name string, table_name string) !QuerySchema {
	path := if client.repo_name.len == 0 {
		'/v1/query-schema?branch=${branch_name}&table=${table_name}'
	} else {
		'/v1/query-schema?repo=${client.repo_name}&branch=${branch_name}&table=${table_name}'
	}
	response := client.get(path)!
	return json.decode(QuerySchema, response.body)!
}

pub fn (client Client) query_plan_preview(query QueryRowsPostRequest) !QueryPlanPreview {
	response := client.post_json('/v1/query-plan-preview', json.encode(QueryRowsPostRequestBody{
		repo_name:          client.repo_name
		branch_name:        query.branch_name
		table_name:         query.table_name
		filters:            query.filters.clone()
		general_fts:        query.general_fts
		select_columns:     query.select_columns.clone()
		start_primary_key:  query.start_primary_key
		start_index_value:  query.start_index_value
		continuation_token: query.continuation_token
		limit:              query.limit
	}))!
	return json.decode(QueryPlanPreview, response.body)!
}

pub fn (client Client) index_lookup(branch_name string, table_name string, index_name string, value string, limit int) !IndexLookup {
	path := if client.repo_name.len == 0 {
		'/v1/index-lookup?branch=${branch_name}&table=${table_name}&index=${index_name}&value=${value}&limit=${limit}'
	} else {
		'/v1/index-lookup?repo=${client.repo_name}&branch=${branch_name}&table=${table_name}&index=${index_name}&value=${value}&limit=${limit}'
	}
	response := client.get(path)!
	return json.decode(IndexLookup, response.body)!
}

pub fn (client Client) index_lookup_prefix(branch_name string, table_name string, index_name string, value string, limit int) !IndexLookup {
	path := if client.repo_name.len == 0 {
		'/v1/index-lookup-prefix?branch=${branch_name}&table=${table_name}&index=${index_name}&value=${value}&limit=${limit}'
	} else {
		'/v1/index-lookup-prefix?repo=${client.repo_name}&branch=${branch_name}&table=${table_name}&index=${index_name}&value=${value}&limit=${limit}'
	}
	response := client.get(path)!
	return json.decode(IndexLookup, response.body)!
}

pub fn (client Client) markdown_query(query MarkdownQueryRequest) !MarkdownQuery {
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
	return json.decode(MarkdownQuery, response.body)!
}

pub fn (client Client) query_rows(query QueryRowsRequest) !QueryRows {
	return client.query_page(query)!.rows_and_meta(query)
}

pub fn (client Client) query_page(query QueryRowsRequest) !QueryPage {
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
		path += '&select=${query.select_columns.join(",")}'
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
	return json.decode(QueryPage, response.body)!
}

pub fn (client Client) query_rows_post(query QueryRowsPostRequest) !QueryRows {
	return client.query_page_post(query)!.rows_and_meta_post(query)
}

pub fn (client Client) query_page_post(query QueryRowsPostRequest) !QueryPage {
	response := client.post_json('/v1/query-rows', json.encode(QueryRowsPostRequestBody{
		repo_name:          client.repo_name
		branch_name:        query.branch_name
		table_name:         query.table_name
		filters:            query.filters.clone()
		general_fts:        query.general_fts
		select_columns:     query.select_columns.clone()
		start_primary_key:  query.start_primary_key
		start_index_value:  query.start_index_value
		continuation_token: query.continuation_token
		limit:              query.limit
	}))!
	return json.decode(QueryPage, response.body)!
}

pub fn (client Client) query_fts_preview(query FtsQueryRequest) !FtsQueryPreview {
	response := client.post_json('/v1/query-fts-preview', json.encode(FtsQueryRequestBody{
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
	return json.decode(FtsQueryPreview, response.body)!
}

pub fn (client Client) query_fts(query FtsQueryRequest) !FtsQueryResult {
	response := client.post_json('/v1/query-fts', json.encode(FtsQueryRequestBody{
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
	return json.decode(FtsQueryResult, response.body)!
}

pub fn (client Client) general_query_fts_preview(query GeneralFtsQueryRequest) !GeneralFtsQueryPreview {
	response := client.post_json('/v1/general-query-fts-preview', json.encode(GeneralFtsQueryRequestBody{
		repo_name:      client.repo_name
		branch_name:    query.branch_name
		table_name:     query.table_name
		index_name:     query.index_name
		query_kind:     query.query_kind
		terms:          query.terms.clone()
		select_columns: query.select_columns.clone()
		limit:          query.limit
	}))!
	return json.decode(GeneralFtsQueryPreview, response.body)!
}

pub fn (client Client) general_query_fts(query GeneralFtsQueryRequest) !GeneralFtsQueryResult {
	response := client.post_json('/v1/general-query-fts', json.encode(GeneralFtsQueryRequestBody{
		repo_name:      client.repo_name
		branch_name:    query.branch_name
		table_name:     query.table_name
		index_name:     query.index_name
		query_kind:     query.query_kind
		terms:          query.terms.clone()
		select_columns: query.select_columns.clone()
		limit:          query.limit
	}))!
	return json.decode(GeneralFtsQueryResult, response.body)!
}

fn fetch_remote_branch_into_repo(mut repo LocalRepo, client Client, branch_name string) !storage.SyncOffer {
	envelope := client.offer_sync(branch_name, branch_name, 0)!
	exchange := client.fetch_full_exchange_sync(envelope.offer)!
	storage.import_sync_exchange_objects(mut repo.repo, exchange)!
	return envelope.offer
}

fn build_auto_merge_sidecar_exchange(mut source_repo LocalRepo, source_branch string, client Client, target_branch string) !storage.SyncExchange {
	remote_offer := fetch_remote_branch_into_repo(mut source_repo, client, target_branch)!
	merged_offer := storage.build_auto_merge_offer_for_remote_offer(mut source_repo.repo, source_branch, target_branch, remote_offer)!
	return storage.full_sync_exchange_for_offer(mut source_repo.repo, merged_offer)
}

pub fn push_branch_to_sidecar(mut source_repo LocalRepo, source_branch string, client Client, target_branch string, policy SyncPolicy) !SyncPushResult {
	prediction_depth := match policy {
		.manifest_depth1, .auto { 1 }
		.manifest_depth2 { 2 }
		.regular { 0 }
	}
	envelope := client.offer_sync(source_branch, target_branch, prediction_depth)!
	use_manifest := prediction_depth > 0
	missing := client.negotiate_missing_sync(envelope.offer, envelope.manifest, use_manifest)!
	exchange := storage.sync_exchange_for_missing(mut source_repo.repo, envelope.offer, missing)!
	first_apply := client.try_apply_exchange_sync(exchange)!
	if first_apply.ok {
		return SyncPushResult{
			branch:       first_apply.branch
			packet_count: exchange.packets.len
			packet_bytes: sync_packet_bytes_storage(exchange.packets)
		}
	}
	err_msg := first_apply.error_msg
	if !is_branch_head_changed_error(err_msg) {
		return error(err_msg)
	}
	merged_exchange := build_auto_merge_sidecar_exchange(mut source_repo, source_branch, client, target_branch)!
	merged_branch := client.apply_exchange_sync(merged_exchange)!
	return SyncPushResult{
		branch:       merged_branch
		packet_count: merged_exchange.packets.len
		packet_bytes: sync_packet_bytes_storage(merged_exchange.packets)
		auto_merged:  true
	}
}

pub fn pull_branch_from_sidecar(mut target_repo LocalRepo, target_branch string, client Client, source_branch string, policy SyncPolicy) !SyncPullResult {
	prediction_depth := match policy {
		.manifest_depth1, .auto { 1 }
		.manifest_depth2 { 2 }
		.regular { 0 }
	}
	envelope := client.offer_sync(source_branch, target_branch, prediction_depth)!
	missing := if prediction_depth > 0 {
		storage.sync_missing_for_manifest(mut target_repo.repo, envelope.manifest)!
	} else {
		storage.sync_missing_for_offer(mut target_repo.repo, envelope.offer)!
	}
	exchange := client.fetch_exchange_sync(envelope.offer, missing)!
	branch := storage.apply_exchange_to_repo(mut target_repo.repo, exchange)!
	return SyncPullResult{
		branch:       Branch{
			name:       branch.name
			commit_cid: branch.commit_cid
		}
		packet_count: exchange.packets.len
		packet_bytes: sync_packet_bytes_storage(exchange.packets)
	}
}
