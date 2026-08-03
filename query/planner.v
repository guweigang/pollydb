module query

import core
import encoding.base64
import json
import time

pub fn preview_plan(database Database, request Request) !Plan {
	if request.general_fts.index_name.len > 0 {
		return preview_general_fts(database, general_fts_request_from_clause(request.table_name,
			request.general_fts, request.select_columns, request.limit))!.as_query_plan()
	}
	return plan_request(query_spec(database.db.table_spec(request.table_name)!,
		map[string]ProjectionDef{}), request)
}

pub fn preview_plan_from_spec(spec QuerySpec, request Request) !Plan {
	if request.general_fts.index_name.len > 0 {
		return preview_general_fts_from_spec(spec, general_fts_request_from_clause(request.table_name,
			request.general_fts, request.select_columns, request.limit))!.as_query_plan()
	}
	return plan_request(spec, request)
}

pub fn preview_plan_details(database Database, request Request) !PlanPreview {
	if request.general_fts.index_name.len > 0 {
		return preview_general_fts_details(database, general_fts_request_from_clause(request.table_name,
			request.general_fts, request.select_columns, request.limit))
	}
	plan := preview_plan(database, request)!
	schema := table_schema(database, request.table_name)!
	return build_plan_preview(schema, request, plan)
}

pub fn preview_plan_details_from_spec(spec QuerySpec, request Request) !PlanPreview {
	if request.general_fts.index_name.len > 0 {
		return preview_general_fts_details_from_spec(spec, general_fts_request_from_clause(request.table_name,
			request.general_fts, request.select_columns, request.limit))
	}
	plan := preview_plan_from_spec(spec, request)!
	schema := table_schema_from_spec(spec, request.table_name)!
	return build_plan_preview(schema, request, plan)
}

pub fn preview_plan_in_session(session Session, request Request) !Plan {
	if request.general_fts.index_name.len > 0 {
		return preview_general_fts_in_session(session, general_fts_request_from_clause(request.table_name,
			request.general_fts, request.select_columns, request.limit))!.as_query_plan()
	}
	return plan_request(query_spec(session.session.table_spec(request.table_name)!,
		map[string]ProjectionDef{}), request)
}

pub fn preview_plan_details_in_session(session Session, request Request) !PlanPreview {
	if request.general_fts.index_name.len > 0 {
		return preview_general_fts_details_in_session(session, general_fts_request_from_clause(request.table_name,
			request.general_fts, request.select_columns, request.limit))
	}
	plan := preview_plan_in_session(session, request)!
	schema := table_schema_from_spec(query_spec(session.session.table_spec(request.table_name)!,
		map[string]ProjectionDef{}), request.table_name)!
	return build_plan_preview(schema, request, plan)
}

pub fn projection_pushdown_eligible(stores_row bool, index_is_field_selector bool, index_is_fts bool, select_columns []string, post_filter_count int) bool {
	return core.query_projection_pushdown_eligible(select_columns.len, stores_row,
		index_is_field_selector, index_is_fts, post_filter_count)
}

pub fn fetch_limit(post_filter_count int, limit int) int {
	return core.query_fetch_limit(post_filter_count, limit)
}

pub fn ordered_index_scan(base_strategy string) bool {
	return core.query_ordered_index_scan(base_strategy)
}

pub fn reverse_filtered_order(order_column_name string, filter_column_name string, order_desc bool, op FilterOp) bool {
	return core.query_reverse_filtered_order(order_column_name, filter_column_name, order_desc,
		query_filter_op_name(op))
}

pub fn requires_base_row_fetch(has_index bool, select_columns []string, stores_row bool) bool {
	return core.query_requires_base_row_fetch(has_index, select_columns.len, stores_row)
}

pub fn preview_warnings(table_scan bool) []string {
	return core.query_plan_preview_warnings(table_scan)
}

pub fn preview_notes(post_filter_count int, uses_projection_pushdown bool, requires_base_row_fetch bool, supports_reverse bool, supports_top_n bool, has_order bool) []string {
	return core.query_plan_preview_notes(post_filter_count, uses_projection_pushdown,
		requires_base_row_fetch, supports_reverse, supports_top_n, has_order)
}

pub fn field_selector_planning_warning(field_ref string, projection_only bool) string {
	return core.query_field_selector_planning_warning(field_ref, projection_only)
}

pub fn query_page(session Session, mut database Database, request Request) !CursorPage {
	return (query_page_profiled(session, mut database, request)!).page
}

pub fn query_page_profiled(session Session, mut database Database, request Request) !ProfiledCursorPage {
	mut total_sw := time.new_stopwatch()
	if request.general_fts.index_name.len > 0 {
		mut plan_sw := time.new_stopwatch()
		result := query_general_fts_in_session(session, mut database, general_fts_request_from_clause(request.table_name,
			request.general_fts, request.select_columns, request.limit))!
		plan_ms := plan_sw.elapsed().milliseconds()
		return ProfiledCursorPage{
			page:    CursorPage{
				rows:             result.rows.clone()
				plan:             result.plan.as_query_plan()
				cursor:           CursorState{}
				general_fts_hits: result.hits.clone()
			}
			timings: ExecutionTimings{
				plan_ms:       plan_ms
				total_ms:      total_sw.elapsed().milliseconds()
				returned_rows: result.rows.len
			}
		}
	}
	spec := query_spec(session.session.table_spec(request.table_name)!, map[string]ProjectionDef{})
	mut plan_sw := time.new_stopwatch()
	plan := plan_request(spec, request)!
	plan_ms := plan_sw.elapsed().milliseconds()
	mut normalize_sw := time.new_stopwatch()
	normalized := request_with_continuation_token(request, plan)!
	normalize_ms := normalize_sw.elapsed().milliseconds()
	mut fetch_sw := time.new_stopwatch()
	fetched := fetch_query_rows_profiled_query(session.session, mut database.db, spec.schema, plan,
		normalized)!
	fetch_ms := fetch_sw.elapsed().milliseconds()
	schema := spec.schema
	return finalize_profiled_query_page_query(total_sw.elapsed().milliseconds(),
		database.db.root_dir, schema, plan, normalized, plan_ms, normalize_ms, fetch_ms,
		fetched.rows, fetched.begin_tx_ms, fetched.begin_checkout_ms, fetched.begin_tree_load_ms,
		fetched.begin_wrap_ms, fetched.view_ms, fetched.scan_ms, fetched.scan_nodes,
		fetched.scan_leaves, fetched.scan_items)
}

pub fn query_rows(session Session, mut database Database, request Request) !Result {
	return (query_page(session, mut database, request)!).result()
}

pub fn preview_plan_in_transaction(session Transaction, request Request) !Plan {
	if request.general_fts.index_name.len > 0 {
		return error('general fts query requires database session')
	}
	return plan_request(query_spec(session.tx.table_spec(request.table_name)!,
		map[string]ProjectionDef{}), request)
}

pub fn preview_plan_details_in_transaction(session Transaction, request Request) !PlanPreview {
	if request.general_fts.index_name.len > 0 {
		return error('general fts query requires database session')
	}
	plan := preview_plan_in_transaction(session, request)!
	schema := table_schema_from_spec(query_spec(session.tx.table_spec(request.table_name)!,
		map[string]ProjectionDef{}), request.table_name)!
	return build_plan_preview(schema, request, plan)
}

pub fn query_page_in_transaction(session Transaction, request Request) !CursorPage {
	return (query_page_profiled_in_transaction(session, request)!).page
}

pub fn query_page_profiled_in_transaction(session Transaction, request Request) !ProfiledCursorPage {
	if request.general_fts.index_name.len > 0 {
		return error('general fts query requires database session')
	}
	mut total_sw := time.new_stopwatch()
	spec := query_spec(session.tx.table_spec(request.table_name)!, map[string]ProjectionDef{})
	mut plan_sw := time.new_stopwatch()
	plan := plan_request(spec, request)!
	plan_ms := plan_sw.elapsed().milliseconds()
	mut normalize_sw := time.new_stopwatch()
	normalized := request_with_continuation_token(request, plan)!
	normalize_ms := normalize_sw.elapsed().milliseconds()
	mut fetch_sw := time.new_stopwatch()
	fetched := fetch_query_rows_profiled_in_transaction_query(session.tx, spec.schema, plan,
		normalized)!
	fetch_ms := fetch_sw.elapsed().milliseconds()
	schema := spec.schema
	return finalize_profiled_query_page_query(total_sw.elapsed().milliseconds(),
		session.tx.root_dir, schema, plan, normalized, plan_ms, normalize_ms, fetch_ms,
		fetched.rows, fetched.begin_tx_ms, fetched.begin_checkout_ms, fetched.begin_tree_load_ms,
		fetched.begin_wrap_ms, fetched.view_ms, fetched.scan_ms, fetched.scan_nodes,
		fetched.scan_leaves, fetched.scan_items)
}

pub fn query_rows_in_transaction(session Transaction, request Request) !Result {
	return (query_page_in_transaction(session, request)!).result()
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

pub fn encode_continuation_token(table_name string, index_filter Filter, next_primary_key []u8, next_index_value QueryValue) string {
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
		start_index_value: if next_index_value.is_null() {
			''
		} else {
			query_cursor_render_value(next_index_value)
		}
	})
	return base64.encode_str(payload)
}

pub fn encode_continuation_token_for_plan(plan Plan, next_primary_key []u8, next_index_value QueryValue) string {
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
		start_index_value: if next_index_value.is_null() {
			''
		} else {
			query_cursor_render_value(next_index_value)
		}
	})
	return base64.encode_str(payload)
}

pub fn request_with_continuation_token(request Request, plan Plan) !Request {
	if request.continuation_token.len == 0 {
		return request
	}
	token := decode_continuation_token(request.continuation_token)!
	validate_continuation_token_for_plan(token, plan)!
	anchor_filter := query_plan_anchor_filter(plan)
	start_index_value := if anchor_filter.column_name.len > 0 && token.start_index_value.len > 0 {
		decode_query_cursor_value(token.start_index_value, anchor_filter)!
	} else {
		QueryValue.null_value()
	}
	return Request{
		...request
		start_primary_key:     token.start_primary_key.bytes()
		start_index_value:     start_index_value
		has_start_index_value: token.start_index_value.len > 0
	}
}

fn decode_continuation_token(raw string) !QueryContinuationDto {
	if raw.len == 0 {
		return error('empty continuation token')
	}
	return json.decode(QueryContinuationDto, base64.decode_str(raw))
}

fn validate_continuation_token_for_plan(token QueryContinuationDto, plan Plan) ! {
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

fn query_plan_continuation_kind(plan Plan) string {
	if plan.index_filter.column_name.len > 0 {
		return query_filter_op_name(plan.index_filter.op)
	}
	return if plan.order_by.direction == .desc { 'order_desc' } else { 'order_asc' }
}

fn query_plan_anchor_filter(plan Plan) Filter {
	if plan.index_filter.column_name.len > 0 {
		return plan.index_filter
	}
	if plan.order_by.column_name.len > 0 {
		return Filter{
			column_name: plan.order_by.column_name
			op:          .eq
			value:       QueryValue.string_value('')
		}
	}
	return Filter{}
}

fn decode_query_cursor_value(raw string, filter Filter) !QueryValue {
	if raw.len == 0 {
		return QueryValue.null_value()
	}
	value_type := query_value_type_query(filter.value)!
	return match value_type {
		.bool_ {
			if raw == 'true' {
				QueryValue.bool_value(true)
			} else if raw == 'false' {
				QueryValue.bool_value(false)
			} else {
				return error('invalid bool cursor value: ${raw}')
			}
		}
		.i64_ {
			QueryValue.i64_value(raw.i64())
		}
		.bytes_ {
			if !raw.starts_with('hex:') {
				return error('invalid bytes cursor value: ${raw}')
			}
			QueryValue.bytes_value(raw.all_after('hex:').bytes())
		}
		.string_, .enum_, .json_, .datetime_ {
			QueryValue.string_value(raw)
		}
		.markdown_ {
			return error('markdown cursor values are not supported')
		}
	}
}

fn query_cursor_render_value(value QueryValue) string {
	stored := value.value
	return match stored {
		MarkdownRef {
			'markdown:${stored.doc_root_id}'
		}
		NullValue {
			''
		}
		bool {
			if stored {
				'true'
			} else {
				'false'
			}
		}
		i64 {
			stored.str()
		}
		string {
			stored
		}
		[]u8 {
			'hex:${stored.hex()}'
		}
	}
}

pub fn build_plan_preview(schema TableSchema, request Request, plan Plan) !PlanPreview {
	mut warnings := preview_warnings(plan.strategy == 'table_scan')
	notes := preview_notes(plan.post_filter_count, plan_uses_projection_pushdown(plan), requires_base_row_fetch(plan.index_name.len > 0,
		request.select_columns, schema_index_stores_row(schema, plan.index_name)),
		plan_supports_reverse_scan(plan), plan_supports_top_n(plan),
		plan.order_by.column_name.len > 0)
	for filter in request.filters {
		if !filter.is_field_selector() {
			continue
		}
		if schema_has_field_selector_index(schema, filter) {
			continue
		}
		field_ref := '${filter.column_name}.${filter.plugin_name}:${filter.selector}'
		warnings << field_selector_planning_warning(field_ref, schema_has_projection_metric(schema,
			filter))
	}
	return PlanPreview{
		plan:                        plan
		warnings:                    warnings
		notes:                       notes
		default_result_shape:        schema.default_result_shape
		supports_continuation_token: schema.supports_continuation_token
	}
}

fn build_plan_preview_from_spec(spec QuerySpec, request Request, plan Plan) PlanPreview {
	schema := spec.schema
	mut warnings := preview_warnings(plan.strategy == 'table_scan')
	notes := preview_notes(plan.post_filter_count, plan_uses_projection_pushdown(plan), requires_base_row_fetch(plan.index_name.len > 0,
		request.select_columns, spec_index_covers_selection(schema, plan.index_name,
		request.select_columns)), plan_supports_reverse_scan(plan), plan_supports_top_n(plan),
		plan.order_by.column_name.len > 0)
	for filter in request.filters {
		if !filter.is_field_selector() {
			continue
		}
		if spec_has_field_selector_index(schema, filter) {
			continue
		}
		field_ref := '${filter.column_name}.${filter.plugin_name}:${filter.selector}'
		warnings << field_selector_planning_warning(field_ref, spec_has_projection_metric(spec.projections,
			request.table_name, filter))
	}
	return PlanPreview{
		plan:                        plan
		warnings:                    warnings
		notes:                       notes
		default_result_shape:        'page'
		supports_continuation_token: true
	}
}

pub fn plan_uses_projection_pushdown(plan Plan) bool {
	return core.query_plan_uses_projection_pushdown(plan.strategy)
}

pub fn plan_supports_reverse_scan(plan Plan) bool {
	return core.query_plan_supports_reverse_scan(plan.index_name, plan.strategy)
}

pub fn plan_supports_top_n(plan Plan) bool {
	return core.query_plan_supports_top_n(plan.index_name, plan.strategy)
}

fn schema_index_stores_row(schema TableSchema, index_name string) bool {
	for index in schema.indexes {
		if index.name == index_name {
			return index.stores_row
		}
	}
	return true
}

fn spec_index_stores_row(schema TableSchemaDef, index_name string) bool {
	for index in schema.indexes {
		if index.name == index_name {
			return index.stores_row
		}
	}
	return true
}

fn spec_index_covers_selection(schema TableSchemaDef, index_name string, select_columns []string) bool {
	for index in schema.indexes {
		if index.name == index_name {
			return index.can_cover_columns(select_columns)
		}
	}
	return true
}

fn schema_has_field_selector_index(schema TableSchema, filter Filter) bool {
	for selector in schema.field_selectors {
		if selector.column_name != filter.column_name || selector.plugin_name != filter.plugin_name
			|| selector.selector != filter.selector {
			continue
		}
		return selector.index_names.len > 0
	}
	return false
}

fn spec_has_field_selector_index(schema TableSchemaDef, filter Filter) bool {
	for index in schema.indexes {
		meta := index.field_selector_meta() or { continue }
		if index.column != filter.column_name || meta.plugin_name != filter.plugin_name
			|| meta.selector != filter.selector {
			continue
		}
		return true
	}
	return false
}

fn schema_has_projection_metric(schema TableSchema, filter Filter) bool {
	for projection in schema.projection_metrics {
		if projection.column_name != filter.column_name
			|| projection.plugin_name != filter.plugin_name
			|| projection.selector != filter.selector {
			continue
		}
		return true
	}
	return false
}

fn spec_has_projection_metric(projectors map[string]ProjectionDef, table_name string, filter Filter) bool {
	for _, projection in projectors {
		if projection.table_name != table_name || projection.column_name != filter.column_name {
			continue
		}
		meta := projection.field_projection_meta() or { continue }
		if meta.plugin_name != filter.plugin_name || meta.selector != filter.selector {
			continue
		}
		return true
	}
	return false
}

struct QueryFilterResult {
	rows             []QueryRow
	has_more         bool
	next_primary_key []u8
	next_index_value QueryValue = null_query_value()
}

struct QueryFetchedProfile {
	rows               []QueryRow
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

struct QueryIndexFetchSpec {
	fetch_limit       int
	push_projection   bool
	projected_columns []string
	base_strategy     string
}

fn finalize_profiled_query_page_query(total_ms i64, root_dir string, schema TableSchemaDef, plan Plan, request Request, plan_ms i64, normalize_ms i64, fetch_ms i64, fetched_rows_in []QueryRow, fetch_begin_tx_ms i64, fetch_begin_checkout_ms i64, fetch_begin_tree_load_ms i64, fetch_begin_wrap_ms i64, fetch_view_ms i64, fetch_scan_ms i64, fetch_scan_nodes int, fetch_scan_leaves int, fetch_scan_items int) !ProfiledCursorPage {
	mut rows := fetched_rows_in.clone()
	fetched_rows := rows.len
	mut filter_sw := time.new_stopwatch()
	filtered := filter_rows_query(root_dir, schema, rows, request.filters,
		request.start_primary_key, request.start_index_value, request.has_start_index_value,
		plan.index_filter, plan.order_by, request.limit)!
	filter_ms := filter_sw.elapsed().milliseconds()
	rows = filtered.rows.clone()
	filtered_rows := rows.len
	mut project_sw := time.new_stopwatch()
	rows = project_rows_query(rows, request.select_columns)!
	project_ms := project_sw.elapsed().milliseconds()
	mut continuation_sw := time.new_stopwatch()
	cursor := cursor_state_for_plan_query(plan, filtered)
	continuation_ms := continuation_sw.elapsed().milliseconds()
	return ProfiledCursorPage{
		page:    CursorPage{
			rows:   rows
			plan:   plan
			cursor: cursor
		}
		timings: ExecutionTimings{
			plan_ms:                  plan_ms
			normalize_ms:             normalize_ms
			fetch_ms:                 fetch_ms
			fetch_begin_tx_ms:        fetch_begin_tx_ms
			fetch_begin_checkout_ms:  fetch_begin_checkout_ms
			fetch_begin_tree_load_ms: fetch_begin_tree_load_ms
			fetch_begin_wrap_ms:      fetch_begin_wrap_ms
			fetch_view_ms:            fetch_view_ms
			fetch_scan_ms:            fetch_scan_ms
			fetch_scan_nodes:         fetch_scan_nodes
			fetch_scan_leaves:        fetch_scan_leaves
			fetch_scan_items:         fetch_scan_items
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

fn cursor_state_for_plan_query(plan Plan, filtered QueryFilterResult) CursorState {
	return CursorState{
		has_more:                filtered.has_more
		next_primary_key:        filtered.next_primary_key
		next_index_value:        filtered.next_index_value
		next_continuation_token: encode_continuation_token_for_plan(plan,
			filtered.next_primary_key, filtered.next_index_value)
	}
}

fn project_rows_query(rows []QueryRow, select_columns []string) ![]QueryRow {
	if select_columns.len == 0 {
		return rows.clone()
	}
	mut projected := []QueryRow{cap: rows.len}
	for row in rows {
		mut data := QueryRowData{}
		for name in select_columns {
			if row.data.has(name) {
				data.set(name, row.data.get(name)!)
			}
		}
		projected << QueryRow{
			primary_key: row.primary_key.clone()
			data:        data
		}
	}
	return projected
}

fn filter_rows_query(root_dir string, schema TableSchemaDef, rows []QueryRow, filters []Filter, start_primary_key []u8, start_index_value QueryValue, has_start_index_value bool, index_filter Filter, order_by Order, limit int) !QueryFilterResult {
	mut matched := []QueryRow{}
	for row in rows {
		anchor_filter := if index_filter.column_name.len > 0 {
			index_filter
		} else if order_by.column_name.len > 0 {
			Filter{
				column_name: order_by.column_name
				op:          .eq
				value:       start_index_value
			}
		} else {
			Filter{}
		}
		if has_start_index_value && anchor_filter.column_name.len > 0 {
			row_index_value := row_anchor_value_query(root_dir, schema, row, anchor_filter) or {
				null_query_value()
			}
			if should_skip_from_anchor_query(row.primary_key, row_index_value, start_primary_key,
				start_index_value, has_start_index_value, order_by.direction == .desc)
			{
				continue
			}
		} else if start_primary_key.len > 0 && order_by.column_name.len == 0
			&& compare_key_bytes_query(row.primary_key, start_primary_key) <= 0 {
			continue
		}
		if row_matches_all_filters_query(root_dir, schema, row, filters)! {
			if limit > 0 && matched.len >= limit {
				last_anchor_filter := if index_filter.column_name.len > 0 {
					index_filter
				} else if order_by.column_name.len > 0 {
					Filter{
						column_name: order_by.column_name
						op:          .eq
						value:       start_index_value
					}
				} else {
					Filter{}
				}
				last_anchor := if matched.len > 0 && last_anchor_filter.column_name.len > 0 {
					row_anchor_value_query(root_dir, schema, matched[matched.len - 1],
						last_anchor_filter) or { null_query_value() }
				} else {
					null_query_value()
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
			row_anchor_value_query(root_dir, schema, matched[matched.len - 1], if index_filter.column_name.len > 0 {
				index_filter
			} else {
				Filter{
					column_name: order_by.column_name
					op:          .eq
					value:       start_index_value
				}
			}) or { null_query_value() }
		} else {
			null_query_value()
		}
	}
}

fn should_skip_from_anchor_query(primary_key []u8, row_index_value QueryValue, start_primary_key []u8, start_index_value QueryValue, has_start_index_value bool, reverse bool) bool {
	if !has_start_index_value {
		if !reverse {
			return start_primary_key.len > 0
				&& compare_key_bytes_query(primary_key, start_primary_key) <= 0
		}
		return start_primary_key.len > 0
			&& compare_key_bytes_query(primary_key, start_primary_key) >= 0
	}
	value_cmp := compare_query_values(row_index_value, start_index_value)
	if reverse {
		if value_cmp > 0 {
			return true
		}
		if value_cmp < 0 {
			return false
		}
		return start_primary_key.len > 0
			&& compare_key_bytes_query(primary_key, start_primary_key) >= 0
	}
	if value_cmp < 0 {
		return true
	}
	if value_cmp > 0 {
		return false
	}
	return start_primary_key.len > 0 && compare_key_bytes_query(primary_key, start_primary_key) <= 0
}

fn row_anchor_value_query(root_dir string, schema TableSchemaDef, row QueryRow, filter Filter) !QueryValue {
	column := schema.column(filter.column_name)!
	if !row.data.has(column.name) {
		return null_query_value()
	}
	if !filter.is_field_selector() {
		return row.data.get(column.name)!
	}
	return query_row_anchor_field_selector_value(root_dir, column, row, filter)
}

fn row_matches_all_filters_query(root_dir string, schema TableSchemaDef, row QueryRow, filters []Filter) !bool {
	for filter in filters {
		if !row_matches_filter_query(root_dir, schema, row, filter)! {
			return false
		}
	}
	return true
}

fn row_matches_filter_query(root_dir string, schema TableSchemaDef, row QueryRow, filter Filter) !bool {
	column := schema.column(filter.column_name)!
	if filter.is_field_selector() {
		return query_row_matches_field_selector(root_dir, column, row, filter)
	}
	if !row.data.has(column.name) {
		return false
	}
	return value_matches_filter_query(row.data.get(column.name)!, filter)
}

fn value_matches_filter_query(value QueryValue, filter Filter) bool {
	return match filter.op {
		.eq {
			query_values_equal(value, filter.value)
		}
		.prefix {
			query_value_has_prefix(value, filter.value)
		}
		.after {
			compare_query_values(value, filter.value) > 0
		}
		.before {
			compare_query_values(value, filter.value) < 0
		}
		.between {
			compare_query_values(value, filter.value) >= 0
				&& compare_query_values(value, filter.second_value) <= 0
		}
	}
}

fn compare_key_bytes_query(a []u8, b []u8) int {
	common_len := if a.len < b.len { a.len } else { b.len }
	for idx := 0; idx < common_len; idx++ {
		if a[idx] < b[idx] {
			return -1
		}
		if a[idx] > b[idx] {
			return 1
		}
	}
	if a.len < b.len {
		return -1
	}
	if a.len > b.len {
		return 1
	}
	return 0
}

fn query_can_push_projection_query(schema TableSchemaDef, plan Plan, select_columns []string) bool {
	if select_columns.len == 0 || plan.post_filter_count > 0 || plan.index_name.len == 0 {
		return false
	}
	index := plan_index_by_name_query(schema, plan.index_name) or { return false }
	return projection_pushdown_eligible(index.can_cover_columns(select_columns),
		index.is_field_selector(), index.is_fts(), select_columns, plan.post_filter_count)
}

fn plan_index_by_name_query(schema TableSchemaDef, index_name string) ?IndexSchemaDef {
	for index in schema.indexes {
		if index.name == index_name {
			return index
		}
	}
	return none
}

fn query_projected_fetch_columns_query(plan Plan, select_columns []string) []string {
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

fn query_plan_uses_ordered_index_scan_query(fetch QueryIndexFetchSpec) bool {
	return ordered_index_scan(fetch.base_strategy)
}

fn query_plan_uses_reverse_filtered_order_query(plan Plan) bool {
	return reverse_filtered_order(plan.order_by.column_name, plan.index_filter.column_name,
		plan.order_by.direction == .desc, plan.index_filter.op)
}

struct QueryBestFilterIndexMatch {
	index  IndexSchemaDef
	filter Filter
	score  int = -1
}

fn plan_request(spec QuerySpec, request Request) !Plan {
	schema := spec.schema
	validate_request_for_schema(schema, request)!
	if request.order_by.column_name.len > 0 && request.filters.len == 0 {
		return plan_for_order_only_request(schema, request)
	}
	best_match := best_filter_index_match(schema, request.filters, request.select_columns)
	if best_match.score >= 0 {
		return plan_for_indexed_filter_request(request, best_match)
	}
	return table_scan_plan(request)
}

fn validate_request_for_schema(schema TableSchemaDef, request Request) ! {
	if request.table_name.len == 0 {
		return error('query requires table_name')
	}
	if request.filters.len == 0 && request.order_by.column_name.len == 0 {
		return error('query requires at least one filter or order_by')
	}
	for column_name in request.select_columns {
		if !schema.has_column(column_name) {
			return error('query select column not found: ${column_name}')
		}
	}
	for filter in request.filters {
		validate_filter_for_schema(schema, filter)!
	}
	if request.order_by.column_name.len > 0 {
		column := schema.column(request.order_by.column_name)!
		if !core.query_type_supports_order(column.typ.str()) {
			return error('query order_by requires comparable indexed column: ${request.order_by.column_name}')
		}
		_ = best_index_for_order_for_projection(schema, request.order_by, request.select_columns)!
		if request.filters.len > 0 {
			validate_order_with_filters(schema, request)!
		}
	}
}

fn validate_order_with_filters(schema TableSchemaDef, request Request) ! {
	if request.filters.len != 1 {
		return error(core.query_order_with_filters_error(request.filters.len, false, true, true,
			'eq', request.order_by.direction == .desc))
	}
	filter := request.filters[0]
	indexed_filter := best_index_for_filter_for_projection(schema, filter, []string{}) != none
	err_msg := core.query_order_with_filters_error(request.filters.len, filter.is_field_selector(),
		filter.column_name == request.order_by.column_name, indexed_filter,
		query_filter_op_name(filter.op), request.order_by.direction == .desc)
	if err_msg.len > 0 {
		return error(err_msg)
	}
}

fn validate_filter_for_schema(table TableSchemaDef, filter Filter) ! {
	column := table.column(filter.column_name)!
	if filter.is_field_selector() {
		if filter.plugin_name.len == 0 || filter.selector.len == 0 {
			return error('field selector filter requires plugin_name and selector: ${filter.column_name}')
		}
		value_type := query_value_type_query(filter.value)!
		validate_named_field_selector_query(filter.plugin_name, filter.selector, value_type)!
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

fn validate_named_field_selector_query(plugin_name string, selector string, value_type ColumnType) ! {
	match plugin_name {
		'markdown' {
			validate_markdown_index_selector_query(selector, value_type)!
		}
		else {
			return error('unsupported field selector plugin: ${plugin_name}')
		}
	}
}

fn validate_markdown_index_selector_query(selector string, value_type ColumnType) ! {
	parts := selector.split(':')
	match parts[0] {
		'links', 'images', 'code_spans', 'code_blocks', 'blocks', 'headings' {
			if value_type != .i64_ {
				return error('markdown metric selector ${selector} requires i64 index type')
			}
			validate_markdown_projection_selector_query(selector)!
		}
		'code_block_lang', 'link_host', 'image_host', 'heading_text' {
			if value_type != .string_ {
				return error('markdown value selector ${selector} requires string index type')
			}
			if parts[0] == 'heading_text' && parts.len > 2 {
				return error('markdown heading_text selector must be heading_text or heading_text:<level>')
			}
			if parts[0] == 'heading_text' && parts.len == 2 {
				level := parts[1].int()
				if level < 1 || level > 6 {
					return error('markdown heading_text selector level must be between 1 and 6')
				}
			}
			if parts[0] != 'heading_text' && parts.len > 1 {
				return error('markdown value selector ${selector} does not accept a qualifier')
			}
		}
		'fts' {
			if value_type != .string_ {
				return error('markdown value selector ${selector} requires string index type')
			}
			if parts.len > 2 {
				return error('markdown fts selector must be fts or fts:<scope>')
			}
			if parts.len == 2 && parts[1] !in ['heading', 'paragraph', 'code_block', 'list_item'] {
				return error('unsupported markdown fts scope selector: ${parts[1]}')
			}
		}
		else {
			return error('unsupported markdown index selector: ${selector}')
		}
	}
}

fn validate_markdown_projection_selector_query(selector string) ! {
	parts := selector.split(':')
	match parts[0] {
		'blocks' {
			if parts.len > 1 {
				return error('markdown selector blocks does not accept a qualifier')
			}
		}
		'headings' {
			if parts.len > 2 {
				return error('markdown heading selector must be headings or headings:<level>')
			}
			if parts.len == 2 {
				level := parts[1].int()
				if level < 1 || level > 6 {
					return error('markdown heading selector level must be between 1 and 6')
				}
			}
		}
		'links', 'images', 'code_spans', 'code_blocks' {
			if parts[0] != 'code_blocks' && parts.len > 1 {
				return error('markdown selector ${parts[0]} does not accept a qualifier')
			}
			if parts[0] == 'code_blocks' && parts.len > 2 {
				return error('markdown code block selector must be code_blocks or code_blocks:<lang>')
			}
		}
		else {
			return error('unsupported markdown projection selector: ${selector}')
		}
	}
}

fn best_index_for_order_for_projection(schema TableSchemaDef, order Order, select_columns []string) !IndexSchemaDef {
	mut best := IndexSchemaDef{}
	mut best_score := -1
	for index in schema.indexes {
		if !core.query_order_index_eligible(index.is_field_selector(), index.is_json_path(),
			index.is_fts(), index.column == order.column_name) {
			continue
		}
		score := core.query_order_index_score(index.can_cover_columns(select_columns),
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

fn best_index_for_filter_for_projection(schema TableSchemaDef, filter Filter, select_columns []string) ?IndexSchemaDef {
	mut best := IndexSchemaDef{}
	mut best_score := -1
	for index in schema.indexes {
		if !index_matches_filter(schema, index, filter) {
			continue
		}
		score := core.query_index_score(query_filter_op_name(filter.op),
			index.can_cover_columns(select_columns), filter.is_field_selector(), select_columns.len)
		if score > best_score {
			best = index
			best_score = score
		}
	}
	return if best_score >= 0 { best } else { none }
}

fn best_filter_index_match(schema TableSchemaDef, filters []Filter, select_columns []string) QueryBestFilterIndexMatch {
	mut best := QueryBestFilterIndexMatch{}
	for filter in filters {
		index := best_index_for_filter_for_projection(schema, filter, select_columns) or {
			continue
		}
		score := core.query_index_score(query_filter_op_name(filter.op),
			index.can_cover_columns(select_columns), filter.is_field_selector(), select_columns.len)
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

fn index_matches_filter(table TableSchemaDef, index IndexSchemaDef, filter Filter) bool {
	column := index.value_column(table) or { return false }
	return core.query_filter_index_eligible(filter.is_field_selector(), index.is_field_selector(),
		index.is_json_path(), index.is_fts(), index.column == filter.column_name,
		index.field_selector_plugin() == filter.plugin_name,
		index.field_selector() == filter.selector, core.query_type_supports_filter_op(column.typ.str(),
		query_filter_op_name(filter.op)))
}

fn plan_for_order_only_request(schema TableSchemaDef, request Request) !Plan {
	order_index := best_index_for_order_for_projection(schema, request.order_by,
		request.select_columns)!
	projected := projection_pushdown_eligible(order_index.can_cover_columns(request.select_columns),
		order_index.is_field_selector(), order_index.is_fts(), request.select_columns, 0)
	return Plan{
		table_name:        request.table_name
		strategy:          core.query_plan_order_strategy_name(request.order_by.direction == .desc,
			projected)
		index_name:        order_index.name
		index_filter:      Filter{}
		order_by:          request.order_by
		post_filters:      []Filter{}
		post_filter_count: 0
		limit:             request.limit
	}
}

fn plan_for_indexed_filter_request(request Request, best_match QueryBestFilterIndexMatch) Plan {
	post_filters := post_filters_for_request(request.filters, best_match.filter)
	projected := projection_pushdown_eligible(best_match.index.can_cover_columns(request.select_columns),
		best_match.index.is_field_selector(), best_match.index.is_fts(), request.select_columns,
		post_filters.len)
	return Plan{
		table_name:        request.table_name
		strategy:          core.query_plan_filter_order_strategy_name(query_filter_op_name(best_match.filter.op),
			request.order_by.column_name.len > 0
			&& request.order_by.column_name == best_match.filter.column_name,
			request.order_by.direction == .desc, projected)
		index_name:        best_match.index.name
		index_filter:      best_match.filter
		order_by:          request.order_by
		post_filters:      post_filters
		post_filter_count: post_filters.len
		limit:             request.limit
	}
}

fn table_scan_plan(request Request) Plan {
	return Plan{
		table_name:        request.table_name
		strategy:          'table_scan'
		index_name:        ''
		index_filter:      Filter{}
		post_filters:      request.filters.clone()
		post_filter_count: request.filters.len
		limit:             request.limit
	}
}

fn post_filters_for_request(filters []Filter, chosen Filter) []Filter {
	mut post_filters := []Filter{}
	mut skipped := false
	for filter in filters {
		if !skipped && filters_equal(filter, chosen) {
			skipped = true
			continue
		}
		post_filters << filter
	}
	return post_filters
}

fn filters_equal(left Filter, right Filter) bool {
	return left.column_name == right.column_name && left.plugin_name == right.plugin_name
		&& left.selector == right.selector && left.op == right.op
		&& query_values_equal(left.value, right.value)
		&& left.has_second_value == right.has_second_value
		&& (!left.has_second_value || query_values_equal(left.second_value, right.second_value))
}
