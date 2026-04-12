module storage

import encoding.base64
import json
import time

pub enum QueryFilterOp {
	eq
	prefix
	after
	before
	between
}

pub struct QueryFilter {
pub:
	column_name      string
	plugin_name      string
	selector         string
	op               QueryFilterOp
	value            ColumnValue
	second_value     ColumnValue = NullValue{}
	has_second_value bool
}

pub enum QueryOrderDirection {
	asc
	desc
}

pub struct QueryOrder {
pub:
	column_name string
	direction   QueryOrderDirection = .asc
}

pub struct QueryRequest {
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

pub struct QueryGeneralFtsClause {
pub:
	index_name string
	kind       FtsQueryKind
	terms      []string
}

pub struct QueryPlan {
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

pub struct QueryPlanPreview {
pub:
	plan                        QueryPlan
	warnings                    []string
	notes                       []string
	default_result_shape        string
	supports_continuation_token bool
}

pub fn (preview QueryPlanPreview) sample_explain() QuerySamplePlanExplain {
	return QuerySamplePlanExplain{
		strategy:                    preview.plan.strategy
		index_name:                  preview.plan.index_name
		warnings:                    preview.warnings.clone()
		notes:                       preview.notes.clone()
		default_result_shape:        preview.default_result_shape
		supports_continuation_token: preview.supports_continuation_token
		supports_reverse_scan:       query_plan_supports_reverse_executor(preview.plan)
		supports_top_n:              query_plan_supports_top_n_executor(preview.plan)
	}
}

pub struct QueryCursorState {
pub:
	has_more                bool
	next_primary_key        []u8
	next_index_value        ColumnValue = NullValue{}
	next_continuation_token string
}

pub struct QueryCursorPage {
pub:
	rows             []TypedSchemaRow
	plan             QueryPlan
	cursor           QueryCursorState
	general_fts_hits []GeneralFtsHit
}

pub struct QueryExecutionTimings {
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

pub struct ProfiledQueryCursorPage {
pub:
	page    QueryCursorPage
	timings QueryExecutionTimings
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

// QueryResult is the compatibility query envelope that duplicates cursor fields
// at the top level. Prefer QueryCursorPage for new paged-read call sites.
pub struct QueryResult {
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

pub fn QueryFilter.eq(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op:          .eq
		value:       clone_column_value(value)
	}
}

pub fn QueryFilter.prefix(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op:          .prefix
		value:       clone_column_value(value)
	}
}

pub fn QueryFilter.field_eq(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .eq
		value:       clone_column_value(value)
	}
}

pub fn QueryFilter.field_prefix(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .prefix
		value:       clone_column_value(value)
	}
}

pub fn QueryFilter.after(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op:          .after
		value:       clone_column_value(value)
	}
}

pub fn QueryFilter.before(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op:          .before
		value:       clone_column_value(value)
	}
}

pub fn QueryFilter.between(column_name string, start_value ColumnValue, end_value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name:      column_name
		op:               .between
		value:            clone_column_value(start_value)
		second_value:     clone_column_value(end_value)
		has_second_value: true
	}
}

pub fn QueryFilter.field_after(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .after
		value:       clone_column_value(value)
	}
}

pub fn QueryFilter.field_before(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .before
		value:       clone_column_value(value)
	}
}

pub fn QueryFilter.field_between(column_name string, plugin_name string, selector string, start_value ColumnValue, end_value ColumnValue) QueryFilter {
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

pub fn (filter QueryFilter) is_field_selector() bool {
	return filter.plugin_name.len > 0 || filter.selector.len > 0
}

pub fn (database PersistentDatabase) preview_query_plan(request QueryRequest) !QueryPlan {
	if request.general_fts.index_name.len > 0 {
		plan := database.preview_general_fts_query(GeneralFtsQuery{
			table_name:     request.table_name
			index_name:     request.general_fts.index_name
			kind:           request.general_fts.kind
			terms:          request.general_fts.terms.clone()
			select_columns: request.select_columns.clone()
			limit:          request.limit
		})!
		return plan.as_query_plan()
	}
	spec := database.table_spec(request.table_name)!
	return plan_query_request(spec, request)
}

pub fn (database PersistentDatabase) preview_query_plan_details(request QueryRequest) !QueryPlanPreview {
	if request.general_fts.index_name.len > 0 {
		plan := database.preview_general_fts_query(GeneralFtsQuery{
			table_name:     request.table_name
			index_name:     request.general_fts.index_name
			kind:           request.general_fts.kind
			terms:          request.general_fts.terms.clone()
			select_columns: request.select_columns.clone()
			limit:          request.limit
		})!
		return QueryPlanPreview{
			plan: plan.as_query_plan()
			warnings: []string{}
			notes: ['Query will execute against the SQLite FTS5 sidecar for index `${plan.index_name}`.']
			default_result_shape: 'rows'
			supports_continuation_token: false
		}
	}
	spec := database.table_spec(request.table_name)!
	plan := plan_query_request(spec, request)!
	return build_query_plan_preview(spec, database.projectors, request, plan, false)
}

pub fn (session DatabaseSession) preview_query_plan(request QueryRequest) !QueryPlan {
	if request.general_fts.index_name.len > 0 {
		plan := session.preview_general_fts_query(GeneralFtsQuery{
			table_name:     request.table_name
			index_name:     request.general_fts.index_name
			kind:           request.general_fts.kind
			terms:          request.general_fts.terms.clone()
			select_columns: request.select_columns.clone()
			limit:          request.limit
		})!
		return plan.as_query_plan()
	}
	spec := session.table_spec(request.table_name)!
	return plan_query_request(spec, request)
}

pub fn (session DatabaseSession) query_rows(mut db PersistentDatabase, request QueryRequest) !QueryResult {
	return (session.query_page(mut db, request)!).result()
}

// query_page is the preferred public query entrypoint for paged reads.
// query_rows remains as a compatibility wrapper around the cursor-page result.
pub fn (session DatabaseSession) query_page(mut db PersistentDatabase, request QueryRequest) !QueryCursorPage {
	return (session.query_page_profiled(mut db, request)!).page
}

pub fn (session DatabaseSession) query_page_profiled(mut db PersistentDatabase, request QueryRequest) !ProfiledQueryCursorPage {
	mut total_sw := time.new_stopwatch()
	if request.general_fts.index_name.len > 0 {
		mut plan_sw := time.new_stopwatch()
		result := session.query_general_fts(mut db, GeneralFtsQuery{
			table_name:     request.table_name
			index_name:     request.general_fts.index_name
			kind:           request.general_fts.kind
			terms:          request.general_fts.terms.clone()
			select_columns: request.select_columns.clone()
			limit:          request.limit
		})!
		plan_ms := plan_sw.elapsed().milliseconds()
		page := QueryCursorPage{
			rows:             result.rows.clone()
			plan:             result.plan.as_query_plan()
			cursor:           QueryCursorState{}
			general_fts_hits: result.hits.clone()
		}
		return ProfiledQueryCursorPage{
			page: page
			timings: QueryExecutionTimings{
				plan_ms:       plan_ms
				total_ms:      total_sw.elapsed().milliseconds()
				returned_rows: result.rows.len
			}
		}
	}
	spec := session.table_spec(request.table_name)!
	mut plan_sw := time.new_stopwatch()
	plan := plan_query_request(spec, request)!
	plan_ms := plan_sw.elapsed().milliseconds()
	mut normalize_sw := time.new_stopwatch()
	normalized := query_request_with_continuation_token(request, plan)!
	normalize_ms := normalize_sw.elapsed().milliseconds()
	mut fetch_sw := time.new_stopwatch()
	profiled_rows := if plan.index_name.len > 0 {
		query_rows_from_database_index_profiled(session, mut db, spec, plan, normalized)!
	} else {
		ProfiledQueryRows{
			rows: query_rows_from_database_scan(session, mut db, spec, plan)!
		}
	}
	fetch_ms := fetch_sw.elapsed().milliseconds()
	mut rows := profiled_rows.rows.clone()
	fetched_rows := rows.len
	mut filter_sw := time.new_stopwatch()
	filtered := filter_query_rows(db.root_dir, spec.table, rows, normalized.filters, normalized.start_primary_key,
		normalized.start_index_value, normalized.has_start_index_value, plan.index_filter,
		plan.order_by, normalized.limit)!
	filter_ms := filter_sw.elapsed().milliseconds()
	rows = filtered.rows.clone()
	filtered_rows := rows.len
	mut project_sw := time.new_stopwatch()
	rows = project_query_rows(rows, normalized.select_columns)!
	project_ms := project_sw.elapsed().milliseconds()
	mut continuation_sw := time.new_stopwatch()
	cursor := QueryCursorState{
		has_more:                filtered.has_more
		next_primary_key:        filtered.next_primary_key
		next_index_value:        filtered.next_index_value
		next_continuation_token: encode_query_continuation_token_for_plan(plan, filtered.next_primary_key,
			filtered.next_index_value)
	}
	continuation_ms := continuation_sw.elapsed().milliseconds()
	page := QueryCursorPage{
		rows:   rows
		plan:   plan
		cursor: cursor
	}
	return ProfiledQueryCursorPage{
		page:    page
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
			total_ms:                 total_sw.elapsed().milliseconds()
			fetched_rows:             fetched_rows
			filtered_rows:            filtered_rows
			returned_rows:            rows.len
		}
	}
}

pub fn (session TransactionSession) preview_query_plan(request QueryRequest) !QueryPlan {
	if request.general_fts.index_name.len > 0 {
		return error('general fts query requires database session')
	}
	spec := session.working_set.transaction().specs[request.table_name] or {
		return error('typed table not registered: ${request.table_name}')
	}
	return plan_query_request(spec, request)
}

pub fn (session TransactionSession) preview_query_plan_details(request QueryRequest) !QueryPlanPreview {
	if request.general_fts.index_name.len > 0 {
		return error('general fts query requires database session')
	}
	spec := session.working_set.transaction().specs[request.table_name] or {
		return error('typed table not registered: ${request.table_name}')
	}
	plan := plan_query_request(spec, request)!
	return build_query_plan_preview(spec, map[string]AggregateProjectionDef{}, request,
		plan, true)
}

pub fn (session TransactionSession) query_rows(request QueryRequest) !QueryResult {
	return (session.query_page(request)!).result()
}

// query_page is the preferred public query entrypoint for paged reads.
// query_rows remains as a compatibility wrapper around the cursor-page result.
pub fn (session TransactionSession) query_page(request QueryRequest) !QueryCursorPage {
	return (session.query_page_profiled(request)!).page
}

pub fn (session TransactionSession) query_page_profiled(request QueryRequest) !ProfiledQueryCursorPage {
	mut total_sw := time.new_stopwatch()
	if request.general_fts.index_name.len > 0 {
		return error('general fts query requires database session')
	}
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
	profiled_rows := if plan.index_name.len > 0 {
		query_rows_from_transaction_index_profiled(session, spec, plan, normalized)!
	} else {
		ProfiledQueryRows{
			rows: query_rows_from_transaction_scan(session, spec, plan)!
		}
	}
	fetch_ms := fetch_sw.elapsed().milliseconds()
	mut rows := profiled_rows.rows.clone()
	fetched_rows := rows.len
	mut filter_sw := time.new_stopwatch()
	filtered := filter_query_rows(session.root_dir, spec.table, rows, normalized.filters,
		normalized.start_primary_key, normalized.start_index_value, normalized.has_start_index_value,
		plan.index_filter, plan.order_by, normalized.limit)!
	filter_ms := filter_sw.elapsed().milliseconds()
	rows = filtered.rows.clone()
	filtered_rows := rows.len
	mut project_sw := time.new_stopwatch()
	rows = project_query_rows(rows, normalized.select_columns)!
	project_ms := project_sw.elapsed().milliseconds()
	mut continuation_sw := time.new_stopwatch()
	cursor := QueryCursorState{
		has_more:                filtered.has_more
		next_primary_key:        filtered.next_primary_key
		next_index_value:        filtered.next_index_value
		next_continuation_token: encode_query_continuation_token_for_plan(plan, filtered.next_primary_key,
			filtered.next_index_value)
	}
	continuation_ms := continuation_sw.elapsed().milliseconds()
	page := QueryCursorPage{
		rows:   rows
		plan:   plan
		cursor: cursor
	}
	return ProfiledQueryCursorPage{
		page:    page
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
			total_ms:                 total_sw.elapsed().milliseconds()
			fetched_rows:             fetched_rows
			filtered_rows:            filtered_rows
			returned_rows:            rows.len
		}
	}
}

pub fn (result QueryResult) cursor_page() QueryCursorPage {
	return QueryCursorPage{
		rows:             result.rows.clone()
		plan:             result.plan
		cursor:           result.cursor
		general_fts_hits: result.general_fts_hits.clone()
	}
}

pub fn (result QueryResult) page() QueryCursorPage {
	return result.cursor_page()
}

pub fn (page QueryCursorPage) result() QueryResult {
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

pub fn (plan GeneralFtsQueryPlan) as_query_plan() QueryPlan {
	return QueryPlan{
		table_name: plan.table_name
		strategy:   plan.strategy
		index_name: plan.index_name
		limit:      plan.limit
	}
}

pub fn encode_query_continuation_token(table_name string, index_filter QueryFilter, next_primary_key []u8, next_index_value ColumnValue) string {
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

fn query_filter_op_name(op QueryFilterOp) string {
	return match op {
		.eq { 'eq' }
		.prefix { 'prefix' }
		.after { 'after' }
		.before { 'before' }
		.between { 'between' }
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

struct QueryFilterResult {
	rows             []TypedSchemaRow
	has_more         bool
	next_primary_key []u8
	next_index_value ColumnValue = NullValue{}
}

fn plan_query_request(spec TypedTableSpec, request QueryRequest) !QueryPlan {
	validate_query_request(spec, request)!
	if request.order_by.column_name.len > 0 && request.filters.len == 0 {
		order_index := best_index_for_order_for_projection(spec, request.order_by, request.select_columns)!
		projected := request.select_columns.len > 0 && order_index.stores_row
			&& !order_index.is_field_selector()
		return QueryPlan{
			table_name:        request.table_name
			strategy:          query_plan_order_strategy_name(request.order_by.direction,
				projected)
			index_name:        order_index.name
			index_filter:      QueryFilter{}
			order_by:          request.order_by
			post_filters:      []QueryFilter{}
			post_filter_count: 0
			limit:             request.limit
		}
	}
	mut best_index := SchemaIndexDef{}
	mut best_filter := QueryFilter{}
	mut best_score := -1
	for filter in request.filters {
		index := best_index_for_filter_for_projection(spec, filter, request.select_columns) or {
			continue
		}
		score := query_index_score(spec, index, filter, request.select_columns)
		if score > best_score {
			best_index = index
			best_filter = filter
			best_score = score
		}
	}
	if best_score >= 0 {
		post_filters := query_post_filters(request.filters, best_filter)
		projected := request.select_columns.len > 0 && best_index.stores_row
			&& !best_index.is_field_selector() && post_filters.len == 0
		strategy := query_plan_filter_order_strategy_name(best_filter, request.order_by,
			projected)
		return QueryPlan{
			table_name:        request.table_name
			strategy:          strategy
			index_name:        best_index.name
			index_filter:      best_filter
			order_by:          request.order_by
			post_filters:      post_filters
			post_filter_count: post_filters.len
			limit:             request.limit
		}
	}
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

fn query_plan_strategy_name(op QueryFilterOp, projected bool) string {
	base := match op {
		.eq { 'index_exact' }
		.prefix { 'index_prefix' }
		.after { 'index_after' }
		.before { 'index_before' }
		.between { 'index_between' }
	}
	return if projected { '${base}_projected' } else { base }
}

fn query_plan_filter_order_strategy_name(filter QueryFilter, order_by QueryOrder, projected bool) string {
	if order_by.column_name.len > 0 && order_by.column_name == filter.column_name {
		base := match filter.op {
			.eq {
				if order_by.direction == .desc {
					'index_eq_order_desc'
				} else {
					'index_eq_order_asc'
				}
			}
			.prefix {
				if order_by.direction == .desc {
					'index_prefix_order_desc'
				} else {
					'index_prefix_order_asc'
				}
			}
			.after {
				if order_by.direction == .desc {
					'index_after_order_desc'
				} else {
					'index_after_order_asc'
				}
			}
			.before {
				if order_by.direction == .desc {
					'index_before_order_desc'
				} else {
					'index_before_order_asc'
				}
			}
			.between {
				if order_by.direction == .desc {
					'index_between_order_desc'
				} else {
					'index_between_order_asc'
				}
			}
		}
		return if projected { '${base}_projected' } else { base }
	}
	return query_plan_strategy_name(filter.op, projected)
}

fn query_plan_order_strategy_name(direction QueryOrderDirection, projected bool) string {
	base := if direction == .desc { 'index_order_desc' } else { 'index_order_asc' }
	return if projected { '${base}_projected' } else { base }
}

fn query_plan_uses_projection_pushdown(plan QueryPlan) bool {
	return plan.strategy.ends_with('_projected')
}

fn query_plan_supports_reverse_executor(plan QueryPlan) bool {
	base := query_plan_base_strategy(plan)
	return plan.index_name.len > 0 && (base == 'index_before'
		|| base == 'index_order_desc' || base == 'index_before_order_desc'
		|| base == 'index_after_order_desc' || base == 'index_between_order_desc'
		|| base == 'index_prefix_order_desc')
}

fn query_plan_supports_top_n_executor(plan QueryPlan) bool {
	base := query_plan_base_strategy(plan)
	return plan.index_name.len > 0 && (base == 'index_before'
		|| base == 'index_order_desc' || base == 'index_order_asc'
		|| base == 'index_before_order_desc' || base == 'index_after_order_desc'
		|| base == 'index_after_order_asc' || base == 'index_between_order_desc'
		|| base == 'index_between_order_asc' || base == 'index_prefix_order_desc'
		|| base == 'index_prefix_order_asc' || base == 'index_eq_order_desc'
		|| base == 'index_eq_order_asc')
}

fn query_plan_base_strategy(plan QueryPlan) string {
	if query_plan_uses_projection_pushdown(plan) {
		return plan.strategy.all_before_last('_projected')
	}
	return plan.strategy
}

fn build_query_plan_preview(spec TypedTableSpec, projectors map[string]AggregateProjectionDef, request QueryRequest, plan QueryPlan, transaction_local bool) QueryPlanPreview {
	_ = transaction_local
	mut warnings := []string{}
	mut notes := []string{}

	if plan.strategy == 'table_scan' {
		warnings << 'No eligible index matched; planner will fall back to table scan.'
	}
	if plan.post_filter_count > 0 {
		notes << 'Additional filters will run as post-filters after the primary planner step.'
	}
	if query_plan_uses_projection_pushdown(plan) {
		notes << 'Selected columns will be satisfied directly from the covering index.'
	} else if plan.index_name.len > 0 && request.select_columns.len > 0 {
		for index in spec.indexes {
			if index.name == plan.index_name && !index.stores_row {
				notes << 'Selected columns may require base-row fetches because the chosen index is non-covering.'
				break
			}
		}
	}
	if query_plan_supports_reverse_executor(plan) {
		notes << 'A reverse index scan executor is available for this filter shape.'
	}
	if query_plan_supports_top_n_executor(plan) {
		notes << 'Top-N retrieval can be satisfied by combining the reverse executor with a limit.'
	}
	if plan.order_by.column_name.len > 0 {
		notes << 'Requested ordering can be satisfied directly from the chosen index.'
	}
	for filter in request.filters {
		if !filter.is_field_selector() {
			continue
		}
		if best_index_for_filter(spec, filter) != none {
			continue
		}
		field_ref := '${filter.column_name}.${filter.plugin_name}:${filter.selector}'
		if query_filter_has_projection_metric(projectors, request.table_name, filter) {
			warnings << 'Field selector `${field_ref}` is projection-only in the current schema and cannot be planned with an index.'
		} else {
			warnings << 'Field selector `${field_ref}` has no matching derived index and will not benefit from indexed planning.'
		}
	}
	return QueryPlanPreview{
		plan:                        plan
		warnings:                    warnings
		notes:                       notes
		default_result_shape:        'page'
		supports_continuation_token: true
	}
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
		match column.typ {
			.i64_, .string_, .bytes_, .enum_, .datetime_ {}
			else { return error('query order_by requires comparable indexed column: ${request.order_by.column_name}') }
		}
		_ = best_index_for_order(spec, request.order_by)!
		if request.filters.len > 0 {
			validate_query_order_with_filters(spec, request)!
		}
	}
}

fn validate_query_order_with_filters(spec TypedTableSpec, request QueryRequest) ! {
	if request.filters.len != 1 {
		return error('query order_by with filters currently requires a single indexed filter')
	}
	filter := request.filters[0]
	if filter.is_field_selector() {
		return error('query order_by does not yet support field selector filters')
	}
	if filter.column_name != request.order_by.column_name {
		return error('query order_by with filters currently requires ordering on the same indexed column')
	}
	_ = best_index_for_filter(spec, filter) or {
		return error('query order_by with filters requires an indexed filter column')
	}
	match filter.op {
		.eq {}
		.after, .between {
			// both asc and desc can reuse the same indexed range shape
		}
		.prefix {
			// both asc and desc can now use prefix index scan executors
		}
		.before {
			if request.order_by.direction != .desc {
				return error('query order_by asc is not yet supported for before-filtered queries')
			}
		}
	}
}

fn best_index_for_order(spec TypedTableSpec, order QueryOrder) !SchemaIndexDef {
	return best_index_for_order_for_projection(spec, order, []string{})
}

fn best_index_for_order_for_projection(spec TypedTableSpec, order QueryOrder, select_columns []string) !SchemaIndexDef {
	mut best := SchemaIndexDef{}
	mut best_score := -1
	for index in spec.indexes {
		if index.is_field_selector() || index.is_json_path() || index.is_fts()
			|| index.column != order.column_name {
			continue
		}
		mut score := 10
		if select_columns.len > 0 && index.stores_row {
			score += 5
		}
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
		validate_query_filter_bounds(filter.op, filter.value, filter.second_value, filter.has_second_value)!
		return
	}
	if filter.plugin_name.len > 0 || filter.selector.len > 0 {
		return error('field selector filter requires both plugin_name and selector: ${filter.column_name}')
	}
	if filter.op != .eq {
		validate_query_filter_bounds(filter.op, filter.value, filter.second_value, filter.has_second_value)!
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
	match op {
		.prefix {
			match value {
				string, []u8 {}
				else { return error('query prefix filters require string or bytes values') }
			}
		}
		.between {
			if !has_second_value {
				return error('query between filters require second_value')
			}
			query_assert_same_value_kind(value, second_value)!
		}
		.after, .before {
			if has_second_value {
				return error('query after/before filters do not accept second_value')
			}
		}
		.eq {}
	}
}

fn query_assert_same_value_kind(left ColumnValue, right ColumnValue) ! {
	match left {
		bool {
			if right is bool {
				return
			}
		}
		i64 {
			if right is i64 {
				return
			}
		}
		string {
			if right is string {
				return
			}
		}
		[]u8 {
			if right is []u8 {
				return
			}
		}
		MarkdownRef {
			if right is MarkdownRef {
				return
			}
		}
		NullValue {}
	}
	return error('query filter values must use the same type')
}

fn best_index_for_filter(spec TypedTableSpec, filter QueryFilter) ?SchemaIndexDef {
	return best_index_for_filter_for_projection(spec, filter, []string{})
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
	if filter.is_field_selector() {
		return index.is_field_selector() && index.column == filter.column_name
			&& index.field_selector_plugin() == filter.plugin_name
			&& index.field_selector() == filter.selector
	}
	if index.is_field_selector() || index.is_json_path() || index.is_fts() {
		return false
	}
	if index.column != filter.column_name {
		return false
	}
	column := index.value_column(table) or { return false }
	return match filter.op {
		.prefix {
			match column.typ {
				.string_, .bytes_, .enum_, .datetime_ { true }
				else { false }
			}
		}
		.after, .before, .between {
			match column.typ {
				.i64_, .string_, .bytes_, .enum_, .datetime_ { true }
				else { false }
			}
		}
		.eq {
			true
		}
	}
}

fn query_index_score(spec TypedTableSpec, index SchemaIndexDef, filter QueryFilter, select_columns []string) int {
	mut score := 10
	match filter.op {
		.eq { score += 4 }
		.between, .after, .before { score += 3 }
		.prefix { score += 2 }
	}
	if index.stores_row {
		score += 2
	}
	if filter.is_field_selector() {
		score += 1
	}
	if select_columns.len > 0 && index.stores_row {
		score += 1
	}
	return score
}

fn query_index_by_name(spec TypedTableSpec, index_name string) ?SchemaIndexDef {
	for index in spec.indexes {
		if index.name == index_name {
			return index
		}
	}
	return none
}

fn query_can_push_projection(spec TypedTableSpec, plan QueryPlan, select_columns []string) bool {
	if select_columns.len == 0 || plan.post_filter_count > 0 || plan.index_name.len == 0 {
		return false
	}
	index := query_index_by_name(spec, plan.index_name) or { return false }
	return index.stores_row && !index.is_field_selector() && !index.is_fts()
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

fn query_rows_from_database_index(session DatabaseSession, mut db PersistentDatabase, spec TypedTableSpec, plan QueryPlan, request QueryRequest) ![]TypedSchemaRow {
	return (query_rows_from_database_index_profiled(session, mut db, spec, plan, request)!).rows
}

fn query_rows_from_database_index_profiled(session DatabaseSession, mut db PersistentDatabase, spec TypedTableSpec, plan QueryPlan, request QueryRequest) !ProfiledQueryRows {
	fetch_limit := if plan.post_filter_count > 0 {
		0
	} else if plan.limit > 0 {
		plan.limit + 1
	} else {
		0
	}
	push_projection := query_can_push_projection(spec, plan, request.select_columns)
	projected_columns := query_projected_fetch_columns(plan, request.select_columns)
	base := query_plan_base_strategy(plan)
	mut scan_sw := time.new_stopwatch()
	mut rows := []TypedSchemaRow{}
	if base == 'index_order_asc' || base == 'index_order_desc' {
		if push_projection {
			mut reader := session.index_reader(mut db, plan.table_name, plan.index_name)!
			projected_rows, ordered_stats := reader.find_rows_covering_ordered_projected_with_stats(request.start_index_value,
				request.has_start_index_value, request.start_primary_key, fetch_limit,
				projected_columns, base == 'index_order_desc')!
			return ProfiledQueryRows{
				rows:        projected_rows
				scan_ms:     scan_sw.elapsed().milliseconds()
				scan_nodes:  ordered_stats.nodes_read
				scan_leaves: ordered_stats.leaves_visited
				scan_items:  ordered_stats.items_examined
			}
		} else {
			rows = session.lookup_index_ordered(mut db, plan.table_name, plan.index_name,
				request.start_index_value, request.has_start_index_value, request.start_primary_key,
				fetch_limit, base == 'index_order_desc')!
		}
		return ProfiledQueryRows{
			rows:    rows
			scan_ms: scan_sw.elapsed().milliseconds()
		}
	}
	if plan.order_by.column_name.len > 0
		&& plan.order_by.column_name == plan.index_filter.column_name {
		if plan.index_filter.op == .prefix && plan.order_by.direction == .desc {
			if push_projection {
				rows = session.lookup_index_prefix_reverse_projected(mut db, plan.table_name,
					plan.index_name, plan.index_filter.value, fetch_limit, projected_columns)!
			} else {
				rows = session.lookup_index_prefix_reverse(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit)!
			}
			return ProfiledQueryRows{
				rows:    rows
				scan_ms: scan_sw.elapsed().milliseconds()
			}
		}
		if plan.index_filter.op == .before && plan.order_by.direction == .desc {
			if push_projection {
				rows = session.lookup_index_before_reverse_projected(mut db, plan.table_name,
					plan.index_name, plan.index_filter.value, fetch_limit, projected_columns)!
			} else {
				rows = session.lookup_index_before_reverse(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit)!
			}
			return ProfiledQueryRows{
				rows:    rows
				scan_ms: scan_sw.elapsed().milliseconds()
			}
		}
		if plan.index_filter.op == .after && plan.order_by.direction == .desc {
			if push_projection {
				rows = session.lookup_index_after_reverse_projected(mut db, plan.table_name,
					plan.index_name, plan.index_filter.value, fetch_limit, projected_columns)!
			} else {
				rows = session.lookup_index_after_reverse(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit)!
			}
			return ProfiledQueryRows{
				rows:    rows
				scan_ms: scan_sw.elapsed().milliseconds()
			}
		}
		if plan.index_filter.op == .between && plan.order_by.direction == .desc {
			if push_projection {
				rows = session.lookup_index_between_reverse_projected(mut db, plan.table_name,
					plan.index_name, plan.index_filter.value, plan.index_filter.second_value,
					fetch_limit, projected_columns)!
			} else {
				rows = session.lookup_index_between_reverse(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, plan.index_filter.second_value, fetch_limit)!
			}
			return ProfiledQueryRows{
				rows:    rows
				scan_ms: scan_sw.elapsed().milliseconds()
			}
		}
	}
	tx_result := session.begin_transaction_profiled(mut db)!
	tx := tx_result.tx
	begin_tx_ms := tx_result.timings.total_ms
	mut view_sw := time.new_stopwatch()
	_ = tx.indexed_view(plan.table_name)!
	view_ms := view_sw.elapsed().milliseconds()
	scan_sw.restart()
	rows = match plan.index_filter.op {
		.prefix {
			if push_projection {
				session.lookup_index_prefix_projected(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit, projected_columns)!
			} else {
				session.lookup_index_prefix(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit)!
			}
		}
		.after {
			if push_projection {
				session.lookup_index_after_projected(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit, projected_columns)!
			} else {
				session.lookup_index_after(mut db, plan.table_name, plan.index_name, plan.index_filter.value,
					fetch_limit)!
			}
		}
		.before {
			if push_projection {
				session.lookup_index_before_projected(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit, projected_columns)!
			} else {
				session.lookup_index_before(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit)!
			}
		}
		.between {
			if push_projection {
				session.lookup_index_between_projected(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, plan.index_filter.second_value, fetch_limit,
					projected_columns)!
			} else {
				session.lookup_index_between(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, plan.index_filter.second_value, fetch_limit)!
			}
		}
		.eq {
			if push_projection {
				session.lookup_index_projected(mut db, plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit, projected_columns)!
			} else {
				session.lookup_index(mut db, plan.table_name, plan.index_name, plan.index_filter.value,
					fetch_limit)!
			}
		}
	}
	return ProfiledQueryRows{
		rows:               rows
		begin_tx_ms:        begin_tx_ms
		begin_checkout_ms:  tx_result.timings.checkout_ms
		begin_tree_load_ms: tx_result.timings.tree_load_ms
		begin_wrap_ms:      tx_result.timings.wrap_ms
		view_ms:            view_ms
		scan_ms:            scan_sw.elapsed().milliseconds()
	}
}

fn query_rows_from_database_scan(session DatabaseSession, mut db PersistentDatabase, spec TypedTableSpec, plan QueryPlan) ![]TypedSchemaRow {
	return session.scan_table(mut db, plan.table_name, 0)
}

fn query_rows_from_transaction_index(session TransactionSession, spec TypedTableSpec, plan QueryPlan, request QueryRequest) ![]TypedSchemaRow {
	return (query_rows_from_transaction_index_profiled(session, spec, plan, request)!).rows
}

fn query_rows_from_transaction_index_profiled(session TransactionSession, spec TypedTableSpec, plan QueryPlan, request QueryRequest) !ProfiledQueryRows {
	fetch_limit := if plan.post_filter_count > 0 {
		0
	} else if plan.limit > 0 {
		plan.limit + 1
	} else {
		0
	}
	push_projection := query_can_push_projection(spec, plan, request.select_columns)
	projected_columns := query_projected_fetch_columns(plan, request.select_columns)
	base := query_plan_base_strategy(plan)
	mut view_sw := time.new_stopwatch()
	view := session.working_set.transaction().indexed_view(plan.table_name)!
	view_ms := view_sw.elapsed().milliseconds()
	mut scan_sw := time.new_stopwatch()
	mut rows := []TypedSchemaRow{}
	if base == 'index_order_asc' || base == 'index_order_desc' {
		rows = typed_scan_rows_by_index(view, plan.index_name, TypedIndexScanRequest{
			mode:              .all
			value:             clone_column_value(request.start_index_value)
			has_value:         request.has_start_index_value
			start_primary_key: request.start_primary_key.clone()
			limit:             fetch_limit
			columns:           if push_projection { projected_columns } else { []string{} }
			reverse:           base == 'index_order_desc'
		})!
		return ProfiledQueryRows{
			rows:    rows
			view_ms: view_ms
			scan_ms: scan_sw.elapsed().milliseconds()
		}
	}
	if plan.order_by.column_name.len > 0
		&& plan.order_by.column_name == plan.index_filter.column_name
		&& plan.order_by.direction == .desc {
		rows = match plan.index_filter.op {
			.prefix {
				if push_projection {
					session.lookup_index_prefix_reverse_projected(plan.table_name, plan.index_name,
						plan.index_filter.value, fetch_limit, projected_columns)!
				} else {
					session.lookup_index_prefix_reverse(plan.table_name, plan.index_name,
						plan.index_filter.value, fetch_limit)!
				}
			}
			.before {
				if push_projection {
					session.lookup_index_before_reverse_projected(plan.table_name, plan.index_name,
						plan.index_filter.value, fetch_limit, projected_columns)!
				} else {
					session.lookup_index_before_reverse(plan.table_name, plan.index_name,
						plan.index_filter.value, fetch_limit)!
				}
			}
			.after {
				if push_projection {
					session.lookup_index_after_reverse_projected(plan.table_name, plan.index_name,
						plan.index_filter.value, fetch_limit, projected_columns)!
				} else {
					session.lookup_index_after_reverse(plan.table_name, plan.index_name,
						plan.index_filter.value, fetch_limit)!
				}
			}
			.between {
				if push_projection {
					session.lookup_index_between_reverse_projected(plan.table_name, plan.index_name,
						plan.index_filter.value, plan.index_filter.second_value, fetch_limit,
						projected_columns)!
				} else {
					session.lookup_index_between_reverse(plan.table_name, plan.index_name,
						plan.index_filter.value, plan.index_filter.second_value, fetch_limit)!
				}
			}
			else {
				[]TypedSchemaRow{}
			}
		}
		if rows.len > 0 {
			return ProfiledQueryRows{
				rows:    rows
				view_ms: view_ms
				scan_ms: scan_sw.elapsed().milliseconds()
			}
		}
	}
	rows = match plan.index_filter.op {
		.prefix {
			if push_projection {
				session.lookup_index_prefix_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit, projected_columns)!
			} else {
				session.lookup_index_prefix(plan.table_name, plan.index_name, plan.index_filter.value,
					fetch_limit)!
			}
		}
		.after {
			if push_projection {
				session.lookup_index_after_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit, projected_columns)!
			} else {
				session.lookup_index_after(plan.table_name, plan.index_name, plan.index_filter.value,
					fetch_limit)!
			}
		}
		.before {
			if push_projection {
				session.lookup_index_before_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, fetch_limit, projected_columns)!
			} else {
				session.lookup_index_before(plan.table_name, plan.index_name, plan.index_filter.value,
					fetch_limit)!
			}
		}
		.between {
			if push_projection {
				session.lookup_index_between_projected(plan.table_name, plan.index_name,
					plan.index_filter.value, plan.index_filter.second_value, fetch_limit,
					projected_columns)!
			} else {
				session.lookup_index_between(plan.table_name, plan.index_name, plan.index_filter.value,
					plan.index_filter.second_value, fetch_limit)!
			}
		}
		.eq {
			if push_projection {
				session.lookup_index_projected(plan.table_name, plan.index_name, plan.index_filter.value,
					fetch_limit, projected_columns)!
			} else {
				session.lookup_index(plan.table_name, plan.index_name, plan.index_filter.value,
					fetch_limit)!
			}
		}
	}
	return ProfiledQueryRows{
		rows:    rows
		view_ms: view_ms
		scan_ms: scan_sw.elapsed().milliseconds()
	}
}

fn query_rows_from_transaction_scan(session TransactionSession, spec TypedTableSpec, plan QueryPlan) ![]TypedSchemaRow {
	return session.scan_table(plan.table_name, 0)
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
