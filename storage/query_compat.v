module storage

import core
import encoding.base64
import json
import time

enum QueryFilterOp {
	eq
	prefix
	after
	before
	between
}

struct QueryFilter {
pub:
	column_name      string
	plugin_name      string
	selector         string
	op               QueryFilterOp
	value            ColumnValue
	second_value     ColumnValue = NullValue{}
	has_second_value bool
}

enum QueryOrderDirection {
	asc
	desc
}

pub enum FtsQueryKind {
	term
	prefix
	all
	any
}

pub enum FtsScope {
	any
	heading
	paragraph
	code_block
	list_item
}

struct FtsQuery {
	table_name     string
	column_name    string
	scope          FtsScope = .any
	kind           FtsQueryKind
	terms          []string
	select_columns []string
	limit          int
}

fn fts_scope_name(scope FtsScope) string {
	return match scope {
		.any { 'any' }
		.heading { 'heading' }
		.paragraph { 'paragraph' }
		.code_block { 'code_block' }
		.list_item { 'list_item' }
	}
}

fn fts_query_kind_name(kind FtsQueryKind) string {
	return match kind {
		.term { 'term' }
		.prefix { 'prefix' }
		.all { 'all' }
		.any { 'any' }
	}
}

fn fts_normalize_term(raw string) string {
	return raw.to_lower().trim_space()
}

fn fts_normalize_terms(raw_terms []string) []string {
	mut out := []string{}
	for raw in raw_terms {
		normalized := fts_normalize_term(raw)
		if normalized.len == 0 {
			continue
		}
		out << normalized
	}
	return out
}

fn validate_fts_query(query FtsQuery) ! {
	if query.table_name.len == 0 {
		return error('fts query requires table_name')
	}
	if query.column_name.len == 0 {
		return error('fts query requires column_name')
	}
	if query.terms.len == 0 {
		return error('fts query requires at least one term')
	}
	normalized := fts_normalize_terms(query.terms)
	if normalized.len == 0 {
		return error('fts query terms cannot all be empty')
	}
	match query.kind {
		.term, .prefix {
			if normalized.len != 1 {
				return error('fts ${fts_query_kind_name(query.kind)} query requires exactly one term')
			}
		}
		.all, .any {}
	}
}

struct QueryOrder {
pub:
	column_name string
	direction   QueryOrderDirection = .asc
}

struct QueryRequest {
pub:
	table_name            string
	filters               []QueryFilter
	general_fts           QueryGeneralFtsClause
	order_by              QueryOrder
	select_columns        []string
	start_primary_key     []u8
	start_index_value     ColumnValue = NullValue{}
	has_start_index_value bool
	continuation_token    string
	limit                 int
}

struct QueryGeneralFtsClause {
pub:
	index_name string
	kind       FtsQueryKind
	terms      []string
}

struct QueryPlan {
pub:
	table_name        string
	strategy          string
	index_name        string
	index_filter      QueryFilter
	order_by          QueryOrder
	post_filters      []QueryFilter
	post_filter_count int
	limit             int
}

struct QueryPlanPreview {
pub:
	plan                        QueryPlan
	warnings                    []string
	notes                       []string
	default_result_shape        string
	supports_continuation_token bool
}

fn (preview QueryPlanPreview) sample_explain() QuerySamplePlanExplain {
	flags := core.query_plan_explain_flags(preview.plan.index_name, preview.plan.strategy,
		preview.supports_continuation_token)
	return QuerySamplePlanExplain{
		strategy:                    preview.plan.strategy
		index_name:                  preview.plan.index_name
		warnings:                    preview.warnings.clone()
		notes:                       preview.notes.clone()
		default_result_shape:        preview.default_result_shape
		supports_continuation_token: flags.supports_continuation
		supports_reverse_scan:       flags.supports_reverse
		supports_top_n:              flags.supports_top_n
	}
}

struct QueryCursorState {
pub:
	has_more                bool
	next_primary_key        []u8
	next_index_value        ColumnValue = NullValue{}
	next_continuation_token string
}

struct QueryCursorPage {
pub:
	rows             []TypedSchemaRow
	plan             QueryPlan
	cursor           QueryCursorState
	general_fts_hits []GeneralFtsHit
}

struct QueryExecutionTimings {
pub:
	plan_ms                  i64
	normalize_ms             i64
	fetch_ms                 i64
	fetch_begin_tx_ms        i64
	fetch_begin_checkout_ms  i64
	fetch_begin_tree_load_ms i64
	fetch_begin_wrap_ms      i64
	fetch_view_ms            i64
	fetch_scan_ms            i64
	fetch_scan_nodes         int
	fetch_scan_leaves        int
	fetch_scan_items         int
	filter_ms                i64
	project_ms               i64
	continuation_ms          i64
	total_ms                 i64
	fetched_rows             int
	filtered_rows            int
	returned_rows            int
}

struct ProfiledQueryCursorPage {
pub:
	page    QueryCursorPage
	timings QueryExecutionTimings
}

// QueryResult is the compatibility query envelope that duplicates cursor fields
// at the top level. Prefer QueryCursorPage for new paged-read call sites.
struct QueryResult {
pub:
	rows                    []TypedSchemaRow
	plan                    QueryPlan
	cursor                  QueryCursorState
	general_fts_hits        []GeneralFtsHit
	has_more                bool
	next_primary_key        []u8
	next_index_value        ColumnValue = NullValue{}
	next_continuation_token string
}

fn QueryFilter.eq(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op:          .eq
		value:       clone_column_value(value)
	}
}

fn QueryFilter.prefix(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op:          .prefix
		value:       clone_column_value(value)
	}
}

fn QueryFilter.field_eq(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .eq
		value:       clone_column_value(value)
	}
}

fn QueryFilter.field_prefix(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .prefix
		value:       clone_column_value(value)
	}
}

fn QueryFilter.after(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op:          .after
		value:       clone_column_value(value)
	}
}

fn QueryFilter.before(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op:          .before
		value:       clone_column_value(value)
	}
}

fn QueryFilter.between(column_name string, start_value ColumnValue, end_value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name:      column_name
		op:               .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_second_value: true
	}
}

fn QueryFilter.field_after(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .after
		value:       clone_column_value(value)
	}
}

fn QueryFilter.field_before(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .before
		value:       clone_column_value(value)
	}
}

fn QueryFilter.field_between(column_name string, plugin_name string, selector string, start_value ColumnValue, end_value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name:      column_name
		plugin_name:      plugin_name
		selector:         selector
		op:               .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_second_value: true
	}
}

fn (filter QueryFilter) is_field_selector() bool {
	return filter.plugin_name.len > 0 || filter.selector.len > 0
}

fn (result QueryResult) cursor_page() QueryCursorPage {
	return QueryCursorPage{
		rows:             result.rows.clone()
		plan:             result.plan
		cursor:           result.cursor
		general_fts_hits: result.general_fts_hits.clone()
	}
}

fn (result QueryResult) page() QueryCursorPage {
	return result.cursor_page()
}

fn (page QueryCursorPage) result() QueryResult {
	return QueryResult{
		rows:                    page.rows.clone()
		plan:                    page.plan
		cursor:                  page.cursor
		general_fts_hits:        page.general_fts_hits.clone()
		has_more:                page.cursor.has_more
		next_primary_key:        page.cursor.next_primary_key
		next_index_value:        page.cursor.next_index_value
		next_continuation_token: page.cursor.next_continuation_token
	}
}

fn (plan GeneralFtsQueryPlan) as_query_plan() QueryPlan {
	return QueryPlan{
		table_name: plan.table_name
		strategy:   plan.strategy
		index_name: plan.index_name
		limit:      plan.limit
	}
}

fn query_general_fts_query_from_request(request QueryRequest) GeneralFtsQuery {
	return GeneralFtsQuery{
		table_name:     request.table_name
		index_name:     request.general_fts.index_name
		kind:           request.general_fts.kind
		terms:          request.general_fts.terms.clone()
		select_columns: request.select_columns.clone()
		limit:          request.limit
	}
}

fn (database PersistentDatabase) preview_query_plan(request QueryRequest) !QueryPlan {
	if request.general_fts.index_name.len > 0 {
		plan := database.preview_general_fts_query(query_general_fts_query_from_request(request))!
		return plan.as_query_plan()
	}
	spec := database.table_spec(request.table_name)!
	return plan_query_request(spec, request)
}

// Compatibility entrypoint. Prefer `query.preview_plan_details(...)` for new in-process callers.
fn (database PersistentDatabase) preview_query_plan_details(request QueryRequest) !QueryPlanPreview {
	if request.general_fts.index_name.len > 0 {
		plan := database.preview_general_fts_query(query_general_fts_query_from_request(request))!
		return QueryPlanPreview{
			plan:                        plan.as_query_plan()
			warnings:                    []string{}
			notes:                       [
				'Query will execute against the SQLite FTS5 sidecar for index `${plan.index_name}`.',
			]
			default_result_shape:        'rows'
			supports_continuation_token: false
		}
	}
	spec := database.table_spec(request.table_name)!
	plan := plan_query_request(spec, request)!
	return build_query_plan_preview(spec, database.projectors, request, plan, false)
}

// Compatibility entrypoint. Prefer `query.preview_plan_in_session(...)` for new in-process callers.
fn (session DatabaseSession) preview_query_plan(request QueryRequest) !QueryPlan {
	if request.general_fts.index_name.len > 0 {
		plan := session.preview_general_fts_query(query_general_fts_query_from_request(request))!
		return plan.as_query_plan()
	}
	spec := session.table_spec(request.table_name)!
	return plan_query_request(spec, request)
}

// Compatibility entrypoint. Prefer `query.query_rows(...)` only when legacy result shape is required.
fn (session DatabaseSession) query_rows(mut db PersistentDatabase, request QueryRequest) !QueryResult {
	return (session.query_page(mut db, request)!).result()
}

// Compatibility entrypoint. Prefer `query.query_page(...)` for new in-process callers.
// `query_rows(...)` remains as a compatibility wrapper around the cursor-page result.
fn (session DatabaseSession) query_page(mut db PersistentDatabase, request QueryRequest) !QueryCursorPage {
	return (session.query_page_profiled(mut db, request)!).page
}

// Compatibility entrypoint. Prefer `query.query_page_profiled(...)` for new in-process callers.
fn (session DatabaseSession) query_page_profiled(mut db PersistentDatabase, request QueryRequest) !ProfiledQueryCursorPage {
	mut total_sw := time.new_stopwatch()
	if request.general_fts.index_name.len > 0 {
		mut plan_sw := time.new_stopwatch()
		result := session.query_general_fts(mut db, query_general_fts_query_from_request(request))!
		plan_ms := plan_sw.elapsed().milliseconds()
		return profiled_query_page_from_general_fts(result, plan_ms,
			total_sw.elapsed().milliseconds())
	}
	spec := session.table_spec(request.table_name)!
	mut plan_sw := time.new_stopwatch()
	plan := plan_query_request(spec, request)!
	plan_ms := plan_sw.elapsed().milliseconds()
	mut normalize_sw := time.new_stopwatch()
	normalized := query_request_with_continuation_token(request, plan)!
	normalize_ms := normalize_sw.elapsed().milliseconds()
	mut fetch_sw := time.new_stopwatch()
	rows, begin_tx_ms, begin_checkout_ms, begin_tree_load_ms, begin_wrap_ms, view_ms, scan_ms, scan_nodes, scan_leaves, scan_items := execute_planned_query_fetch_profiled(session, mut
		db, spec, plan.strategy, plan.index_name, plan.index_filter.column_name,
		plan.index_filter.plugin_name, plan.index_filter.selector,
		query_filter_op_name(plan.index_filter.op), plan.index_filter.value,
		plan.index_filter.second_value, plan.index_filter.has_second_value,
		plan.order_by.column_name, plan.order_by.direction == .desc, plan.post_filter_count,
		plan.limit, normalized.select_columns, normalized.start_primary_key,
		normalized.start_index_value, normalized.has_start_index_value)!
	fetch_ms := fetch_sw.elapsed().milliseconds()
	return finalize_profiled_query_page(total_sw.elapsed().milliseconds(), db.root_dir, spec.table,
		plan, normalized, plan_ms, normalize_ms, fetch_ms, ProfiledQueryRows{
		rows:               rows.clone()
		begin_tx_ms:        begin_tx_ms
		begin_checkout_ms:  begin_checkout_ms
		begin_tree_load_ms: begin_tree_load_ms
		begin_wrap_ms:      begin_wrap_ms
		view_ms:            view_ms
		scan_ms:            scan_ms
		scan_nodes:         scan_nodes
		scan_leaves:        scan_leaves
		scan_items:         scan_items
	})
}

// Compatibility entrypoint. Prefer `query.preview_plan_in_transaction(...)` for new in-process callers.
fn (session TransactionSession) preview_query_plan(request QueryRequest) !QueryPlan {
	if request.general_fts.index_name.len > 0 {
		return error('general fts query requires database session')
	}
	spec := session.working_set.transaction().specs[request.table_name] or {
		return error('typed table not registered: ${request.table_name}')
	}
	return plan_query_request(spec, request)
}

// Compatibility entrypoint. Prefer `query.preview_plan_details_in_transaction(...)` for new in-process callers.
fn (session TransactionSession) preview_query_plan_details(request QueryRequest) !QueryPlanPreview {
	if request.general_fts.index_name.len > 0 {
		return error('general fts query requires database session')
	}
	spec := session.working_set.transaction().specs[request.table_name] or {
		return error('typed table not registered: ${request.table_name}')
	}
	plan := plan_query_request(spec, request)!
	return build_query_plan_preview(spec, map[string]AggregateProjectionDef{}, request, plan, true)
}

// Compatibility entrypoint. Prefer `query.query_rows_in_transaction(...)` only when legacy result shape is required.
fn (session TransactionSession) query_rows(request QueryRequest) !QueryResult {
	return (session.query_page(request)!).result()
}

// Compatibility entrypoint. Prefer `query.query_page_in_transaction(...)` for new in-process callers.
// `query_rows(...)` remains as a compatibility wrapper around the cursor-page result.
fn (session TransactionSession) query_page(request QueryRequest) !QueryCursorPage {
	return (session.query_page_profiled(request)!).page
}

// Compatibility entrypoint. Prefer `query.query_page_profiled_in_transaction(...)` for new in-process callers.
fn (session TransactionSession) query_page_profiled(request QueryRequest) !ProfiledQueryCursorPage {
	if request.general_fts.index_name.len > 0 {
		return error('general fts query requires database session')
	}
	mut total_sw := time.new_stopwatch()
	spec := session.working_set.transaction().specs[request.table_name] or {
		return error('typed table not registered: ${request.table_name}')
	}
	mut plan_sw := time.new_stopwatch()
	plan := plan_query_request(spec, request)!
	plan_ms := plan_sw.elapsed().milliseconds()
	mut normalize_sw := time.new_stopwatch()
	normalized := query_request_with_continuation_token(request, plan)!
	normalize_ms := normalize_sw.elapsed().milliseconds()
	mut fetch_sw := time.new_stopwatch()
	rows, begin_tx_ms, begin_checkout_ms, begin_tree_load_ms, begin_wrap_ms, view_ms, scan_ms, scan_nodes, scan_leaves, scan_items := execute_planned_query_fetch_profiled_in_transaction(session,
		spec, plan.strategy, plan.index_name, plan.index_filter.column_name,
		plan.index_filter.plugin_name, plan.index_filter.selector,
		query_filter_op_name(plan.index_filter.op), plan.index_filter.value,
		plan.index_filter.second_value, plan.index_filter.has_second_value,
		plan.order_by.column_name, plan.order_by.direction == .desc, plan.post_filter_count,
		plan.limit, normalized.select_columns, normalized.start_primary_key,
		normalized.start_index_value, normalized.has_start_index_value)!
	fetch_ms := fetch_sw.elapsed().milliseconds()
	return finalize_profiled_query_page(total_sw.elapsed().milliseconds(), session.root_dir,
		spec.table, plan, normalized, plan_ms, normalize_ms, fetch_ms, ProfiledQueryRows{
		rows:               rows.clone()
		begin_tx_ms:        begin_tx_ms
		begin_checkout_ms:  begin_checkout_ms
		begin_tree_load_ms: begin_tree_load_ms
		begin_wrap_ms:      begin_wrap_ms
		view_ms:            view_ms
		scan_ms:            scan_ms
		scan_nodes:         scan_nodes
		scan_leaves:        scan_leaves
		scan_items:         scan_items
	})
}

fn profiled_query_page_from_general_fts(result GeneralFtsQueryResult, plan_ms i64, total_ms i64) ProfiledQueryCursorPage {
	return ProfiledQueryCursorPage{
		page:    QueryCursorPage{
			rows:             result.rows.clone()
			plan:             result.plan.as_query_plan()
			cursor:           QueryCursorState{}
			general_fts_hits: result.hits.clone()
		}
		timings: QueryExecutionTimings{
			plan_ms:       plan_ms
			total_ms:      total_ms
			returned_rows: result.rows.len
		}
	}
}

fn finalize_profiled_query_page(total_ms i64, root_dir string, table TableDef, plan QueryPlan, request QueryRequest, plan_ms i64, normalize_ms i64, fetch_ms i64, profiled_rows ProfiledQueryRows) !ProfiledQueryCursorPage {
	mut rows := profiled_rows.rows.clone()
	fetched_rows := rows.len

	mut filter_sw := time.new_stopwatch()
	filtered := filter_query_rows(root_dir, table, rows, request.filters,
		request.start_primary_key, request.start_index_value, request.has_start_index_value,
		plan.index_filter, plan.order_by, request.limit)!
	filter_ms := filter_sw.elapsed().milliseconds()

	rows = filtered.rows.clone()
	filtered_rows := rows.len

	mut project_sw := time.new_stopwatch()
	rows = project_query_rows(rows, request.select_columns)!
	project_ms := project_sw.elapsed().milliseconds()

	mut continuation_sw := time.new_stopwatch()
	cursor := QueryCursorState{
		has_more:                filtered.has_more
		next_primary_key:        filtered.next_primary_key
		next_index_value:        filtered.next_index_value
		next_continuation_token: encode_query_continuation_token_for_plan(plan,
			filtered.next_primary_key, filtered.next_index_value)
	}
	continuation_ms := continuation_sw.elapsed().milliseconds()

	return ProfiledQueryCursorPage{
		page:    QueryCursorPage{
			rows:   rows.clone()
			plan:   plan
			cursor: cursor
		}
		timings: QueryExecutionTimings{
			plan_ms:                  plan_ms
			normalize_ms:             normalize_ms
			fetch_ms:                 fetch_ms
			fetch_begin_tx_ms:        profiled_rows.begin_tx_ms
			fetch_begin_checkout_ms:  profiled_rows.begin_checkout_ms
			fetch_begin_tree_load_ms: profiled_rows.begin_tree_load_ms
			fetch_begin_wrap_ms:      profiled_rows.begin_wrap_ms
			fetch_view_ms:            profiled_rows.view_ms
			fetch_scan_ms:            profiled_rows.scan_ms
			fetch_scan_nodes:         profiled_rows.scan_nodes
			fetch_scan_leaves:        profiled_rows.scan_leaves
			fetch_scan_items:         profiled_rows.scan_items
			filter_ms:                filter_ms
			project_ms:               project_ms
			continuation_ms:          continuation_ms
			total_ms:                 total_ms
			fetched_rows:             fetched_rows
			filtered_rows:            filtered_rows
			returned_rows:            rows.len
		}
	}
}

fn build_query_plan_preview(spec TypedTableSpec, projectors map[string]AggregateProjectionDef, request QueryRequest, plan QueryPlan, transaction_local bool) QueryPlanPreview {
	_ = transaction_local
	mut warnings := query_plan_preview_warnings(spec, projectors, request, plan)
	mut notes := query_plan_preview_notes(spec, request, plan)
	return QueryPlanPreview{
		plan:                        plan
		warnings:                    warnings
		notes:                       notes
		default_result_shape:        'page'
		supports_continuation_token: true
	}
}

fn query_plan_preview_warnings(spec TypedTableSpec, projectors map[string]AggregateProjectionDef, request QueryRequest, plan QueryPlan) []string {
	mut warnings := core.query_plan_preview_warnings(plan.strategy == 'table_scan')
	for filter in request.filters {
		warning := query_field_selector_planning_warning(spec, projectors, request.table_name,
			filter) or { continue }
		warnings << warning
	}
	return warnings
}

fn query_plan_preview_notes(spec TypedTableSpec, request QueryRequest, plan QueryPlan) []string {
	return core.query_plan_preview_notes(plan.post_filter_count,
		query_plan_uses_projection_pushdown(plan), query_plan_requires_base_row_fetch(spec,
		request, plan), query_plan_supports_reverse_executor(plan),
		query_plan_supports_top_n_executor(plan), plan.order_by.column_name.len > 0)
}

fn query_plan_uses_projection_pushdown(plan QueryPlan) bool {
	return core.query_plan_uses_projection_pushdown(plan.strategy)
}

fn query_plan_supports_reverse_executor(plan QueryPlan) bool {
	return core.query_plan_supports_reverse_scan(plan.index_name, plan.strategy)
}

fn query_plan_supports_top_n_executor(plan QueryPlan) bool {
	return core.query_plan_supports_top_n(plan.index_name, plan.strategy)
}

fn query_plan_requires_base_row_fetch(spec TypedTableSpec, request QueryRequest, plan QueryPlan) bool {
	if plan.index_name.len == 0 || request.select_columns.len == 0 {
		return false
	}
	index := query_index_by_name(spec, plan.index_name) or { return false }
	return core.query_requires_base_row_fetch(true, request.select_columns.len, query_index_covers_selection(index,
		request.select_columns))
}

fn query_field_selector_planning_warning(spec TypedTableSpec, projectors map[string]AggregateProjectionDef, table_name string, filter QueryFilter) ?string {
	if !filter.is_field_selector() || best_index_for_filter(spec, filter) != none {
		return none
	}
	field_ref := '${filter.column_name}.${filter.plugin_name}:${filter.selector}'
	return core.query_field_selector_planning_warning(field_ref, query_filter_has_projection_metric(projectors,
		table_name, filter))
}

fn query_filter_has_projection_metric(projectors map[string]AggregateProjectionDef, table_name string, filter QueryFilter) bool {
	for _, projector in projectors {
		if projector.table_name != table_name || projector.column_name != filter.column_name {
			continue
		}
		meta := projector.field_projection_meta() or { continue }
		if meta.plugin_name == filter.plugin_name && meta.selector == filter.selector {
			return true
		}
	}
	return false
}

struct QueryContinuationDto {
	table_name        string
	column_name       string
	plugin_name       string
	selector          string
	query_kind        string
	order_by_column   string
	order_desc        bool
	start_primary_key string
	start_index_value string
}

fn encode_query_continuation_token(table_name string, index_filter QueryFilter, next_primary_key []u8, next_index_value ColumnValue) string {
	if next_primary_key.len == 0 {
		return ''
	}
	payload := json.encode(QueryContinuationDto{
		table_name:        table_name
		column_name:       index_filter.column_name
		plugin_name:       index_filter.plugin_name
		selector:          index_filter.selector
		query_kind:        query_filter_op_name(index_filter.op)
		start_primary_key: next_primary_key.bytestr()
		start_index_value: if next_index_value is NullValue {
			''
		} else {
			query_cursor_render_value(next_index_value)
		}
	})
	return base64.encode_str(payload)
}

fn encode_query_continuation_token_for_plan(plan QueryPlan, next_primary_key []u8, next_index_value ColumnValue) string {
	if next_primary_key.len == 0 {
		return ''
	}
	payload := json.encode(QueryContinuationDto{
		table_name:        plan.table_name
		column_name:       plan.index_filter.column_name
		plugin_name:       plan.index_filter.plugin_name
		selector:          plan.index_filter.selector
		query_kind:        query_plan_continuation_kind(plan)
		order_by_column:   plan.order_by.column_name
		order_desc:        plan.order_by.direction == .desc
		start_primary_key: next_primary_key.bytestr()
		start_index_value: if next_index_value is NullValue {
			''
		} else {
			query_cursor_render_value(next_index_value)
		}
	})
	return base64.encode_str(payload)
}

fn query_request_with_continuation_token(request QueryRequest, plan QueryPlan) !QueryRequest {
	if request.continuation_token.len == 0 {
		return request
	}
	token := decode_query_continuation_token(request.continuation_token)!
	validate_query_continuation_token_for_plan(token, plan)!
	anchor_filter := query_plan_anchor_filter(plan)
	start_index_value := if anchor_filter.column_name.len > 0 && token.start_index_value.len > 0 {
		decode_query_cursor_value(token.start_index_value, anchor_filter)!
	} else {
		NullValue{}
	}
	return QueryRequest{
		...request
		start_primary_key:     token.start_primary_key.bytes()
		start_index_value:     start_index_value
		has_start_index_value: token.start_index_value.len > 0
	}
}

fn decode_query_continuation_token(raw string) !QueryContinuationDto {
	if raw.len == 0 {
		return error('empty continuation token')
	}
	return json.decode(QueryContinuationDto, base64.decode_str(raw))
}

fn validate_query_continuation_token(token QueryContinuationDto, table_name string, index_filter QueryFilter) ! {
	if token.table_name != table_name || token.column_name != index_filter.column_name
		|| token.plugin_name != index_filter.plugin_name || token.selector != index_filter.selector
		|| token.query_kind != query_filter_op_name(index_filter.op) {
		return error('continuation token does not match query shape')
	}
}

fn validate_query_continuation_token_for_plan(token QueryContinuationDto, plan QueryPlan) ! {
	expected_kind := query_plan_continuation_kind(plan)
	if token.table_name != plan.table_name || token.query_kind != expected_kind {
		return error('continuation token does not match query shape')
	}
	if plan.index_filter.column_name.len > 0 {
		if token.column_name != plan.index_filter.column_name
			|| token.plugin_name != plan.index_filter.plugin_name
			|| token.selector != plan.index_filter.selector {
			return error('continuation token does not match indexed filter')
		}
		return
	}
	if token.order_by_column != plan.order_by.column_name
		|| token.order_desc != (plan.order_by.direction == .desc) {
		return error('continuation token does not match ordered query')
	}
}

fn query_plan_continuation_kind(plan QueryPlan) string {
	if plan.index_filter.column_name.len > 0 {
		return query_filter_op_name(plan.index_filter.op)
	}
	return if plan.order_by.direction == .desc { 'order_desc' } else { 'order_asc' }
}

fn query_plan_anchor_filter(plan QueryPlan) QueryFilter {
	if plan.index_filter.column_name.len > 0 {
		return plan.index_filter
	}
	if plan.order_by.column_name.len > 0 {
		return QueryFilter{
			column_name: plan.order_by.column_name
			op:          .eq
			value:       ''
		}
	}
	return QueryFilter{}
}

fn decode_query_cursor_value(raw string, filter QueryFilter) !ColumnValue {
	if raw.len == 0 {
		return NullValue{}
	}
	value_type := query_value_type(filter.value)!
	return match value_type {
		.bool_ {
			if raw == 'true' {
				ColumnValue(true)
			} else if raw == 'false' {
				ColumnValue(false)
			} else {
				return error('invalid bool cursor value: ${raw}')
			}
		}
		.i64_ {
			ColumnValue(raw.i64())
		}
		.bytes_ {
			if !raw.starts_with('hex:') {
				return error('invalid bytes cursor value: ${raw}')
			}
			ColumnValue(raw.all_after('hex:').bytes())
		}
		.string_, .enum_, .json_, .datetime_ {
			ColumnValue(raw)
		}
		.markdown_ {
			return error('markdown cursor values are not supported')
		}
	}
}

fn query_cursor_render_value(value ColumnValue) string {
	return match value {
		MarkdownRef {
			'markdown:${value.doc_root_id}'
		}
		NullValue {
			''
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

fn execute_planned_query_fetch_profiled(session DatabaseSession, mut db PersistentDatabase, spec TypedTableSpec, strategy string, index_name string, index_filter_column_name string, index_filter_plugin_name string, index_filter_selector string, index_filter_op string, index_filter_value ColumnValue, index_filter_second_value ColumnValue, index_filter_has_second_value bool, order_by_column string, order_desc bool, post_filter_count int, limit int, select_columns []string, start_primary_key []u8, start_index_value ColumnValue, has_start_index_value bool) !([]TypedSchemaRow, i64, i64, i64, i64, i64, i64, int, int, int) {
	plan := QueryPlan{
		table_name:        spec.table.name
		strategy:          strategy
		index_name:        index_name
		index_filter:      QueryFilter{
			column_name:      index_filter_column_name
			plugin_name:      index_filter_plugin_name
			selector:         index_filter_selector
			op:               query_filter_op_from_name(index_filter_op)
			value:            clone_column_value(index_filter_value)
			second_value:     clone_column_value(index_filter_second_value)
			has_second_value: index_filter_has_second_value
		}
		order_by:          QueryOrder{
			column_name: order_by_column
			direction:   if order_desc { .desc } else { .asc }
		}
		post_filter_count: post_filter_count
		limit:             limit
	}
	request := QueryRequest{
		table_name:            spec.table.name
		select_columns:        select_columns.clone()
		start_primary_key:     start_primary_key.clone()
		start_index_value:     clone_column_value(start_index_value)
		has_start_index_value: has_start_index_value
		limit:                 limit
	}
	profiled_rows := if plan.index_name.len > 0 {
		query_rows_from_database_index_profiled(session, mut db, spec, plan, request)!
	} else {
		ProfiledQueryRows{
			rows: query_rows_from_database_scan(session, mut db, spec, plan)!
		}
	}
	return profiled_rows.rows.clone(), profiled_rows.begin_tx_ms, profiled_rows.begin_checkout_ms, profiled_rows.begin_tree_load_ms, profiled_rows.begin_wrap_ms, profiled_rows.view_ms, profiled_rows.scan_ms, profiled_rows.scan_nodes, profiled_rows.scan_leaves, profiled_rows.scan_items
}

fn execute_planned_query_fetch_profiled_in_transaction(session TransactionSession, spec TypedTableSpec, strategy string, index_name string, index_filter_column_name string, index_filter_plugin_name string, index_filter_selector string, index_filter_op string, index_filter_value ColumnValue, index_filter_second_value ColumnValue, index_filter_has_second_value bool, order_by_column string, order_desc bool, post_filter_count int, limit int, select_columns []string, start_primary_key []u8, start_index_value ColumnValue, has_start_index_value bool) !([]TypedSchemaRow, i64, i64, i64, i64, i64, i64, int, int, int) {
	plan := QueryPlan{
		table_name:        spec.table.name
		strategy:          strategy
		index_name:        index_name
		index_filter:      QueryFilter{
			column_name:      index_filter_column_name
			plugin_name:      index_filter_plugin_name
			selector:         index_filter_selector
			op:               query_filter_op_from_name(index_filter_op)
			value:            clone_column_value(index_filter_value)
			second_value:     clone_column_value(index_filter_second_value)
			has_second_value: index_filter_has_second_value
		}
		order_by:          QueryOrder{
			column_name: order_by_column
			direction:   if order_desc { .desc } else { .asc }
		}
		post_filter_count: post_filter_count
		limit:             limit
	}
	request := QueryRequest{
		table_name:            spec.table.name
		select_columns:        select_columns.clone()
		start_primary_key:     start_primary_key.clone()
		start_index_value:     clone_column_value(start_index_value)
		has_start_index_value: has_start_index_value
		limit:                 limit
	}
	profiled_rows := if plan.index_name.len > 0 {
		query_rows_from_transaction_index_profiled(session, spec, plan, request)!
	} else {
		ProfiledQueryRows{
			rows: query_rows_from_transaction_scan(session, spec, plan)!
		}
	}
	return profiled_rows.rows.clone(), profiled_rows.begin_tx_ms, profiled_rows.begin_checkout_ms, profiled_rows.begin_tree_load_ms, profiled_rows.begin_wrap_ms, profiled_rows.view_ms, profiled_rows.scan_ms, profiled_rows.scan_nodes, profiled_rows.scan_leaves, profiled_rows.scan_items
}

struct QueryIndexFetchSpec {
	fetch_limit       int
	push_projection   bool
	projected_columns []string
	base_strategy     string
}

fn query_rows_from_database_index_profiled(session DatabaseSession, mut db PersistentDatabase, spec TypedTableSpec, plan QueryPlan, request QueryRequest) !ProfiledQueryRows {
	fetch := query_index_fetch_spec(spec, plan, request)
	mut scan_sw := time.new_stopwatch()
	mut rows := []TypedSchemaRow{}
	if query_plan_uses_ordered_index_scan(fetch) {
		if fetch.push_projection {
			mut reader := session.index_reader(mut db, plan.table_name, plan.index_name)!
			projected_rows, ordered_stats := reader.find_rows_covering_ordered_projected_with_stats(request.start_index_value,
				request.has_start_index_value, request.start_primary_key, fetch.fetch_limit,
				fetch.projected_columns, fetch.base_strategy == 'index_order_desc')!
			return ProfiledQueryRows{
				rows:        projected_rows
				scan_ms:     scan_sw.elapsed().milliseconds()
				scan_nodes:  ordered_stats.nodes_read
				scan_leaves: ordered_stats.leaves_visited
				scan_items:  ordered_stats.items_examined
			}
		} else {
			rows = session.lookup_index_ordered(mut db, plan.table_name, plan.index_name,
				request.start_index_value, request.has_start_index_value,
				request.start_primary_key, fetch.fetch_limit,
				fetch.base_strategy == 'index_order_desc')!
		}
		return ProfiledQueryRows{
			rows:    rows
			scan_ms: scan_sw.elapsed().milliseconds()
		}
	}
	if query_plan_uses_reverse_filtered_order(plan) {
		rows = query_rows_from_database_reverse_filtered_index(session, mut db, plan, fetch)!
		return ProfiledQueryRows{
			rows:    rows
			scan_ms: scan_sw.elapsed().milliseconds()
		}
	}
	scan_sw.restart()
	rows = query_rows_from_database_filtered_index(session, mut db, plan, fetch)!
	return ProfiledQueryRows{
		rows:    rows
		scan_ms: scan_sw.elapsed().milliseconds()
	}
}

fn query_rows_from_database_scan(session DatabaseSession, mut db PersistentDatabase, spec TypedTableSpec, plan QueryPlan) ![]TypedSchemaRow {
	_ = spec
	return session.scan_table(mut db, plan.table_name, 0)
}

fn query_rows_from_transaction_index_profiled(session TransactionSession, spec TypedTableSpec, plan QueryPlan, request QueryRequest) !ProfiledQueryRows {
	fetch := query_index_fetch_spec(spec, plan, request)
	mut view_sw := time.new_stopwatch()
	view := session.working_set.transaction().indexed_view(plan.table_name)!
	view_ms := view_sw.elapsed().milliseconds()
	mut scan_sw := time.new_stopwatch()
	mut rows := []TypedSchemaRow{}
	if query_plan_uses_ordered_index_scan(fetch) {
		rows = typed_scan_rows_by_index(view, plan.index_name, TypedIndexScanRequest{
			mode:              .all
			value:             clone_column_value(request.start_index_value)
			has_value:         request.has_start_index_value
			start_primary_key: request.start_primary_key.clone()
			limit:             fetch.fetch_limit
			columns:           if fetch.push_projection {
				fetch.projected_columns
			} else {
				[]string{}
			}
			reverse:           fetch.base_strategy == 'index_order_desc'
		})!
		return ProfiledQueryRows{
			rows:    rows
			view_ms: view_ms
			scan_ms: scan_sw.elapsed().milliseconds()
		}
	}
	if query_plan_uses_reverse_filtered_order(plan) {
		rows = query_rows_from_transaction_reverse_filtered_index(session, plan, fetch)!
		if rows.len > 0 {
			return ProfiledQueryRows{
				rows:    rows
				view_ms: view_ms
				scan_ms: scan_sw.elapsed().milliseconds()
			}
		}
	}
	rows = query_rows_from_transaction_filtered_index(session, plan, fetch)!
	return ProfiledQueryRows{
		rows:    rows
		view_ms: view_ms
		scan_ms: scan_sw.elapsed().milliseconds()
	}
}

fn query_rows_from_transaction_scan(session TransactionSession, spec TypedTableSpec, plan QueryPlan) ![]TypedSchemaRow {
	_ = spec
	return session.scan_table(plan.table_name, 0)
}

fn query_can_push_projection(spec TypedTableSpec, plan QueryPlan, select_columns []string) bool {
	if select_columns.len == 0 || plan.post_filter_count > 0 || plan.index_name.len == 0 {
		return false
	}
	index := query_index_by_name(spec, plan.index_name) or { return false }
	return core.query_projection_pushdown_eligible(select_columns.len, query_index_covers_selection(index,
		select_columns), index.is_field_selector(), index.is_fts(), plan.post_filter_count)
}

fn query_index_covers_selection(index SchemaIndexDef, select_columns []string) bool {
	if select_columns.len == 0 {
		return index.stores_full_row()
	}
	return index.can_cover_columns(select_columns)
}

fn query_projected_fetch_columns(plan QueryPlan, select_columns []string) []string {
	if select_columns.len == 0 {
		return []string{}
	}
	mut columns := select_columns.clone()
	anchor_column := if plan.index_filter.column_name.len > 0 {
		plan.index_filter.column_name
	} else {
		plan.order_by.column_name
	}
	if anchor_column.len > 0 && anchor_column !in columns {
		columns << anchor_column
	}
	return columns
}

fn query_index_fetch_spec(spec TypedTableSpec, plan QueryPlan, request QueryRequest) QueryIndexFetchSpec {
	push_projection := query_can_push_projection(spec, plan, request.select_columns)
	return QueryIndexFetchSpec{
		fetch_limit:       core.query_fetch_limit(plan.post_filter_count, plan.limit)
		push_projection:   push_projection
		projected_columns: query_projected_fetch_columns(plan, request.select_columns)
		base_strategy:     core.query_plan_base_strategy(plan.strategy)
	}
}

fn query_plan_uses_ordered_index_scan(fetch QueryIndexFetchSpec) bool {
	return core.query_ordered_index_scan(fetch.base_strategy)
}

fn query_plan_uses_reverse_filtered_order(plan QueryPlan) bool {
	return core.query_reverse_filtered_order(plan.order_by.column_name,
		plan.index_filter.column_name, plan.order_by.direction == .desc,
		query_filter_op_name(plan.index_filter.op))
}

fn query_rows_from_database_reverse_filtered_index(session DatabaseSession, mut db PersistentDatabase, plan QueryPlan, fetch QueryIndexFetchSpec) ![]TypedSchemaRow {
	return match plan.index_filter.op {
		.prefix {
			if fetch.push_projection {
				session.lookup_index_prefix_reverse_projected(mut db, plan.table_name,
					plan.index_name, plan.index_filter.value, fetch.fetch_limit,
					fetch.projected_columns)!
			} else {
				session.lookup_index_prefix_reverse(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.before {
			if fetch.push_projection {
				session.lookup_index_before_reverse_projected(mut db, plan.table_name,
					plan.index_name, plan.index_filter.value, fetch.fetch_limit,
					fetch.projected_columns)!
			} else {
				session.lookup_index_before_reverse(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.after {
			if fetch.push_projection {
				session.lookup_index_after_reverse_projected(mut db, plan.table_name,
					plan.index_name, plan.index_filter.value, fetch.fetch_limit,
					fetch.projected_columns)!
			} else {
				session.lookup_index_after_reverse(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.between {
			if fetch.push_projection {
				session.lookup_index_between_reverse_projected(mut db, plan.table_name,
					plan.index_name, plan.index_filter.value, plan.index_filter.second_value,
					fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index_between_reverse(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, plan.index_filter.second_value, fetch.fetch_limit)!
			}
		}
		else {
			[]TypedSchemaRow{}
		}
	}
}

fn query_rows_from_transaction_reverse_filtered_index(session TransactionSession, plan QueryPlan, fetch QueryIndexFetchSpec) ![]TypedSchemaRow {
	return match plan.index_filter.op {
		.prefix {
			if fetch.push_projection {
				session.lookup_index_prefix_reverse_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index_prefix_reverse(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.before {
			if fetch.push_projection {
				session.lookup_index_before_reverse_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index_before_reverse(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.after {
			if fetch.push_projection {
				session.lookup_index_after_reverse_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index_after_reverse(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.between {
			if fetch.push_projection {
				session.lookup_index_between_reverse_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, plan.index_filter.second_value, fetch.fetch_limit,
					fetch.projected_columns)!
			} else {
				session.lookup_index_between_reverse(plan.table_name, plan.index_name,
					plan.index_filter.value, plan.index_filter.second_value, fetch.fetch_limit)!
			}
		}
		else {
			[]TypedSchemaRow{}
		}
	}
}

fn query_rows_from_database_filtered_index(session DatabaseSession, mut db PersistentDatabase, plan QueryPlan, fetch QueryIndexFetchSpec) ![]TypedSchemaRow {
	return match plan.index_filter.op {
		.prefix {
			if fetch.push_projection {
				session.lookup_index_prefix_projected(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index_prefix(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.after {
			if fetch.push_projection {
				session.lookup_index_after_projected(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index_after(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.before {
			if fetch.push_projection {
				session.lookup_index_before_projected(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index_before(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.between {
			if fetch.push_projection {
				session.lookup_index_between_projected(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, plan.index_filter.second_value, fetch.fetch_limit,
					fetch.projected_columns)!
			} else {
				session.lookup_index_between(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, plan.index_filter.second_value, fetch.fetch_limit)!
			}
		}
		.eq {
			if fetch.push_projection {
				session.lookup_index_projected(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
	}
}

fn query_rows_from_transaction_filtered_index(session TransactionSession, plan QueryPlan, fetch QueryIndexFetchSpec) ![]TypedSchemaRow {
	return match plan.index_filter.op {
		.prefix {
			if fetch.push_projection {
				session.lookup_index_prefix_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index_prefix(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.after {
			if fetch.push_projection {
				session.lookup_index_after_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index_after(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.before {
			if fetch.push_projection {
				session.lookup_index_before_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index_before(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit)!
			}
		}
		.between {
			if fetch.push_projection {
				session.lookup_index_between_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, plan.index_filter.second_value, fetch.fetch_limit,
					fetch.projected_columns)!
			} else {
				session.lookup_index_between(plan.table_name, plan.index_name,
					plan.index_filter.value, plan.index_filter.second_value, fetch.fetch_limit)!
			}
		}
		.eq {
			if fetch.push_projection {
				session.lookup_index_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch.fetch_limit, fetch.projected_columns)!
			} else {
				session.lookup_index(plan.table_name, plan.index_name, plan.index_filter.value,
					fetch.fetch_limit)!
			}
		}
	}
}

struct FtsQueryPlan {
pub:
	table_name  string
	column_name string
	scope       FtsScope
	kind        FtsQueryKind
	strategy    string
	index_name  string
	selector    string
	term_count  int
	limit       int
}

struct FtsQueryPreview {
pub:
	plan     FtsQueryPlan
	warnings []string
	notes    []string
}

struct FtsHit {
pub:
	primary_key    []u8
	score          int
	matched_terms  []string
	matched_scopes []FtsScope
	summary        string
}

struct FtsQueryResult {
pub:
	rows []TypedSchemaRow
	hits []FtsHit
	plan FtsQueryPlan
}

fn fts_selector(scope FtsScope) string {
	return match scope {
		.any { 'fts' }
		else { 'fts:${fts_scope_name(scope)}' }
	}
}

struct GeneralFtsQuery {
pub:
	table_name     string
	index_name     string
	kind           FtsQueryKind
	terms          []string
	select_columns []string
	limit          int
}

struct GeneralFtsQueryPlan {
pub:
	table_name  string
	index_name  string
	column_name string
	strategy    string
	backend     string
	term_count  int
	limit       int
}

struct GeneralFtsHit {
pub:
	primary_key []u8
	score       f64
	snippet     string
}

struct GeneralFtsQueryResult {
pub:
	rows []TypedSchemaRow
	hits []GeneralFtsHit
	plan GeneralFtsQueryPlan
}

fn validate_general_fts_query(query GeneralFtsQuery) ! {
	if query.table_name.len == 0 {
		return error('general fts query requires table_name')
	}
	if query.index_name.len == 0 {
		return error('general fts query requires index_name')
	}
	if query.terms.len == 0 {
		return error('general fts query requires at least one term')
	}
	normalized := fts_normalize_terms(query.terms)
	if normalized.len == 0 {
		return error('general fts query terms cannot all be empty')
	}
	match query.kind {
		.term, .prefix {
			if normalized.len != 1 {
				return error('general fts ${fts_query_kind_name(query.kind)} query requires exactly one term')
			}
		}
		.all, .any {}
	}
}

fn (database PersistentDatabase) preview_general_fts_query(query GeneralFtsQuery) !GeneralFtsQueryPlan {
	spec := database.table_spec(query.table_name)!
	normalized := normalize_general_fts_query(query)
	index := validate_general_fts_query_request(spec, normalized)!
	return plan_general_fts_query(spec, index, normalized)
}

fn (session DatabaseSession) preview_general_fts_query(query GeneralFtsQuery) !GeneralFtsQueryPlan {
	spec := session.table_spec(query.table_name)!
	normalized := normalize_general_fts_query(query)
	index := validate_general_fts_query_request(spec, normalized)!
	return plan_general_fts_query(spec, index, normalized)
}

fn (mut database PersistentDatabase) query_general_fts(branch_name string, query GeneralFtsQuery) !GeneralFtsQueryResult {
	mut session := database.open_session(branch_name)!
	return session.query_general_fts(mut database, query)
}

fn (session DatabaseSession) query_general_fts(mut db PersistentDatabase, query GeneralFtsQuery) !GeneralFtsQueryResult {
	spec := session.table_spec(query.table_name)!
	normalized := normalize_general_fts_query(query)
	index := validate_general_fts_query_request(spec, normalized)!
	plan := plan_general_fts_query(spec, index, normalized)
	rows, sidecar_hits := execute_planned_general_fts_query_fetch(session, mut db,
		normalized.table_name, normalized.index_name, normalized.kind, normalized.terms,
		normalized.limit)!
	mut snippets := []string{cap: sidecar_hits.len}
	for idx, _ in sidecar_hits {
		source_row := if idx < rows.len { rows[idx] } else { TypedSchemaRow{} }
		snippets << general_fts_build_snippet(db, spec.table, source_row, index, normalized)
	}
	mut hits := []GeneralFtsHit{}
	for idx, sidecar_hit in sidecar_hits {
		primary_key := general_fts_decode_row_pk_hex(sidecar_hit.row_pk_hex) or { continue }
		hits << GeneralFtsHit{
			primary_key: primary_key
			score:       sidecar_hit.score
			snippet:     if idx < snippets.len { snippets[idx] } else { '' }
		}
	}
	return GeneralFtsQueryResult{
		rows: project_query_rows(rows, normalized.select_columns)!
		hits: hits
		plan: plan
	}
}

fn (database PersistentDatabase) preview_fts_query(query FtsQuery) !FtsQueryPlan {
	spec := database.table_spec(query.table_name)!
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	return plan_fts_query(spec, normalized)
}

fn (database PersistentDatabase) preview_fts_query_details(query FtsQuery) !FtsQueryPreview {
	spec := database.table_spec(query.table_name)!
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	plan := plan_fts_query(spec, normalized)
	return build_fts_query_preview(spec, normalized, plan)
}

fn (session DatabaseSession) preview_fts_query(query FtsQuery) !FtsQueryPlan {
	spec := session.table_spec(query.table_name)!
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	return plan_fts_query(spec, normalized)
}

fn (session DatabaseSession) preview_fts_query_details(query FtsQuery) !FtsQueryPreview {
	spec := session.table_spec(query.table_name)!
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	plan := plan_fts_query(spec, normalized)
	return build_fts_query_preview(spec, normalized, plan)
}

fn (session DatabaseSession) query_fts(mut db PersistentDatabase, query FtsQuery) !FtsQueryResult {
	spec := session.table_spec(query.table_name)!
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	plan := plan_fts_query(spec, normalized)
	rows := execute_planned_fts_query_fetch(session, mut db, spec, normalized.column_name,
		normalized.scope, normalized.kind, normalized.terms, normalized.limit, plan.index_name)!
	ranked_rows, ranked_hits := rank_fts_query_rows(db.root_dir, spec.table,
		normalized.column_name, normalized.scope, normalized.kind, normalized.terms,
		normalized.limit, rows)!
	return FtsQueryResult{
		rows: project_query_rows(ranked_rows, normalized.select_columns)!
		hits: ranked_hits
		plan: plan
	}
}

fn (session TransactionSession) preview_fts_query(query FtsQuery) !FtsQueryPlan {
	spec := session.working_set.transaction().specs[query.table_name] or {
		return error('typed table not registered: ${query.table_name}')
	}
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	return plan_fts_query(spec, normalized)
}

fn (session TransactionSession) preview_fts_query_details(query FtsQuery) !FtsQueryPreview {
	spec := session.working_set.transaction().specs[query.table_name] or {
		return error('typed table not registered: ${query.table_name}')
	}
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	plan := plan_fts_query(spec, normalized)
	return build_fts_query_preview(spec, normalized, plan)
}

fn (session TransactionSession) query_fts(query FtsQuery) !FtsQueryResult {
	spec := session.working_set.transaction().specs[query.table_name] or {
		return error('typed table not registered: ${query.table_name}')
	}
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	plan := plan_fts_query(spec, normalized)
	rows := execute_planned_fts_query_fetch_in_transaction(session, spec, normalized.column_name,
		normalized.scope, normalized.kind, normalized.terms, normalized.limit, plan.index_name)!
	ranked_rows, ranked_hits := rank_fts_query_rows(session.root_dir, spec.table,
		normalized.column_name, normalized.scope, normalized.kind, normalized.terms,
		normalized.limit, rows)!
	return FtsQueryResult{
		rows: project_query_rows(ranked_rows, normalized.select_columns)!
		hits: ranked_hits
		plan: plan
	}
}

fn normalize_fts_query(query FtsQuery) FtsQuery {
	mut seen := map[string]bool{}
	mut terms := []string{}
	for term in fts_normalize_terms(query.terms) {
		if seen[term] {
			continue
		}
		seen[term] = true
		terms << term
	}
	return FtsQuery{
		...query
		terms: terms
	}
}

fn validate_fts_query_request(spec TypedTableSpec, query FtsQuery) ! {
	validate_fts_query(query)!
	column := spec.table.column(query.column_name)!
	if column.typ != .markdown_ {
		return error('fts query requires markdown column: ${query.column_name}')
	}
	for column_name in query.select_columns {
		if !spec.table.has_column(column_name) {
			return error('fts query select column not found: ${column_name}')
		}
	}
}

fn plan_fts_query(spec TypedTableSpec, query FtsQuery) FtsQueryPlan {
	selector := fts_selector(query.scope)
	index := fts_query_index_for_selector(spec, query.column_name, selector) or { SchemaIndexDef{} }
	strategy := if index.name.len > 0 {
		match query.kind {
			.term { 'index_exact' }
			.prefix { 'index_prefix' }
			.all { 'fts_index_all' }
			.any { 'fts_index_any' }
		}
	} else {
		'fts_scan_${fts_query_kind_name(query.kind)}'
	}
	return FtsQueryPlan{
		table_name:  query.table_name
		column_name: query.column_name
		scope:       query.scope
		kind:        query.kind
		strategy:    strategy
		index_name:  index.name
		selector:    selector
		term_count:  query.terms.len
		limit:       query.limit
	}
}

fn build_fts_query_preview(spec TypedTableSpec, query FtsQuery, plan FtsQueryPlan) FtsQueryPreview {
	_ = spec
	return FtsQueryPreview{
		plan:     plan
		warnings: core.query_fts_preview_warnings(plan.index_name)
		notes:    core.query_fts_preview_notes(fts_query_kind_name(query.kind), query.terms.len)
	}
}

fn fts_query_index_for_selector(spec TypedTableSpec, column_name string, selector string) ?SchemaIndexDef {
	for index in spec.indexes {
		if !index.is_field_selector() {
			continue
		}
		if index.column != column_name {
			continue
		}
		if index.field_selector_plugin() == 'markdown' && index.field_selector() == selector {
			return index
		}
	}
	return none
}

fn general_fts_build_snippet(database &PersistentDatabase, table TableDef, row TypedSchemaRow, index SchemaIndexDef, query GeneralFtsQuery) string {
	if row.primary_key.len == 0 {
		return ''
	}
	source := fts_sidecar_document_text(database, table, row, index) or { return '' }
	return general_fts_snippet_from_text(source, query)
}

fn general_fts_snippet_from_text(source string, query GeneralFtsQuery) string {
	trimmed := source.trim_space()
	if trimmed.len == 0 {
		return ''
	}
	lower_source := trimmed.to_lower()
	mut best_idx := -1
	mut best_len := 0
	for term in query.terms {
		if term.len == 0 {
			continue
		}
		idx := lower_source.index(term) or { continue }
		if best_idx == -1 || idx < best_idx {
			best_idx = idx
			best_len = term.len
		}
	}
	if best_idx == -1 {
		return if trimmed.len > 120 { trimmed[..120] + ' ...' } else { trimmed }
	}
	start := if best_idx > 36 { best_idx - 36 } else { 0 }
	end_anchor := best_idx + if best_len > 0 { best_len } else { 1 }
	end := if end_anchor + 60 < trimmed.len { end_anchor + 60 } else { trimmed.len }
	mut snippet := trimmed[start..end]
	if start > 0 {
		snippet = '... ' + snippet
	}
	if end < trimmed.len {
		snippet += ' ...'
	}
	return snippet
}

fn normalize_general_fts_query(query GeneralFtsQuery) GeneralFtsQuery {
	mut seen := map[string]bool{}
	mut terms := []string{}
	for term in fts_normalize_terms(query.terms) {
		if seen[term] {
			continue
		}
		seen[term] = true
		terms << term
	}
	return GeneralFtsQuery{
		...query
		terms: terms
	}
}

fn validate_general_fts_query_request(spec TypedTableSpec, query GeneralFtsQuery) !SchemaIndexDef {
	validate_general_fts_query(query)!
	index := general_fts_index_by_name(spec, query.index_name)!
	if !index.is_fts() {
		return error('index is not an fts index: ${query.index_name}')
	}
	for column_name in query.select_columns {
		if !spec.table.has_column(column_name) {
			return error('general fts query select column not found: ${column_name}')
		}
	}
	return index
}

fn general_fts_index_by_name(spec TypedTableSpec, index_name string) !SchemaIndexDef {
	for index in spec.indexes {
		if index.name == index_name {
			return index
		}
	}
	return error('typed table index not found: ${index_name}')
}

fn plan_general_fts_query(spec TypedTableSpec, index SchemaIndexDef, query GeneralFtsQuery) GeneralFtsQueryPlan {
	return GeneralFtsQueryPlan{
		table_name:  spec.table.name
		index_name:  index.name
		column_name: index.column
		strategy:    'sqlite_fts5_match'
		backend:     'sqlite_fts5'
		term_count:  query.terms.len
		limit:       query.limit
	}
}

fn compile_general_fts_match_query(query GeneralFtsQuery) string {
	return match query.kind {
		.term { query.terms[0] }
		.prefix { '${query.terms[0]}*' }
		.all { query.terms.join(' ') }
		.any { query.terms.join(' OR ') }
	}
}

fn fetch_general_fts_rows(session DatabaseSession, mut db PersistentDatabase, table_name string, primary_keys [][]u8, columns []string) ![]TypedSchemaRow {
	if primary_keys.len == 0 {
		return []TypedSchemaRow{}
	}
	if columns.len > 0 {
		return session.get_rows_projected(mut db, table_name, primary_keys, columns)
	}
	mut rows := []TypedSchemaRow{cap: primary_keys.len}
	for primary_key in primary_keys {
		rows << session.get_row(mut db, table_name, primary_key)!
	}
	return rows
}

fn general_fts_decode_row_pk_hex(raw string) ![]u8 {
	if raw.len == 0 {
		return []u8{}
	}
	if raw.len % 2 != 0 {
		return error('invalid row_pk hex length')
	}
	mut out := []u8{cap: raw.len / 2}
	for idx := 0; idx < raw.len; idx += 2 {
		hi := general_fts_hex_value(raw[idx])!
		lo := general_fts_hex_value(raw[idx + 1])!
		out << u8((u8(hi) << 4) | u8(lo))
	}
	return out
}

fn general_fts_hex_value(ch u8) !int {
	if ch >= `0` && ch <= `9` {
		return int(ch - `0`)
	}
	if ch >= `a` && ch <= `f` {
		return int(ch - `a`) + 10
	}
	if ch >= `A` && ch <= `F` {
		return int(ch - `A`) + 10
	}
	return error('invalid hex digit')
}

fn execute_planned_general_fts_query_fetch(session DatabaseSession, mut db PersistentDatabase, table_name string, index_name string, kind FtsQueryKind, terms []string, limit int) !([]TypedSchemaRow, []FtsSidecarHit) {
	query := GeneralFtsQuery{
		table_name: table_name
		index_name: index_name
		kind:       kind
		terms:      terms.clone()
		limit:      limit
	}
	match_query := compile_general_fts_match_query(query)
	sidecar_hits := fts_sidecar_query_hits(db.root_dir, fts_sidecar_table_name(query.table_name,
		query.index_name), session.branch_name, match_query, query.limit)!
	primary_keys :=
		sidecar_hits.map(general_fts_decode_row_pk_hex(it.row_pk_hex) or { []u8{} }).filter(it.len > 0)
	full_rows :=
		fetch_general_fts_rows(session, mut db, query.table_name, primary_keys, []string{})!
	return full_rows, sidecar_hits
}

fn query_fts_rows_from_database_index(session DatabaseSession, mut db PersistentDatabase, query FtsQuery, plan FtsQueryPlan) ![]TypedSchemaRow {
	return match query.kind {
		.term { session.lookup_index(mut db, query.table_name, plan.index_name, query.terms[0],
				query.limit)! }
		.prefix { session.lookup_index_prefix(mut db, query.table_name, plan.index_name,
				query.terms[0], query.limit)! }
		.all { fts_intersect_database_index_rows(session, mut db, query.table_name,
				plan.index_name, query.terms, query.limit)! }
		.any { fts_union_database_index_rows(session, mut db, query.table_name, plan.index_name,
				query.terms, query.limit)! }
	}
}

fn query_fts_rows_from_transaction_index(session TransactionSession, query FtsQuery, plan FtsQueryPlan) ![]TypedSchemaRow {
	return match query.kind {
		.term { session.lookup_index(query.table_name, plan.index_name, query.terms[0], query.limit)! }
		.prefix { []TypedSchemaRow{} }
		.all { fts_intersect_transaction_index_rows(session, query.table_name, plan.index_name,
				query.terms, query.limit)! }
		.any { fts_union_transaction_index_rows(session, query.table_name, plan.index_name,
				query.terms, query.limit)! }
	}
}

fn query_fts_rows_from_database_scan(session DatabaseSession, mut db PersistentDatabase, spec TypedTableSpec, query FtsQuery) ![]TypedSchemaRow {
	rows := session.scan_table(mut db, query.table_name, 0)!
	return fts_filter_rows_by_scan(db.root_dir, spec.table, query, rows)
}

fn query_fts_rows_from_transaction_scan(session TransactionSession, spec TypedTableSpec, query FtsQuery) ![]TypedSchemaRow {
	rows := session.scan_table(query.table_name, 0)!
	return fts_filter_rows_by_scan(session.root_dir, spec.table, query, rows)
}

fn fts_intersect_database_index_rows(session DatabaseSession, mut db PersistentDatabase, table_name string, index_name string, terms []string, limit int) ![]TypedSchemaRow {
	mut matched := map[string]TypedSchemaRow{}
	for idx, term in terms {
		rows := session.lookup_index(mut db, table_name, index_name, term, 0)!
		if idx == 0 {
			for row in rows {
				matched[fts_primary_key_key(row.primary_key)] = row
			}
			continue
		}
		mut current := map[string]bool{}
		for row in rows {
			current[fts_primary_key_key(row.primary_key)] = true
		}
		for key, _ in matched {
			if key !in current {
				matched.delete(key)
			}
		}
		if matched.len == 0 {
			break
		}
	}
	return fts_sorted_rows_from_map(matched, limit)
}

fn fts_union_database_index_rows(session DatabaseSession, mut db PersistentDatabase, table_name string, index_name string, terms []string, limit int) ![]TypedSchemaRow {
	mut matched := map[string]TypedSchemaRow{}
	for term in terms {
		rows := session.lookup_index(mut db, table_name, index_name, term, 0)!
		for row in rows {
			matched[fts_primary_key_key(row.primary_key)] = row
		}
	}
	return fts_sorted_rows_from_map(matched, limit)
}

fn fts_intersect_transaction_index_rows(session TransactionSession, table_name string, index_name string, terms []string, limit int) ![]TypedSchemaRow {
	mut matched := map[string]TypedSchemaRow{}
	for idx, term in terms {
		rows := session.lookup_index(table_name, index_name, term, 0)!
		if idx == 0 {
			for row in rows {
				matched[fts_primary_key_key(row.primary_key)] = row
			}
			continue
		}
		mut current := map[string]bool{}
		for row in rows {
			current[fts_primary_key_key(row.primary_key)] = true
		}
		for key, _ in matched {
			if key !in current {
				matched.delete(key)
			}
		}
		if matched.len == 0 {
			break
		}
	}
	return fts_sorted_rows_from_map(matched, limit)
}

fn fts_union_transaction_index_rows(session TransactionSession, table_name string, index_name string, terms []string, limit int) ![]TypedSchemaRow {
	mut matched := map[string]TypedSchemaRow{}
	for term in terms {
		rows := session.lookup_index(table_name, index_name, term, 0)!
		for row in rows {
			matched[fts_primary_key_key(row.primary_key)] = row
		}
	}
	return fts_sorted_rows_from_map(matched, limit)
}

fn fts_filter_rows_by_scan(root_dir string, table TableDef, query FtsQuery, rows []TypedSchemaRow) ![]TypedSchemaRow {
	column := table.column(query.column_name)!
	index := SchemaIndexDef.field_selector('__fts_scan__', column.name, 'markdown',
		fts_selector(query.scope), .string_, false)!
	mut matched := []TypedSchemaRow{}
	for row in rows {
		stored := if row.data.has(column.name) { row.data.get(column.name)! } else { NullValue{} }
		values := expand_field_selector_index_values(root_dir, column, stored, index)!
		if fts_values_match_query(values, query) {
			matched << row
		}
	}
	fts_sort_rows(mut matched)
	if query.limit > 0 && matched.len > query.limit {
		return matched[..query.limit]
	}
	return matched
}

fn fts_values_match_query(values []ColumnValue, query FtsQuery) bool {
	mut terms := map[string]bool{}
	for value in values {
		match value {
			string { terms[value] = true }
			else {}
		}
	}
	match query.kind {
		.term {
			return query.terms[0] in terms
		}
		.prefix {
			for term, _ in terms {
				if term.starts_with(query.terms[0]) {
					return true
				}
			}
			return false
		}
		.all {
			for term in query.terms {
				if term !in terms {
					return false
				}
			}
			return true
		}
		.any {
			for term in query.terms {
				if term in terms {
					return true
				}
			}
			return false
		}
	}
}

fn fts_primary_key_key(primary_key []u8) string {
	return primary_key.hex()
}

fn fts_sort_rows(mut rows []TypedSchemaRow) {
	rows.sort_with_compare(fn (a &TypedSchemaRow, b &TypedSchemaRow) int {
		return compare_key_bytes(a.primary_key, b.primary_key)
	})
}

fn fts_sorted_rows_from_map(rows_map map[string]TypedSchemaRow, limit int) []TypedSchemaRow {
	mut rows := []TypedSchemaRow{}
	for _, row in rows_map {
		rows << row
	}
	fts_sort_rows(mut rows)
	if limit > 0 && rows.len > limit {
		return rows[..limit]
	}
	return rows
}

fn fts_rank_rows(root_dir string, table TableDef, query FtsQuery, rows []TypedSchemaRow) !([]TypedSchemaRow, []FtsHit) {
	mut ranked := []FtsRankedRow{}
	column := table.column(query.column_name)!
	for row in rows {
		hit := fts_explain_row(root_dir, column, query, row) or { continue }
		ranked << FtsRankedRow{
			row: row
			hit: hit
		}
	}
	ranked.sort_with_compare(fn (a &FtsRankedRow, b &FtsRankedRow) int {
		if a.hit.score > b.hit.score {
			return -1
		}
		if a.hit.score < b.hit.score {
			return 1
		}
		return compare_key_bytes(a.row.primary_key, b.row.primary_key)
	})
	mut out_rows := []TypedSchemaRow{cap: ranked.len}
	mut out_hits := []FtsHit{cap: ranked.len}
	for item in ranked {
		out_rows << item.row
		out_hits << item.hit
	}
	if query.limit > 0 && out_rows.len > query.limit {
		return out_rows[..query.limit].clone(), out_hits[..query.limit].clone()
	}
	return out_rows, out_hits
}

fn execute_planned_fts_query_fetch(session DatabaseSession, mut db PersistentDatabase, spec TypedTableSpec, column_name string, scope FtsScope, kind FtsQueryKind, terms []string, limit int, index_name string) ![]TypedSchemaRow {
	query := FtsQuery{
		table_name:  spec.table.name
		column_name: column_name
		scope:       scope
		kind:        kind
		terms:       terms.clone()
		limit:       limit
	}
	plan := FtsQueryPlan{
		table_name:  spec.table.name
		column_name: column_name
		scope:       scope
		kind:        kind
		index_name:  index_name
		term_count:  terms.len
		limit:       limit
	}
	if plan.index_name.len > 0 {
		return query_fts_rows_from_database_index(session, mut db, query, plan)
	}
	return query_fts_rows_from_database_scan(session, mut db, spec, query)
}

fn execute_planned_fts_query_fetch_in_transaction(session TransactionSession, spec TypedTableSpec, column_name string, scope FtsScope, kind FtsQueryKind, terms []string, limit int, index_name string) ![]TypedSchemaRow {
	query := FtsQuery{
		table_name:  spec.table.name
		column_name: column_name
		scope:       scope
		kind:        kind
		terms:       terms.clone()
		limit:       limit
	}
	plan := FtsQueryPlan{
		table_name:  spec.table.name
		column_name: column_name
		scope:       scope
		kind:        kind
		index_name:  index_name
		term_count:  terms.len
		limit:       limit
	}
	if plan.index_name.len > 0 && query.kind != .prefix {
		return query_fts_rows_from_transaction_index(session, query, plan)
	}
	return query_fts_rows_from_transaction_scan(session, spec, query)
}

fn rank_fts_query_rows(root_dir string, table TableDef, column_name string, scope FtsScope, kind FtsQueryKind, terms []string, limit int, rows []TypedSchemaRow) !([]TypedSchemaRow, []FtsHit) {
	query := FtsQuery{
		table_name:  table.name
		column_name: column_name
		scope:       scope
		kind:        kind
		terms:       terms.clone()
		limit:       limit
	}
	return fts_rank_rows(root_dir, table, query, rows)
}

struct FtsRankedRow {
	row TypedSchemaRow
	hit FtsHit
}

fn fts_explain_row(root_dir string, column ColumnDef, query FtsQuery, row TypedSchemaRow) !FtsHit {
	if !row.data.has(column.name) {
		return error('missing markdown payload')
	}
	stored := row.data.get(column.name)!
	raw := match stored {
		MarkdownRef {
			if stored.is_zero() {
				''
			} else {
				load_markdown_source(root_dir, stored.doc_root_id)!
			}
		}
		string {
			stored
		}
		else {
			return error('fts explanation requires markdown payload')
		}
	}

	emissions := emit_markdown_fts_tokens(raw)!
	mut matched_terms_seen := map[string]bool{}
	mut matched_scopes_seen := map[string]bool{}
	mut matched_terms := []string{}
	mut matched_scopes := []FtsScope{}
	mut score := 0
	for emission in emissions {
		if query.scope != .any && emission.scope != query.scope {
			continue
		}
		if !fts_emission_matches_query(emission.term, query) {
			continue
		}
		score += fts_scope_weight(emission.scope)
		if !matched_terms_seen[emission.term] {
			matched_terms_seen[emission.term] = true
			matched_terms << emission.term
		}
		scope_name := fts_scope_name(emission.scope)
		if !matched_scopes_seen[scope_name] {
			matched_scopes_seen[scope_name] = true
			matched_scopes << emission.scope
		}
	}
	if score == 0 {
		return error('row does not match fts query')
	}
	matched_terms.sort()
	matched_scopes.sort_with_compare(fn (a &FtsScope, b &FtsScope) int {
		left := fts_scope_weight(*a)
		right := fts_scope_weight(*b)
		if left > right {
			return -1
		}
		if left < right {
			return 1
		}
		return 0
	})
	return FtsHit{
		primary_key:    row.primary_key.clone()
		score:          score
		matched_terms:  matched_terms
		matched_scopes: matched_scopes
		summary:        fts_hit_summary(matched_terms, matched_scopes)
	}
}

fn fts_emission_matches_query(term string, query FtsQuery) bool {
	match query.kind {
		.term, .all, .any { return term in query.terms }
		.prefix { return term.starts_with(query.terms[0]) }
	}
}

fn fts_scope_weight(scope FtsScope) int {
	return match scope {
		.heading { 8 }
		.paragraph { 4 }
		.list_item { 3 }
		.code_block { 2 }
		.any { 1 }
	}
}

fn fts_hit_summary(terms []string, scopes []FtsScope) string {
	mut scope_names := []string{cap: scopes.len}
	for scope in scopes {
		scope_names << fts_scope_name(scope)
	}
	return 'terms=[' + terms.join(', ') + '] scopes=[' + scope_names.join(', ') + ']'
}

enum QueryComparisonOp {
	eq
	prefix
	gt
	lt
	between
}

struct QueryPredicateTarget {
pub:
	column_name string
	plugin_name string
	selector    string
}

struct QueryPredicateSpec {
pub:
	target           QueryPredicateTarget
	op               QueryFilterOp
	value            ColumnValue
	second_value     ColumnValue = NullValue{}
	has_second_value bool
}

struct QueryLoweringRequest {
pub:
	table_name     string
	predicates     []QueryPredicateSpec
	select_columns []string
	limit          int
}

struct NormalizedQueryPredicate {
pub:
	target           QueryPredicateTarget
	op               QueryComparisonOp
	value            ColumnValue
	second_value     ColumnValue = NullValue{}
	has_second_value bool
}

struct QueryNormalizedLoweringRequest {
pub:
	table_name     string
	predicates     []NormalizedQueryPredicate
	select_columns []string
	limit          int
}

enum SqlFilterKind {
	eq
	like_prefix
	gt
	lt
	between
}

struct SqlFilterFragment {
pub:
	target           QueryPredicateTarget
	kind             SqlFilterKind
	value            ColumnValue
	second_value     ColumnValue = NullValue{}
	has_second_value bool
}

struct SqlFilterLoweringRequest {
pub:
	table_name     string
	filters        []SqlFilterFragment
	select_columns []string
	limit          int
}

struct SqlPredicateAdapterInput {
pub:
	target           QueryPredicateTarget
	kind             SqlFilterKind
	value            ColumnValue
	second_value     ColumnValue = NullValue{}
	has_second_value bool
	source_sql       string
}

struct ProfiledQueryRows {
	rows               []TypedSchemaRow
	begin_tx_ms        i64
	begin_checkout_ms  i64
	begin_tree_load_ms i64
	begin_wrap_ms      i64
	view_ms            i64
	scan_ms            i64
	scan_nodes         int
	scan_leaves        int
	scan_items         int
}

struct QueryFetchedRows {
pub:
	rows               []TypedSchemaRow
	begin_tx_ms        i64
	begin_checkout_ms  i64
	begin_tree_load_ms i64
	begin_wrap_ms      i64
	view_ms            i64
	scan_ms            i64
	scan_nodes         int
	scan_leaves        int
	scan_items         int
}

struct QueryFilterResult {
	rows             []TypedSchemaRow
	has_more         bool
	next_primary_key []u8
	next_index_value ColumnValue = NullValue{}
}

struct QueryBestFilterIndexMatch {
	index  SchemaIndexDef
	filter QueryFilter
	score  int = -1
}

fn query_filter_op_name(op QueryFilterOp) string {
	return match op {
		.eq { 'eq' }
		.prefix { 'prefix' }
		.after { 'after' }
		.before { 'before' }
		.between { 'between' }
	}
}

fn query_filter_op_from_name(name string) QueryFilterOp {
	return match name {
		'prefix' { .prefix }
		'after' { .after }
		'before' { .before }
		'between' { .between }
		else { .eq }
	}
}

fn QueryPredicateSpec.column_eq(column_name string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op:     .eq
		value:  clone_column_value(value)
	}
}

fn QueryPredicateSpec.column_prefix(column_name string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op:     .prefix
		value:  clone_column_value(value)
	}
}

fn QueryPredicateSpec.column_after(column_name string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op:     .after
		value:  clone_column_value(value)
	}
}

fn QueryPredicateSpec.column_before(column_name string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op:     .before
		value:  clone_column_value(value)
	}
}

fn QueryPredicateSpec.column_between(column_name string, start_value ColumnValue, end_value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target:           QueryPredicateTarget{
			column_name: column_name
		}
		op:               .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_second_value: true
	}
}

fn QueryPredicateSpec.field_eq(column_name string, plugin_name string, selector string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .eq
		value:  clone_column_value(value)
	}
}

fn QueryPredicateSpec.field_prefix(column_name string, plugin_name string, selector string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .prefix
		value:  clone_column_value(value)
	}
}

fn QueryPredicateSpec.field_after(column_name string, plugin_name string, selector string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .after
		value:  clone_column_value(value)
	}
}

fn QueryPredicateSpec.field_before(column_name string, plugin_name string, selector string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .before
		value:  clone_column_value(value)
	}
}

fn QueryPredicateSpec.field_between(column_name string, plugin_name string, selector string, start_value ColumnValue, end_value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target:           QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:               .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_second_value: true
	}
}

fn NormalizedQueryPredicate.column_eq(column_name string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op:     .eq
		value:  clone_column_value(value)
	}
}

fn NormalizedQueryPredicate.column_prefix(column_name string, prefix string) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op:     .prefix
		value:  prefix
	}
}

fn NormalizedQueryPredicate.column_gt(column_name string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op:     .gt
		value:  clone_column_value(value)
	}
}

fn NormalizedQueryPredicate.column_lt(column_name string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op:     .lt
		value:  clone_column_value(value)
	}
}

fn NormalizedQueryPredicate.column_between(column_name string, start_value ColumnValue, end_value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target:           QueryPredicateTarget{
			column_name: column_name
		}
		op:               .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_second_value: true
	}
}

fn NormalizedQueryPredicate.field_eq(column_name string, plugin_name string, selector string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .eq
		value:  clone_column_value(value)
	}
}

fn NormalizedQueryPredicate.field_prefix(column_name string, plugin_name string, selector string, prefix string) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .prefix
		value:  prefix
	}
}

fn NormalizedQueryPredicate.field_gt(column_name string, plugin_name string, selector string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .gt
		value:  clone_column_value(value)
	}
}

fn NormalizedQueryPredicate.field_lt(column_name string, plugin_name string, selector string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .lt
		value:  clone_column_value(value)
	}
}

fn NormalizedQueryPredicate.field_between(column_name string, plugin_name string, selector string, start_value ColumnValue, end_value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target:           QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:               .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_second_value: true
	}
}

fn sql_supported_filter_kinds() []SqlFilterKind {
	return [.eq, .like_prefix, .gt, .lt, .between]
}

fn adapt_sql_predicate_fragment(input SqlPredicateAdapterInput) !SqlFilterFragment {
	if input.target.column_name.len == 0 {
		return error('sql predicate adapter requires target column_name')
	}
	if (input.target.plugin_name.len > 0 && input.target.selector.len == 0)
		|| (input.target.plugin_name.len == 0 && input.target.selector.len > 0) {
		return error('sql predicate adapter requires both plugin_name and selector for field selector targets')
	}
	if input.kind == .between && !input.has_second_value {
		return error('sql predicate adapter requires second_value for BETWEEN predicates')
	}
	if input.kind != .between && input.has_second_value {
		return error('sql predicate adapter only accepts second_value for BETWEEN predicates')
	}
	return SqlFilterFragment{
		target:           input.target
		kind:             input.kind
		value:            clone_column_value(input.value)
		second_value:     clone_column_value(input.second_value)
		has_second_value: input.has_second_value
	}
}

fn SqlFilterFragment.column_eq(column_name string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		kind:   .eq
		value:  clone_column_value(value)
	}
}

fn SqlFilterFragment.column_like_prefix(column_name string, prefix string) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		kind:   .like_prefix
		value:  prefix
	}
}

fn SqlFilterFragment.column_gt(column_name string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		kind:   .gt
		value:  clone_column_value(value)
	}
}

fn SqlFilterFragment.column_lt(column_name string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		kind:   .lt
		value:  clone_column_value(value)
	}
}

fn SqlFilterFragment.column_between(column_name string, start_value ColumnValue, end_value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target:           QueryPredicateTarget{
			column_name: column_name
		}
		kind:             .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_second_value: true
	}
}

fn SqlFilterFragment.field_eq(column_name string, plugin_name string, selector string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		kind:   .eq
		value:  clone_column_value(value)
	}
}

fn SqlFilterFragment.field_like_prefix(column_name string, plugin_name string, selector string, prefix string) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		kind:   .like_prefix
		value:  prefix
	}
}

fn SqlFilterFragment.field_gt(column_name string, plugin_name string, selector string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		kind:   .gt
		value:  clone_column_value(value)
	}
}

fn SqlFilterFragment.field_lt(column_name string, plugin_name string, selector string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		kind:   .lt
		value:  clone_column_value(value)
	}
}

fn SqlFilterFragment.field_between(column_name string, plugin_name string, selector string, start_value ColumnValue, end_value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target:           QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		kind:             .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_second_value: true
	}
}

fn validate_query_request(spec TypedTableSpec, request QueryRequest) ! {
	if request.table_name.len == 0 {
		return error('query requires table_name')
	}
	if request.filters.len == 0 && request.order_by.column_name.len == 0 {
		return error('query requires at least one filter or order_by')
	}
	for column_name in request.select_columns {
		if !spec.table.has_column(column_name) {
			return error('query select column not found: ${column_name}')
		}
	}
	for filter in request.filters {
		validate_query_filter(spec.table, filter)!
	}
	if request.order_by.column_name.len > 0 {
		column := spec.table.column(request.order_by.column_name)!
		if !query_column_type_supports_order(column.typ) {
			return error('query order_by requires comparable indexed column: ${request.order_by.column_name}')
		}
		_ = best_index_for_order(spec, request.order_by)!
		if request.filters.len > 0 {
			validate_query_order_with_filters(spec, request)!
		}
	}
}

fn query_column_type_supports_order(typ ColumnType) bool {
	return core.query_type_supports_order(typ.str())
}

fn validate_query_order_with_filters(spec TypedTableSpec, request QueryRequest) ! {
	if request.filters.len != 1 {
		return error(core.query_order_with_filters_error(request.filters.len, false, true, true,
			'eq', request.order_by.direction == .desc))
	}
	filter := request.filters[0]
	indexed_filter := best_index_for_filter(spec, filter) != none
	err_msg := core.query_order_with_filters_error(request.filters.len, filter.is_field_selector(),
		filter.column_name == request.order_by.column_name, indexed_filter,
		query_filter_op_name(filter.op), request.order_by.direction == .desc)
	if err_msg.len > 0 {
		return error(err_msg)
	}
}

fn best_index_for_order(spec TypedTableSpec, order QueryOrder) !SchemaIndexDef {
	return best_index_for_order_for_projection(spec, order, []string{})
}

fn best_index_for_order_for_projection(spec TypedTableSpec, order QueryOrder, select_columns []string) !SchemaIndexDef {
	mut best := SchemaIndexDef{}
	mut best_score := -1
	for index in spec.indexes {
		if !core.query_order_index_eligible(index.is_field_selector(), index.is_json_path(),
			index.is_fts(), index.column == order.column_name) {
			continue
		}
		score := core.query_order_index_score(query_index_covers_selection(index, select_columns),
			select_columns.len)
		if score > best_score {
			best = index
			best_score = score
		}
	}
	if best_score >= 0 {
		return best
	}
	return error('query order_by requires indexed column: ${order.column_name}')
}

fn validate_query_filter(table TableDef, filter QueryFilter) ! {
	column := table.column(filter.column_name)!
	if filter.is_field_selector() {
		if filter.plugin_name.len == 0 || filter.selector.len == 0 {
			return error('field selector filter requires plugin_name and selector: ${filter.column_name}')
		}
		value_type := query_value_type(filter.value)!
		validate_named_field_selector(filter.plugin_name, filter.selector, value_type)!
		validate_query_filter_bounds(filter.op, filter.value, filter.second_value,
			filter.has_second_value)!
		return
	}
	if filter.plugin_name.len > 0 || filter.selector.len > 0 {
		return error('field selector filter requires both plugin_name and selector: ${filter.column_name}')
	}
	if filter.op != .eq {
		validate_query_filter_bounds(filter.op, filter.value, filter.second_value,
			filter.has_second_value)!
		match column.typ {
			.string_, .bytes_, .enum_, .datetime_ {}
			.i64_ {
				if filter.op == .prefix {
					return error('query prefix filters require string-like column: ${filter.column_name}')
				}
			}
			else {
				return error('query range filters require comparable column: ${filter.column_name}')
			}
		}
	}
}

fn validate_query_filter_bounds(op QueryFilterOp, value ColumnValue, second_value ColumnValue, has_second_value bool) ! {
	prefix_value_compatible := match value {
		string, []u8 { true }
		else { false }
	}

	same_kind := query_values_use_same_kind(value, second_value)
	err_msg := core.query_filter_bounds_error(query_filter_op_name(op), prefix_value_compatible,
		has_second_value, same_kind)
	if err_msg.len > 0 {
		return error(err_msg)
	}
}

fn query_assert_same_value_kind(left ColumnValue, right ColumnValue) ! {
	if query_values_use_same_kind(left, right) {
		return
	}
	return error('query filter values must use the same type')
}

fn query_values_use_same_kind(left ColumnValue, right ColumnValue) bool {
	match left {
		bool {
			if right is bool {
				return true
			}
		}
		i64 {
			if right is i64 {
				return true
			}
		}
		string {
			if right is string {
				return true
			}
		}
		[]u8 {
			if right is []u8 {
				return true
			}
		}
		MarkdownRef {
			if right is MarkdownRef {
				return true
			}
		}
		NullValue {}
	}

	return false
}

fn best_index_for_filter(spec TypedTableSpec, filter QueryFilter) ?SchemaIndexDef {
	return best_index_for_filter_for_projection(spec, filter, []string{})
}

fn query_best_filter_index_match(spec TypedTableSpec, filters []QueryFilter, select_columns []string) QueryBestFilterIndexMatch {
	mut best := QueryBestFilterIndexMatch{}
	for filter in filters {
		index := best_index_for_filter_for_projection(spec, filter, select_columns) or { continue }
		score := query_index_score(spec, index, filter, select_columns)
		if score > best.score {
			best = QueryBestFilterIndexMatch{
				index:  index
				filter: filter
				score:  score
			}
		}
	}
	return best
}

fn best_index_for_filter_for_projection(spec TypedTableSpec, filter QueryFilter, select_columns []string) ?SchemaIndexDef {
	mut best := SchemaIndexDef{}
	mut best_score := -1
	for index in spec.indexes {
		if !query_index_matches_filter(spec.table, index, filter) {
			continue
		}
		score := query_index_score(spec, index, filter, select_columns)
		if score > best_score {
			best = index
			best_score = score
		}
	}
	return if best_score >= 0 { best } else { none }
}

fn query_index_matches_filter(table TableDef, index SchemaIndexDef, filter QueryFilter) bool {
	column_matches := index.column == filter.column_name
	selector_plugin_matches := index.field_selector_plugin() == filter.plugin_name
	selector_name_matches := index.field_selector() == filter.selector
	column := index.value_column(table) or { return false }
	return core.query_filter_index_eligible(filter.is_field_selector(), index.is_field_selector(),
		index.is_json_path(), index.is_fts(), column_matches, selector_plugin_matches,
		selector_name_matches, query_column_type_supports_filter_op(column.typ, filter.op))
}

fn query_column_type_supports_filter_op(typ ColumnType, op QueryFilterOp) bool {
	return core.query_type_supports_filter_op(typ.str(), query_filter_op_name(op))
}

fn query_index_score(spec TypedTableSpec, index SchemaIndexDef, filter QueryFilter, select_columns []string) int {
	_ = spec
	return core.query_index_score(query_filter_op_name(filter.op), query_index_covers_selection(index,
		select_columns), filter.is_field_selector(), select_columns.len)
}

fn query_index_by_name(spec TypedTableSpec, index_name string) ?SchemaIndexDef {
	for index in spec.indexes {
		if index.name == index_name {
			return index
		}
	}
	return none
}

fn query_index_supports_projection_pushdown(index SchemaIndexDef, select_columns []string, post_filters []QueryFilter) bool {
	return core.query_projection_pushdown_eligible(select_columns.len, query_index_covers_selection(index,
		select_columns), index.is_field_selector(), index.is_fts(), post_filters.len)
}

fn query_plan_strategy_name(op QueryFilterOp, projected bool) string {
	return core.query_plan_strategy_name(query_filter_op_name(op), projected)
}

fn query_plan_filter_order_strategy_name(filter QueryFilter, order_by QueryOrder, projected bool) string {
	return core.query_plan_filter_order_strategy_name(query_filter_op_name(filter.op),

		order_by.column_name.len > 0 && order_by.column_name == filter.column_name,
		order_by.direction == .desc, projected)
}

fn query_plan_order_strategy_name(direction QueryOrderDirection, projected bool) string {
	return core.query_plan_order_strategy_name(direction == .desc, projected)
}

fn plan_query_request(spec TypedTableSpec, request QueryRequest) !QueryPlan {
	validate_query_request(spec, request)!
	if request.order_by.column_name.len > 0 && request.filters.len == 0 {
		return query_plan_for_order_only_request(spec, request)
	}
	best_match := query_best_filter_index_match(spec, request.filters, request.select_columns)
	if best_match.score >= 0 {
		return query_plan_for_indexed_filter_request(request, best_match)
	}
	return query_table_scan_plan(request)
}

fn query_plan_for_order_only_request(spec TypedTableSpec, request QueryRequest) !QueryPlan {
	order_index := best_index_for_order_for_projection(spec, request.order_by,
		request.select_columns)!
	projected := query_index_supports_projection_pushdown(order_index, request.select_columns,
		[]QueryFilter{})
	return QueryPlan{
		table_name:        request.table_name
		strategy:          query_plan_order_strategy_name(request.order_by.direction, projected)
		index_name:        order_index.name
		index_filter:      QueryFilter{}
		order_by:          request.order_by
		post_filters:      []QueryFilter{}
		post_filter_count: 0
		limit:             request.limit
	}
}

fn query_plan_for_indexed_filter_request(request QueryRequest, best_match QueryBestFilterIndexMatch) QueryPlan {
	post_filters := query_post_filters(request.filters, best_match.filter)
	projected := query_index_supports_projection_pushdown(best_match.index, request.select_columns,
		post_filters)
	return QueryPlan{
		table_name:        request.table_name
		strategy:          query_plan_filter_order_strategy_name(best_match.filter,
			request.order_by, projected)
		index_name:        best_match.index.name
		index_filter:      best_match.filter
		order_by:          request.order_by
		post_filters:      post_filters
		post_filter_count: post_filters.len
		limit:             request.limit
	}
}

fn query_table_scan_plan(request QueryRequest) QueryPlan {
	return QueryPlan{
		table_name:        request.table_name
		strategy:          'table_scan'
		index_name:        ''
		index_filter:      QueryFilter{}
		post_filters:      request.filters.clone()
		post_filter_count: request.filters.len
		limit:             request.limit
	}
}

fn query_post_filters(filters []QueryFilter, chosen QueryFilter) []QueryFilter {
	mut post_filters := []QueryFilter{}
	mut skipped := false
	for filter in filters {
		if !skipped && query_filters_equal(filter, chosen) {
			skipped = true
			continue
		}
		post_filters << filter
	}
	return post_filters
}

fn query_filters_equal(left QueryFilter, right QueryFilter) bool {
	return left.column_name == right.column_name && left.plugin_name == right.plugin_name
		&& left.selector == right.selector && left.op == right.op
		&& column_values_equal(left.value, right.value)
		&& left.has_second_value == right.has_second_value
		&& (!left.has_second_value || column_values_equal(left.second_value, right.second_value))
}

fn query_value_type(value ColumnValue) !ColumnType {
	return match value {
		MarkdownRef { .markdown_ }
		NullValue { return error('query filters do not support null values') }
		bool { .bool_ }
		i64 { .i64_ }
		string { .string_ }
		[]u8 { .bytes_ }
	}
}

fn query_compare_column_values(left ColumnValue, right ColumnValue) int {
	return match left {
		bool {
			match right {
				bool {
					if left == right {
						0
					} else if !left && right {
						-1
					} else {
						1
					}
				}
				else {
					0
				}
			}
		}
		i64 {
			match right {
				i64 {
					if left < right {
						-1
					} else if left > right {
						1
					} else {
						0
					}
				}
				else {
					0
				}
			}
		}
		string {
			match right {
				string {
					if left < right {
						-1
					} else if left > right {
						1
					} else {
						0
					}
				}
				else {
					0
				}
			}
		}
		[]u8 {
			match right {
				[]u8 { compare_key_bytes(left, right) }
				else { 0 }
			}
		}
		MarkdownRef {
			match right {
				MarkdownRef {
					if left.doc_root_id < right.doc_root_id {
						-1
					} else if left.doc_root_id > right.doc_root_id {
						1
					} else {
						0
					}
				}
				else {
					0
				}
			}
		}
		NullValue {
			0
		}
	}
}

fn project_query_rows(rows []TypedSchemaRow, select_columns []string) ![]TypedSchemaRow {
	if select_columns.len == 0 {
		return rows.clone()
	}
	mut projected := []TypedSchemaRow{cap: rows.len}
	for row in rows {
		mut data := TypedRowData.new()
		for name in select_columns {
			if row.data.has(name) {
				data.set(name, row.data.get(name)!)
			}
		}
		projected << TypedSchemaRow{
			primary_key: row.primary_key.clone()
			data:        data
		}
	}
	return projected
}

fn filter_query_rows(root_dir string, table TableDef, rows []TypedSchemaRow, filters []QueryFilter, start_primary_key []u8, start_index_value ColumnValue, has_start_index_value bool, index_filter QueryFilter, order_by QueryOrder, limit int) !QueryFilterResult {
	mut matched := []TypedSchemaRow{}
	for row in rows {
		anchor_filter := if index_filter.column_name.len > 0 {
			index_filter
		} else if order_by.column_name.len > 0 {
			QueryFilter{
				column_name: order_by.column_name
				op:          .eq
				value:       clone_column_value(start_index_value)
			}
		} else {
			QueryFilter{}
		}
		if has_start_index_value && anchor_filter.column_name.len > 0 {
			row_index_value := query_row_anchor_value(root_dir, table, row, anchor_filter) or {
				NullValue{}
			}
			if query_should_skip_from_anchor(row.primary_key, row_index_value, start_primary_key,
				start_index_value, has_start_index_value, order_by.direction == .desc)
			{
				continue
			}
		} else if start_primary_key.len > 0 && order_by.column_name.len == 0
			&& compare_key_bytes(row.primary_key, start_primary_key) <= 0 {
			continue
		}
		if query_row_matches_all_filters(root_dir, table, row, filters)! {
			if limit > 0 && matched.len >= limit {
				last_anchor_filter := if index_filter.column_name.len > 0 {
					index_filter
				} else if order_by.column_name.len > 0 {
					QueryFilter{
						column_name: order_by.column_name
						op:          .eq
						value:       clone_column_value(start_index_value)
					}
				} else {
					QueryFilter{}
				}
				last_anchor := if matched.len > 0 && last_anchor_filter.column_name.len > 0 {
					query_row_anchor_value(root_dir, table, matched[matched.len - 1],
						last_anchor_filter) or { NullValue{} }
				} else {
					NullValue{}
				}
				return QueryFilterResult{
					rows:             matched
					has_more:         true
					next_primary_key: matched[matched.len - 1].primary_key.clone()
					next_index_value: last_anchor
				}
			}
			matched << row
		}
	}
	return QueryFilterResult{
		rows:             matched
		has_more:         false
		next_primary_key: if matched.len > 0 {
			matched[matched.len - 1].primary_key.clone()
		} else {
			[]u8{}
		}
		next_index_value: if matched.len > 0
			&& (index_filter.column_name.len > 0 || order_by.column_name.len > 0) {
			query_row_anchor_value(root_dir, table, matched[matched.len - 1], if index_filter.column_name.len > 0 {
				index_filter
			} else {
				QueryFilter{
					column_name: order_by.column_name
					op:          .eq
					value:       clone_column_value(start_index_value)
				}
			}) or { NullValue{} }
		} else {
			NullValue{}
		}
	}
}

fn query_should_skip_from_anchor(primary_key []u8, row_index_value ColumnValue, start_primary_key []u8, start_index_value ColumnValue, has_start_index_value bool, reverse bool) bool {
	if !has_start_index_value {
		if !reverse {
			return start_primary_key.len > 0
				&& compare_key_bytes(primary_key, start_primary_key) <= 0
		}
		return start_primary_key.len > 0 && compare_key_bytes(primary_key, start_primary_key) >= 0
	}
	value_cmp := query_compare_column_values(row_index_value, start_index_value)
	if reverse {
		if value_cmp > 0 {
			return true
		}
		if value_cmp < 0 {
			return false
		}
		return start_primary_key.len > 0 && compare_key_bytes(primary_key, start_primary_key) >= 0
	}
	if value_cmp < 0 {
		return true
	}
	if value_cmp > 0 {
		return false
	}
	return start_primary_key.len > 0 && compare_key_bytes(primary_key, start_primary_key) <= 0
}

fn query_row_anchor_value(root_dir string, table TableDef, row TypedSchemaRow, filter QueryFilter) !ColumnValue {
	column := table.column(filter.column_name)!
	if !row.data.has(column.name) {
		return NullValue{}
	}
	if !filter.is_field_selector() {
		return row.data.get(column.name)!
	}
	index := SchemaIndexDef.field_selector('__query_anchor__', column.name, filter.plugin_name,
		filter.selector, query_value_type(filter.value)!, false)!
	values := expand_field_selector_index_values(root_dir, column, row.data.get(column.name)!,
		index)!
	mut matched := []ColumnValue{}
	for value in values {
		if query_value_matches_filter(value, filter) {
			matched << value
		}
	}
	if matched.len == 0 {
		return NullValue{}
	}
	mut best := matched[0]
	for value in matched[1..] {
		if query_compare_column_values(value, best) > 0 {
			best = value
		}
	}
	return best
}

fn query_row_matches_all_filters(root_dir string, table TableDef, row TypedSchemaRow, filters []QueryFilter) !bool {
	for filter in filters {
		if !query_row_matches_filter(root_dir, table, row, filter)! {
			return false
		}
	}
	return true
}

fn query_row_matches_filter(root_dir string, table TableDef, row TypedSchemaRow, filter QueryFilter) !bool {
	column := table.column(filter.column_name)!
	if filter.is_field_selector() {
		stored := if row.data.has(column.name) { row.data.get(column.name)! } else { NullValue{} }
		value_type := query_value_type(filter.value)!
		index := SchemaIndexDef.field_selector('__query_filter__', column.name, filter.plugin_name,
			filter.selector, value_type, false)!
		values := expand_field_selector_index_values(root_dir, column, stored, index)!
		for candidate in values {
			if query_value_matches_filter(candidate, filter) {
				return true
			}
		}
		return false
	}
	if !row.data.has(column.name) {
		return false
	}
	return query_value_matches_filter(row.data.get(column.name)!, filter)
}

fn query_value_matches_filter(value ColumnValue, filter QueryFilter) bool {
	return match filter.op {
		.eq {
			column_values_equal(value, filter.value)
		}
		.prefix {
			query_value_has_prefix(value, filter.value)
		}
		.after {
			query_compare_column_values(value, filter.value) > 0
		}
		.before {
			query_compare_column_values(value, filter.value) < 0
		}
		.between {
			query_compare_column_values(value, filter.value) >= 0
				&& query_compare_column_values(value, filter.second_value) <= 0
		}
	}
}

fn query_value_has_prefix(value ColumnValue, prefix ColumnValue) bool {
	return match value {
		string {
			match prefix {
				string { value.starts_with(prefix) }
				else { false }
			}
		}
		[]u8 {
			match prefix {
				[]u8 { value.len >= prefix.len && value[..prefix.len] == prefix }
				else { false }
			}
		}
		else {
			false
		}
	}
}

fn (database PersistentDatabase) lower_query_request(input QueryLoweringRequest) !QueryRequest {
	schema := database.table_query_schema(input.table_name)!
	mut filters := []QueryFilter{cap: input.predicates.len}
	for predicate in input.predicates {
		filters << lower_query_predicate(schema, predicate)!
	}
	return QueryRequest{
		table_name:     input.table_name
		filters:        filters
		select_columns: input.select_columns.clone()
		limit:          input.limit
	}
}

fn lower_query_predicate(schema TableQuerySchema, predicate QueryPredicateSpec) !QueryFilter {
	if predicate.target.column_name.len == 0 {
		return error('query predicate target requires column_name')
	}
	if predicate.target.plugin_name.len > 0 || predicate.target.selector.len > 0 {
		return lower_field_selector_predicate(schema, predicate)
	}
	return lower_column_predicate(schema, predicate)
}

fn lower_column_predicate(schema TableQuerySchema, predicate QueryPredicateSpec) !QueryFilter {
	mut capability := QueryColumnCapability{}
	mut found := false
	for column in schema.columns {
		if column.name == predicate.target.column_name {
			capability = column
			found = true
			break
		}
	}
	if !found {
		return error('query column not found in schema: ${predicate.target.column_name}')
	}
	expected_type := capability.typ
	query_lowering_validate_types(expected_type, predicate)!
	query_lowering_validate_shape(capability.filter_shapes, predicate.op,
		'column `${predicate.target.column_name}`')!
	return query_filter_from_predicate(predicate)
}

fn lower_field_selector_predicate(schema TableQuerySchema, predicate QueryPredicateSpec) !QueryFilter {
	if predicate.target.plugin_name.len == 0 || predicate.target.selector.len == 0 {
		return error('field selector predicate requires plugin_name and selector: ${predicate.target.column_name}')
	}
	mut capability := QueryFieldSelectorCapability{}
	mut found := false
	for selector in schema.field_selectors {
		if selector.column_name == predicate.target.column_name
			&& selector.plugin_name == predicate.target.plugin_name
			&& selector.selector == predicate.target.selector {
			capability = selector
			found = true
			break
		}
	}
	if !found {
		return error('field selector not found in schema: ${predicate.target.column_name}.${predicate.target.plugin_name}:${predicate.target.selector}')
	}
	query_lowering_validate_types(capability.value_type, predicate)!
	query_lowering_validate_shape(capability.filter_shapes, predicate.op,
		'field selector `${predicate.target.column_name}.${predicate.target.plugin_name}:${predicate.target.selector}`')!
	return query_filter_from_predicate(predicate)
}

fn query_lowering_validate_types(expected_type ColumnType, predicate QueryPredicateSpec) ! {
	value_type := query_value_type(predicate.value)!
	if value_type != expected_type {
		return error('query predicate value type mismatch: expected ${expected_type}, got ${value_type}')
	}
	if predicate.has_second_value {
		second_type := query_value_type(predicate.second_value)!
		if second_type != expected_type {
			return error('query predicate second value type mismatch: expected ${expected_type}, got ${second_type}')
		}
	}
	validate_query_filter_bounds(predicate.op, predicate.value, predicate.second_value,
		predicate.has_second_value)!
}

fn query_lowering_validate_shape(shapes []QueryFilterShapeCapability, op QueryFilterOp, target_label string) ! {
	for shape in shapes {
		if shape.op == op {
			return
		}
	}
	return error('query predicate op `${query_filter_op_name(op)}` is not supported for ${target_label}')
}

fn query_filter_from_predicate(predicate QueryPredicateSpec) !QueryFilter {
	if predicate.target.plugin_name.len > 0 || predicate.target.selector.len > 0 {
		return match predicate.op {
			.eq { QueryFilter.field_eq(predicate.target.column_name, predicate.target.plugin_name,
					predicate.target.selector, predicate.value) }
			.prefix { QueryFilter.field_prefix(predicate.target.column_name,
					predicate.target.plugin_name, predicate.target.selector, predicate.value) }
			.after { QueryFilter.field_after(predicate.target.column_name,
					predicate.target.plugin_name, predicate.target.selector, predicate.value) }
			.before { QueryFilter.field_before(predicate.target.column_name,
					predicate.target.plugin_name, predicate.target.selector, predicate.value) }
			.between { QueryFilter.field_between(predicate.target.column_name,
					predicate.target.plugin_name, predicate.target.selector, predicate.value,
					predicate.second_value) }
		}
	}
	return match predicate.op {
		.eq { QueryFilter.eq(predicate.target.column_name, predicate.value) }
		.prefix { QueryFilter.prefix(predicate.target.column_name, predicate.value) }
		.after { QueryFilter.after(predicate.target.column_name, predicate.value) }
		.before { QueryFilter.before(predicate.target.column_name, predicate.value) }
		.between { QueryFilter.between(predicate.target.column_name, predicate.value,
				predicate.second_value) }
	}
}

// Compatibility entrypoint. Prefer `query.predicate_spec_from_normalized(...)` for new in-process callers.
fn (predicate NormalizedQueryPredicate) to_query_predicate_spec() !QueryPredicateSpec {
	return QueryPredicateSpec{
		target:           predicate.target
		op:               normalized_query_op_to_filter_op(predicate.op)
		value:            clone_column_value(predicate.value)
		second_value:     clone_column_value(predicate.second_value)
		has_second_value: predicate.has_second_value
	}
}

// Compatibility entrypoint. Prefer `query.lower_normalized_request(...)` for new in-process callers.
fn (database PersistentDatabase) lower_normalized_query_request(input QueryNormalizedLoweringRequest) !QueryRequest {
	mut predicates := []QueryPredicateSpec{cap: input.predicates.len}
	for predicate in input.predicates {
		predicates << predicate.to_query_predicate_spec()!
	}
	return database.lower_query_request(QueryLoweringRequest{
		table_name:     input.table_name
		predicates:     predicates
		select_columns: input.select_columns.clone()
		limit:          input.limit
	})
}

fn normalized_query_op_to_filter_op(op QueryComparisonOp) QueryFilterOp {
	return match op {
		.eq { .eq }
		.prefix { .prefix }
		.gt { .after }
		.lt { .before }
		.between { .between }
	}
}

// Compatibility entrypoint. Prefer `query.normalized_predicate_from_sql_filter(...)` for new in-process callers.
fn (fragment SqlFilterFragment) to_normalized_query_predicate() !NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target:           fragment.target
		op:               sql_filter_kind_to_query_comparison_op(fragment.kind)
		value:            clone_column_value(fragment.value)
		second_value:     clone_column_value(fragment.second_value)
		has_second_value: fragment.has_second_value
	}
}

// Compatibility entrypoint. Prefer `query.lower_sql_filter_request(...)` for new in-process callers.
fn (database PersistentDatabase) lower_sql_filter_request(input SqlFilterLoweringRequest) !QueryRequest {
	mut predicates := []NormalizedQueryPredicate{cap: input.filters.len}
	for filter in input.filters {
		predicates << filter.to_normalized_query_predicate()!
	}
	return database.lower_normalized_query_request(QueryNormalizedLoweringRequest{
		table_name:     input.table_name
		predicates:     predicates
		select_columns: input.select_columns.clone()
		limit:          input.limit
	})
}

fn sql_filter_kind_to_query_comparison_op(kind SqlFilterKind) QueryComparisonOp {
	return match kind {
		.eq { .eq }
		.like_prefix { .prefix }
		.gt { .gt }
		.lt { .lt }
		.between { .between }
	}
}

struct QueryPlannerHint {
pub:
	op                    QueryFilterOp
	strategy              string
	index_name            string
	stores_row            bool
	score                 int
	supports_reverse_scan bool
	supports_top_n        bool
}

struct QueryFilterShapeCapability {
pub:
	op                    QueryFilterOp
	value_type            ColumnType
	indexed               bool
	index_name            string
	planner_strategy      string
	planner_score         int
	projection_only       bool
	continuation_anchor   bool
	supports_reverse_scan bool
	supports_top_n        bool
	sample_explain        QuerySamplePlanExplain
}

struct QueryFtsShapeCapability {
pub:
	kind             FtsQueryKind
	indexed          bool
	index_name       string
	planner_strategy string
	sample_explain   QuerySamplePlanExplain
}

struct QuerySamplePlanExplain {
pub:
	strategy                    string
	index_name                  string
	warnings                    []string
	notes                       []string
	default_result_shape        string
	supports_continuation_token bool
	supports_reverse_scan       bool
	supports_top_n              bool
}

struct QueryOrderCapability {
pub:
	column_name           string
	direction             QueryOrderDirection
	filter_op             QueryFilterOp
	indexed               bool
	index_name            string
	planner_strategy      string
	supports_continuation bool
	supports_reverse_scan bool
	supports_top_n        bool
	sample_explain        QuerySamplePlanExplain
}

struct QueryColumnCapability {
pub:
	name          string
	typ           ColumnType
	nullable      bool
	filter_ops    []QueryFilterOp
	index_names   []string
	planner_hints []QueryPlannerHint
	filter_shapes []QueryFilterShapeCapability
	order_shapes  []QueryOrderCapability
}

struct QueryIndexCapability {
pub:
	name                string
	column_name         string
	value_type          ColumnType
	stores_row          bool
	is_fts              bool
	fts_query_kinds     []FtsQueryKind
	fts_shapes          []QueryFtsShapeCapability
	json_field          string
	field_selector_meta FieldSelectorRef
	filter_ops          []QueryFilterOp
}

struct QueryFieldSelectorCapability {
pub:
	column_name      string
	plugin_name      string
	selector         string
	value_type       ColumnType
	stores_row       bool
	filter_ops       []QueryFilterOp
	index_names      []string
	projection_names []string
	planner_hints    []QueryPlannerHint
	filter_shapes    []QueryFilterShapeCapability
	order_shapes     []QueryOrderCapability
	fts_query_kinds  []FtsQueryKind
	fts_shapes       []QueryFtsShapeCapability
}

struct QueryProjectionCapability {
pub:
	name             string
	column_name      string
	source_json_path string
	plugin_name      string
	selector         string
	value_type       ColumnType
	aggregate        ColumnAggregate
	priority         int
	cost_hint        AggregateProjectionCostHint
}

struct TableQuerySchema {
pub:
	table_name                  string
	primary_key                 []string
	columns                     []QueryColumnCapability
	indexes                     []QueryIndexCapability
	field_selectors             []QueryFieldSelectorCapability
	projection_metrics          []QueryProjectionCapability
	supported_filter_ops        []QueryFilterOp
	default_result_shape        string
	supports_continuation_token bool
	supports_select_projection  bool
}

fn query_supported_filter_ops() []QueryFilterOp {
	return [.eq, .prefix, .after, .before, .between]
}

// Compatibility entrypoint. Prefer `query.table_schema(...)` for new in-process callers.
fn (database PersistentDatabase) table_query_schema(table_name string) !TableQuerySchema {
	spec := database.table_spec(table_name)!
	mut columns := []QueryColumnCapability{cap: spec.table.columns.len}
	for column in spec.table.columns {
		mut index_names := []string{}
		for index in spec.indexes {
			if index.column == column.name && !index.is_field_selector() {
				index_names << index.name
			}
		}
		columns << QueryColumnCapability{
			name:          column.name
			typ:           column.typ
			nullable:      column.nullable
			filter_ops:    query_supported_ops_for_type(column.typ)
			index_names:   index_names
			planner_hints: query_planner_hints_for_target(spec, column.name, '', '', column.typ)
			filter_shapes: query_filter_shapes_for_target(spec, database.projectors, table_name,
				column.name, '', '', column.typ, []string{})
			order_shapes:  query_order_shapes_for_target(spec, database.projectors, table_name,
				column.name, '', '', column.typ)
		}
	}
	mut indexes := []QueryIndexCapability{cap: spec.indexes.len}
	for index in spec.indexes {
		value_column := index.value_column(spec.table)!
		indexes << QueryIndexCapability{
			name:                index.name
			column_name:         index.column
			value_type:          value_column.typ
			stores_row:          index.stores_row
			is_fts:              index.is_fts()
			fts_query_kinds:     if index.is_fts() {
				[.term, .prefix, .all, .any]
			} else {
				[]FtsQueryKind{}
			}
			fts_shapes:          query_fts_shapes_for_index(spec, index)
			json_field:          index.json_field
			field_selector_meta: index.field_selector_meta() or { FieldSelectorRef{} }
			filter_ops:          if index.is_fts() {
				[]QueryFilterOp{}
			} else {
				query_supported_ops_for_type(value_column.typ)
			}
		}
	}
	mut field_selector_entries := map[string]QueryFieldSelectorCapability{}
	for index in spec.indexes {
		meta := index.field_selector_meta() or { continue }
		key := '${index.column}\n${meta.plugin_name}\n${meta.selector}'
		capability := field_selector_entries[key] or {
			QueryFieldSelectorCapability{
				column_name:      index.column
				plugin_name:      meta.plugin_name
				selector:         meta.selector
				value_type:       meta.value_type
				stores_row:       meta.stores_row
				filter_ops:       query_supported_ops_for_type(meta.value_type)
				index_names:      []string{}
				projection_names: []string{}
				planner_hints:    query_planner_hints_for_target(spec, index.column,
					meta.plugin_name, meta.selector, meta.value_type)
				filter_shapes:    []QueryFilterShapeCapability{}
				order_shapes:     []QueryOrderCapability{}
				fts_query_kinds:  query_supported_fts_kinds_for_selector(meta.plugin_name,
					meta.selector)
				fts_shapes:       query_fts_shapes_for_selector(spec, index.column,
					meta.plugin_name, meta.selector)
			}
		}
		mut index_names := capability.index_names.clone()
		index_names << index.name
		field_selector_entries[key] = QueryFieldSelectorCapability{
			...capability
			stores_row:    capability.stores_row || meta.stores_row
			index_names:   index_names
			filter_shapes: query_filter_shapes_for_target(spec, database.projectors, table_name,
				index.column, meta.plugin_name, meta.selector, meta.value_type,
				capability.projection_names)
			order_shapes:  []QueryOrderCapability{}
		}
	}
	mut projection_metrics := []QueryProjectionCapability{}
	for name in sorted_projector_names(database.projectors) {
		projector := database.projectors[name] or { continue }
		if projector.table_name != table_name {
			continue
		}
		mut capability := QueryProjectionCapability{
			name:             projector.name
			column_name:      projector.column_name
			source_json_path: projector.source_json_path
			plugin_name:      ''
			selector:         ''
			value_type:       .i64_
			aggregate:        projector.aggregate
			priority:         projector.priority
			cost_hint:        projector.cost_hint
		}
		if selector_meta := projector.field_projection_meta() {
			capability = QueryProjectionCapability{
				...capability
				plugin_name: selector_meta.plugin_name
				selector:    selector_meta.selector
				value_type:  selector_meta.value_type
			}
			key := '${projector.column_name}\n${selector_meta.plugin_name}\n${selector_meta.selector}'
			selector_capability := field_selector_entries[key] or {
				QueryFieldSelectorCapability{
					column_name:      projector.column_name
					plugin_name:      selector_meta.plugin_name
					selector:         selector_meta.selector
					value_type:       selector_meta.value_type
					stores_row:       selector_meta.stores_row
					filter_ops:       query_supported_ops_for_type(selector_meta.value_type)
					index_names:      []string{}
					projection_names: []string{}
					planner_hints:    query_planner_hints_for_target(spec, projector.column_name,
						selector_meta.plugin_name, selector_meta.selector, selector_meta.value_type)
					filter_shapes:    []QueryFilterShapeCapability{}
					order_shapes:     []QueryOrderCapability{}
					fts_query_kinds:  query_supported_fts_kinds_for_selector(selector_meta.plugin_name,
						selector_meta.selector)
					fts_shapes:       query_fts_shapes_for_selector(spec, projector.column_name,
						selector_meta.plugin_name, selector_meta.selector)
				}
			}
			mut projection_names := selector_capability.projection_names.clone()
			projection_names << projector.name
			field_selector_entries[key] = QueryFieldSelectorCapability{
				...selector_capability
				projection_names: projection_names
				filter_shapes:    query_filter_shapes_for_target(spec, database.projectors,
					table_name, projector.column_name, selector_meta.plugin_name,
					selector_meta.selector, selector_meta.value_type, projection_names)
				order_shapes:     []QueryOrderCapability{}
			}
		}
		projection_metrics << capability
	}
	mut field_selectors := []QueryFieldSelectorCapability{}
	for _, capability in field_selector_entries {
		field_selectors << capability
	}
	field_selectors.sort_with_compare(fn (a &QueryFieldSelectorCapability, b &QueryFieldSelectorCapability) int {
		left := '${a.column_name}:${a.plugin_name}:${a.selector}'
		right := '${b.column_name}:${b.plugin_name}:${b.selector}'
		if left < right {
			return -1
		}
		if left > right {
			return 1
		}
		return 0
	})
	return TableQuerySchema{
		table_name:                  spec.table.name
		primary_key:                 spec.table.primary_key.clone()
		columns:                     columns
		indexes:                     indexes
		field_selectors:             field_selectors
		projection_metrics:          projection_metrics
		supported_filter_ops:        query_supported_filter_ops()
		default_result_shape:        'page'
		supports_continuation_token: true
		supports_select_projection:  true
	}
}

fn query_supported_ops_for_type(typ ColumnType) []QueryFilterOp {
	return core.query_supported_ops_for_type_name(typ.str()).map(storage_query_filter_op_from_name(it))
}

fn query_sample_value_for_type(typ ColumnType) ColumnValue {
	return match core.query_sample_value_kind(typ.str()) {
		'bool' { ColumnValue(true) }
		'i64' { ColumnValue(i64(1)) }
		'string' { ColumnValue('x') }
		'bytes' { ColumnValue('x'.bytes()) }
		'markdown' { ColumnValue(MarkdownRef{}) }
		else { ColumnValue('') }
	}
}

fn query_sample_filter(column_name string, plugin_name string, selector string, value_type ColumnType, op QueryFilterOp) QueryFilter {
	first := query_sample_value_for_type(value_type)
	second := query_sample_value_for_type(value_type)
	if plugin_name.len > 0 || selector.len > 0 {
		return match op {
			.eq {
				QueryFilter.field_eq(column_name, plugin_name, selector, first)
			}
			.prefix {
				QueryFilter.field_prefix(column_name, plugin_name, selector, first)
			}
			.after {
				QueryFilter.field_after(column_name, plugin_name, selector, first)
			}
			.before {
				QueryFilter.field_before(column_name, plugin_name, selector, first)
			}
			.between {
				QueryFilter.field_between(column_name, plugin_name, selector, first, second)
			}
		}
	}
	return match op {
		.eq { QueryFilter.eq(column_name, first) }
		.prefix { QueryFilter.prefix(column_name, first) }
		.after { QueryFilter.after(column_name, first) }
		.before { QueryFilter.before(column_name, first) }
		.between { QueryFilter.between(column_name, first, second) }
	}
}

struct QueryBestIndexMatch {
	index SchemaIndexDef
	score int = -1
}

fn query_best_index_match_for_filter(spec TypedTableSpec, filter QueryFilter) QueryBestIndexMatch {
	mut best_index := SchemaIndexDef{}
	mut best_score := -1
	for index in spec.indexes {
		if !query_index_matches_filter(spec.table, index, filter) {
			continue
		}
		score := query_index_score(spec, index, filter, []string{})
		if score > best_score {
			best_index = index
			best_score = score
		}
	}
	return QueryBestIndexMatch{
		index: best_index
		score: best_score
	}
}

fn query_planner_hints_for_target(spec TypedTableSpec, column_name string, plugin_name string, selector string, value_type ColumnType) []QueryPlannerHint {
	mut hints := []QueryPlannerHint{}
	for op in query_supported_ops_for_type(value_type) {
		filter := query_sample_filter(column_name, plugin_name, selector, value_type, op)
		best := query_best_index_match_for_filter(spec, filter)
		best_index := best.index
		best_score := best.score
		if best_score < 0 {
			continue
		}
		supports_ordered_reverse := core.query_supports_reverse_scan(best_score >= 0, plugin_name,
			selector, query_filter_op_name(op))
		supports_ordered_top_n := core.query_supports_top_n(best_score >= 0, plugin_name, selector,
			query_filter_op_name(op))
		planner_strategy := query_sample_plan_explain(spec, map[string]AggregateProjectionDef{},
			spec.table.name, filter).strategy
		hints << QueryPlannerHint{
			op:                    op
			strategy:              planner_strategy
			index_name:            best_index.name
			stores_row:            best_index.stores_row
			score:                 best_score
			supports_reverse_scan: supports_ordered_reverse
			supports_top_n:        supports_ordered_top_n
		}
	}
	return hints
}

fn query_sample_plan_request(table_name string, filter QueryFilter, indexed bool) QueryRequest {
	order_direction := core.query_sample_order_direction(indexed, filter.plugin_name,
		filter.selector, query_filter_op_name(filter.op))
	order_by := if order_direction.len > 0 {
		QueryOrder{
			column_name: filter.column_name
			direction:   if order_direction == 'desc' { .desc } else { .asc }
		}
	} else {
		QueryOrder{}
	}
	return QueryRequest{
		table_name: table_name
		filters:    [filter]
		order_by:   order_by
	}
}

fn query_sample_plan_explain(spec TypedTableSpec, projectors map[string]AggregateProjectionDef, table_name string, filter QueryFilter) QuerySamplePlanExplain {
	best := query_best_index_match_for_filter(spec, filter)
	request := query_sample_plan_request(table_name, filter, best.score >= 0)
	plan := plan_query_request(spec, request) or {
		return QuerySamplePlanExplain{
			strategy:                    'table_scan'
			index_name:                  ''
			warnings:                    core.query_sample_plan_fallback_warnings()
			notes:                       []string{}
			default_result_shape:        'page'
			supports_continuation_token: true
			supports_reverse_scan:       false
			supports_top_n:              false
		}
	}
	preview := build_query_plan_preview(spec, projectors, request, plan, false)
	return preview.sample_explain()
}

fn query_filter_shapes_for_target(spec TypedTableSpec, projectors map[string]AggregateProjectionDef, table_name string, column_name string, plugin_name string, selector string, value_type ColumnType, projection_names []string) []QueryFilterShapeCapability {
	mut shapes := []QueryFilterShapeCapability{}
	for op in query_supported_ops_for_type(value_type) {
		filter := query_sample_filter(column_name, plugin_name, selector, value_type, op)
		best := query_best_index_match_for_filter(spec, filter)
		flags := core.query_shape_flags(best.score >= 0, projection_names.len, filter.plugin_name,
			filter.selector, query_filter_op_name(op))
		sample_explain := query_sample_plan_explain(spec, projectors, table_name, filter)
		shapes << QueryFilterShapeCapability{
			op:                    op
			value_type:            value_type
			indexed:               best.score >= 0
			index_name:            if best.score >= 0 { best.index.name } else { '' }
			planner_strategy:      if best.score >= 0 {
				sample_explain.strategy
			} else {
				'table_scan'
			}
			planner_score:         if best.score >= 0 { best.score } else { -1 }
			projection_only:       flags.projection_only
			continuation_anchor:   flags.continuation_anchor
			supports_reverse_scan: flags.supports_reverse
			supports_top_n:        flags.supports_top_n
			sample_explain:        sample_explain
		}
	}
	return shapes
}

fn query_order_shapes_for_target(spec TypedTableSpec, projectors map[string]AggregateProjectionDef, table_name string, column_name string, plugin_name string, selector string, value_type ColumnType) []QueryOrderCapability {
	mut shapes := []QueryOrderCapability{}
	if !core.query_supports_order_shapes(plugin_name, selector) {
		return shapes
	}
	for op in query_supported_ops_for_type(value_type) {
		for direction in [QueryOrderDirection.asc, .desc] {
			request := QueryRequest{
				table_name: table_name
				filters:    [
					query_sample_filter(column_name, plugin_name, selector, value_type, op),
				]
				order_by:   QueryOrder{
					column_name: column_name
					direction:   direction
				}
				limit:      10
			}
			plan := plan_query_request(spec, request) or { continue }
			preview := build_query_plan_preview(spec, projectors, request, plan, false)
			flags := core.query_plan_explain_flags(plan.index_name, plan.strategy,
				preview.supports_continuation_token)
			shapes << QueryOrderCapability{
				column_name:           column_name
				direction:             direction
				filter_op:             op
				indexed:               plan.index_name.len > 0
				index_name:            plan.index_name
				planner_strategy:      plan.strategy
				supports_continuation: flags.supports_continuation
				supports_reverse_scan: flags.supports_reverse
				supports_top_n:        flags.supports_top_n
				sample_explain:        preview.sample_explain()
			}
		}
	}
	return shapes
}

fn query_supported_fts_kinds_for_selector(plugin_name string, selector string) []FtsQueryKind {
	return core.query_supported_markdown_fts_kinds(plugin_name, selector).map(match it {
		'term' { FtsQueryKind.term }
		'prefix' { .prefix }
		'all' { .all }
		'any' { .any }
		else { .term }
	})
}

fn storage_query_filter_op_from_name(name string) QueryFilterOp {
	return match name {
		'eq' { .eq }
		'prefix' { .prefix }
		'after' { .after }
		'before' { .before }
		'between' { .between }
		else { .eq }
	}
}

fn query_sample_fts_terms(kind FtsQueryKind) []string {
	kind_name := match kind {
		.term { 'term' }
		.prefix { 'prefix' }
		.all { 'all' }
		.any { 'any' }
	}

	return core.query_sample_fts_terms(kind_name)
}

fn query_sample_fts_explain(spec TypedTableSpec, column_name string, scope FtsScope, kind FtsQueryKind) QuerySamplePlanExplain {
	query := FtsQuery{
		table_name:  spec.table.name
		column_name: column_name
		scope:       scope
		kind:        kind
		terms:       query_sample_fts_terms(kind)
		limit:       10
	}
	plan := plan_fts_query(spec, query)
	preview := build_fts_query_preview(spec, query, plan)
	return QuerySamplePlanExplain{
		strategy:                    preview.plan.strategy
		index_name:                  preview.plan.index_name
		warnings:                    preview.warnings.clone()
		notes:                       preview.notes.clone()
		default_result_shape:        'rows'
		supports_continuation_token: false
		supports_reverse_scan:       false
		supports_top_n:              false
	}
}

fn query_sample_general_fts_explain(spec TypedTableSpec, index SchemaIndexDef, kind FtsQueryKind) QuerySamplePlanExplain {
	plan := plan_general_fts_query(spec, index, GeneralFtsQuery{
		table_name: spec.table.name
		index_name: index.name
		kind:       kind
		terms:      query_sample_fts_terms(kind)
		limit:      10
	})
	return QuerySamplePlanExplain{
		strategy:                    plan.strategy
		index_name:                  plan.index_name
		warnings:                    []string{}
		notes:                       core.query_sample_general_fts_notes(index.name)
		default_result_shape:        'rows'
		supports_continuation_token: false
		supports_reverse_scan:       false
		supports_top_n:              false
	}
}

fn query_fts_shapes_for_index(spec TypedTableSpec, index SchemaIndexDef) []QueryFtsShapeCapability {
	if !index.is_fts() {
		return []QueryFtsShapeCapability{}
	}
	kinds := []FtsQueryKind{cap: 4}
	mut ordered_kinds := kinds.clone()
	ordered_kinds << .term
	ordered_kinds << .prefix
	ordered_kinds << .all
	ordered_kinds << .any
	mut shapes := []QueryFtsShapeCapability{cap: ordered_kinds.len}
	for kind in ordered_kinds {
		plan := plan_general_fts_query(spec, index, GeneralFtsQuery{
			table_name: spec.table.name
			index_name: index.name
			kind:       kind
			terms:      query_sample_fts_terms(kind)
			limit:      10
		})
		shapes << QueryFtsShapeCapability{
			kind:             kind
			indexed:          true
			index_name:       index.name
			planner_strategy: plan.strategy
			sample_explain:   query_sample_general_fts_explain(spec, index, kind)
		}
	}
	return shapes
}

fn query_fts_shapes_for_selector(spec TypedTableSpec, column_name string, plugin_name string, selector string) []QueryFtsShapeCapability {
	kinds := query_supported_fts_kinds_for_selector(plugin_name, selector)
	if kinds.len == 0 {
		return []QueryFtsShapeCapability{}
	}
	scope := markdown_fts_scope_from_selector(selector)
	mut shapes := []QueryFtsShapeCapability{cap: kinds.len}
	for kind in kinds {
		query := FtsQuery{
			table_name:  spec.table.name
			column_name: column_name
			scope:       scope
			kind:        kind
			terms:       query_sample_fts_terms(kind)
			limit:       10
		}
		plan := plan_fts_query(spec, query)
		shapes << QueryFtsShapeCapability{
			kind:             kind
			indexed:          plan.index_name.len > 0
			index_name:       plan.index_name
			planner_strategy: plan.strategy
			sample_explain:   query_sample_fts_explain(spec, column_name, scope, kind)
		}
	}
	return shapes
}
