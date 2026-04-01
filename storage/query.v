module storage

import encoding.base64
import json

pub enum QueryFilterOp {
	eq
	prefix
	after
	before
	between
}

pub struct QueryFilter {
pub:
	column_name string
	plugin_name string
	selector    string
	op          QueryFilterOp
	value       ColumnValue
	second_value ColumnValue = NullValue{}
	has_second_value bool
}

pub struct QueryRequest {
pub:
	table_name     string
	filters        []QueryFilter
	select_columns []string
	start_primary_key []u8
	start_index_value ColumnValue = NullValue{}
	has_start_index_value bool
	continuation_token string
	limit          int
}

pub struct QueryPlan {
pub:
	table_name        string
	strategy          string
	index_name        string
	index_filter      QueryFilter
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
		strategy: preview.plan.strategy
		index_name: preview.plan.index_name
		warnings: preview.warnings.clone()
		notes: preview.notes.clone()
		default_result_shape: preview.default_result_shape
		supports_continuation_token: preview.supports_continuation_token
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
	rows   []TypedSchemaRow
	plan   QueryPlan
	cursor QueryCursorState
}

// QueryResult is the compatibility query envelope that duplicates cursor fields
// at the top level. Prefer QueryCursorPage for new paged-read call sites.
pub struct QueryResult {
pub:
	rows             []TypedSchemaRow
	plan             QueryPlan
	cursor           QueryCursorState
	has_more         bool
	next_primary_key []u8
	next_index_value ColumnValue = NullValue{}
	next_continuation_token string
}

struct QueryContinuationDto {
	table_name        string
	column_name       string
	plugin_name       string
	selector          string
	query_kind        string
	start_primary_key string
	start_index_value string
}

pub fn QueryFilter.eq(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op: .eq
		value: clone_column_value(value)
	}
}

pub fn QueryFilter.prefix(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op: .prefix
		value: clone_column_value(value)
	}
}

pub fn QueryFilter.field_eq(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector: selector
		op: .eq
		value: clone_column_value(value)
	}
}

pub fn QueryFilter.field_prefix(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector: selector
		op: .prefix
		value: clone_column_value(value)
	}
}

pub fn QueryFilter.after(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op: .after
		value: clone_column_value(value)
	}
}

pub fn QueryFilter.before(column_name string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op: .before
		value: clone_column_value(value)
	}
}

pub fn QueryFilter.between(column_name string, start_value ColumnValue, end_value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		op: .between
		value: clone_column_value(start_value)
		second_value: clone_column_value(end_value)
		has_second_value: true
	}
}

pub fn QueryFilter.field_after(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector: selector
		op: .after
		value: clone_column_value(value)
	}
}

pub fn QueryFilter.field_before(column_name string, plugin_name string, selector string, value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector: selector
		op: .before
		value: clone_column_value(value)
	}
}

pub fn QueryFilter.field_between(column_name string, plugin_name string, selector string, start_value ColumnValue, end_value ColumnValue) QueryFilter {
	return QueryFilter{
		column_name: column_name
		plugin_name: plugin_name
		selector: selector
		op: .between
		value: clone_column_value(start_value)
		second_value: clone_column_value(end_value)
		has_second_value: true
	}
}

pub fn (filter QueryFilter) is_field_selector() bool {
	return filter.plugin_name.len > 0 || filter.selector.len > 0
}

pub fn (database PersistentDatabase) preview_query_plan(request QueryRequest) !QueryPlan {
	spec := database.table_spec(request.table_name)!
	return plan_query_request(spec, request)
}

pub fn (database PersistentDatabase) preview_query_plan_details(request QueryRequest) !QueryPlanPreview {
	spec := database.table_spec(request.table_name)!
	plan := plan_query_request(spec, request)!
	return build_query_plan_preview(spec, database.projectors, request, plan, false)
}

pub fn (session DatabaseSession) preview_query_plan(request QueryRequest) !QueryPlan {
	spec := session.table_spec(request.table_name)!
	return plan_query_request(spec, request)
}

pub fn (session DatabaseSession) query_rows(mut db PersistentDatabase, request QueryRequest) !QueryResult {
	return (session.query_page(mut db, request)!).result()
}

// query_page is the preferred public query entrypoint for paged reads.
// query_rows remains as a compatibility wrapper around the cursor-page result.
pub fn (session DatabaseSession) query_page(mut db PersistentDatabase, request QueryRequest) !QueryCursorPage {
	spec := session.table_spec(request.table_name)!
	plan := plan_query_request(spec, request)!
	normalized := query_request_with_continuation_token(request, plan)!
	mut rows := if plan.index_name.len > 0 {
		query_rows_from_database_index(session, mut db, spec, plan)!
	} else {
		query_rows_from_database_scan(session, mut db, spec, plan)!
	}
	filtered := filter_query_rows(db.root_dir, spec.table, rows, normalized.filters, normalized.start_primary_key,
		normalized.start_index_value, normalized.has_start_index_value, plan.index_filter, normalized.limit)!
	rows = filtered.rows.clone()
	rows = project_query_rows(rows, normalized.select_columns)!
	cursor := QueryCursorState{
		has_more: filtered.has_more
		next_primary_key: filtered.next_primary_key
		next_index_value: filtered.next_index_value
		next_continuation_token: encode_query_continuation_token(plan.table_name, plan.index_filter,
			filtered.next_primary_key, filtered.next_index_value)
	}
	return QueryCursorPage{
		rows: rows
		plan: plan
		cursor: cursor
	}
}

pub fn (session TransactionSession) preview_query_plan(request QueryRequest) !QueryPlan {
	spec := session.working_set.transaction().specs[request.table_name] or {
		return error('typed table not registered: ${request.table_name}')
	}
	return plan_query_request(spec, request)
}

pub fn (session TransactionSession) preview_query_plan_details(request QueryRequest) !QueryPlanPreview {
	spec := session.working_set.transaction().specs[request.table_name] or {
		return error('typed table not registered: ${request.table_name}')
	}
	plan := plan_query_request(spec, request)!
	return build_query_plan_preview(spec, map[string]AggregateProjectionDef{}, request, plan, true)
}

pub fn (session TransactionSession) query_rows(request QueryRequest) !QueryResult {
	return (session.query_page(request)!).result()
}

// query_page is the preferred public query entrypoint for paged reads.
// query_rows remains as a compatibility wrapper around the cursor-page result.
pub fn (session TransactionSession) query_page(request QueryRequest) !QueryCursorPage {
	spec := session.working_set.transaction().specs[request.table_name] or {
		return error('typed table not registered: ${request.table_name}')
	}
	plan := plan_query_request(spec, request)!
	normalized := query_request_with_continuation_token(request, plan)!
	mut rows := if plan.index_name.len > 0 {
		query_rows_from_transaction_index(session, spec, plan)!
	} else {
		query_rows_from_transaction_scan(session, spec, plan)!
	}
	filtered := filter_query_rows(session.root_dir, spec.table, rows, normalized.filters,
		normalized.start_primary_key, normalized.start_index_value, normalized.has_start_index_value,
		plan.index_filter, normalized.limit)!
	rows = filtered.rows.clone()
	rows = project_query_rows(rows, normalized.select_columns)!
	cursor := QueryCursorState{
		has_more: filtered.has_more
		next_primary_key: filtered.next_primary_key
		next_index_value: filtered.next_index_value
		next_continuation_token: encode_query_continuation_token(plan.table_name, plan.index_filter,
			filtered.next_primary_key, filtered.next_index_value)
	}
	return QueryCursorPage{
		rows: rows
		plan: plan
		cursor: cursor
	}
}

pub fn (result QueryResult) cursor_page() QueryCursorPage {
	return QueryCursorPage{
		rows: result.rows.clone()
		plan: result.plan
		cursor: result.cursor
	}
}

pub fn (result QueryResult) page() QueryCursorPage {
	return result.cursor_page()
}

pub fn (page QueryCursorPage) result() QueryResult {
	return QueryResult{
		rows: page.rows.clone()
		plan: page.plan
		cursor: page.cursor
		has_more: page.cursor.has_more
		next_primary_key: page.cursor.next_primary_key
		next_index_value: page.cursor.next_index_value
		next_continuation_token: page.cursor.next_continuation_token
	}
}

pub fn encode_query_continuation_token(table_name string, index_filter QueryFilter, next_primary_key []u8, next_index_value ColumnValue) string {
	if next_primary_key.len == 0 {
		return ''
	}
	payload := json.encode(QueryContinuationDto{
		table_name: table_name
		column_name: index_filter.column_name
		plugin_name: index_filter.plugin_name
		selector: index_filter.selector
		query_kind: query_filter_op_name(index_filter.op)
		start_primary_key: next_primary_key.bytestr()
		start_index_value: if next_index_value is NullValue { '' } else { query_cursor_render_value(next_index_value) }
	})
	return base64.encode_str(payload)
}

fn query_request_with_continuation_token(request QueryRequest, plan QueryPlan) !QueryRequest {
	if request.continuation_token.len == 0 {
		return request
	}
	token := decode_query_continuation_token(request.continuation_token)!
	validate_query_continuation_token(token, plan.table_name, plan.index_filter)!
	start_index_value := decode_query_cursor_value(token.start_index_value, plan.index_filter)!
	return QueryRequest{
		...request
		start_primary_key: token.start_primary_key.bytes()
		start_index_value: start_index_value
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

fn query_filter_op_name(op QueryFilterOp) string {
	return match op {
		.eq { 'eq' }
		.prefix { 'prefix' }
		.after { 'after' }
		.before { 'before' }
		.between { 'between' }
	}
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
		.i64_ { ColumnValue(raw.i64()) }
		.bytes_ {
			if !raw.starts_with('hex:') {
				return error('invalid bytes cursor value: ${raw}')
			}
			ColumnValue(raw.all_after('hex:').bytes())
		}
		.string_, .enum_, .json_, .datetime_ { ColumnValue(raw) }
		.markdown_ { return error('markdown cursor values are not supported') }
	}
}

fn query_cursor_render_value(value ColumnValue) string {
	return match value {
		MarkdownRef { 'markdown:${value.doc_root_id}' }
		NullValue { '' }
		bool { if value { 'true' } else { 'false' } }
		i64 { value.str() }
		string { value }
		[]u8 { 'hex:${value.hex()}' }
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
	mut best_index := SchemaIndexDef{}
	mut best_filter := QueryFilter{}
	mut best_score := -1
	for filter in request.filters {
		index := best_index_for_filter(spec, filter) or { continue }
		score := query_index_score(spec, index, filter, request.select_columns)
		if score > best_score {
			best_index = index
			best_filter = filter
			best_score = score
		}
	}
	if best_score >= 0 {
		post_filters := query_post_filters(request.filters, best_filter)
		return QueryPlan{
			table_name: request.table_name
			strategy: query_plan_strategy_name(best_filter.op)
			index_name: best_index.name
			index_filter: best_filter
			post_filters: post_filters
			post_filter_count: post_filters.len
			limit: request.limit
		}
	}
	return QueryPlan{
		table_name: request.table_name
		strategy: 'table_scan'
		index_name: ''
		index_filter: QueryFilter{}
		post_filters: request.filters.clone()
		post_filter_count: request.filters.len
		limit: request.limit
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

fn query_plan_strategy_name(op QueryFilterOp) string {
	return match op {
		.eq { 'index_exact' }
		.prefix { 'index_prefix' }
		.after { 'index_after' }
		.before { 'index_before' }
		.between { 'index_between' }
	}
}

fn build_query_plan_preview(spec TypedTableSpec, projectors map[string]AggregateProjectionDef, request QueryRequest, plan QueryPlan, transaction_local bool) QueryPlanPreview {
	mut warnings := []string{}
	mut notes := []string{}

	if plan.strategy == 'table_scan' {
		warnings << 'No eligible index matched; planner will fall back to table scan.'
	}
	if plan.post_filter_count > 0 {
		notes << 'Additional filters will run as post-filters after the primary planner step.'
	}
	if transaction_local && plan.strategy == 'index_prefix' {
		notes << 'Transaction-local prefix queries may degrade to table scan during execution.'
	}
	if plan.index_name.len > 0 && request.select_columns.len > 0 {
		for index in spec.indexes {
			if index.name == plan.index_name && !index.stores_row {
				notes << 'Selected columns may require base-row fetches because the chosen index is non-covering.'
				break
			}
		}
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
		plan: plan
		warnings: warnings
		notes: notes
		default_result_shape: 'page'
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
	if request.filters.len == 0 {
		return error('query requires at least one filter')
	}
	for column_name in request.select_columns {
		if !spec.table.has_column(column_name) {
			return error('query select column not found: ${column_name}')
		}
	}
	for filter in request.filters {
		validate_query_filter(spec.table, filter)!
	}
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
			else { return error('query range filters require comparable column: ${filter.column_name}') }
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
	for index in spec.indexes {
		if !query_index_matches_filter(spec.table, index, filter) {
			continue
		}
		return index
	}
	return none
}

fn query_index_matches_filter(table TableDef, index SchemaIndexDef, filter QueryFilter) bool {
	if filter.is_field_selector() {
		return index.is_field_selector() && index.column == filter.column_name
			&& index.field_selector_plugin() == filter.plugin_name
			&& index.field_selector() == filter.selector
	}
	if index.is_field_selector() || index.is_json_path() {
		return false
	}
	if index.column != filter.column_name {
		return false
	}
	column := index.value_column(table) or { return false }
	return match filter.op {
		.prefix { match column.typ {
			.string_, .bytes_, .enum_, .datetime_ { true }
			else { false }
		} }
		.after, .before, .between { match column.typ {
			.i64_, .string_, .bytes_, .enum_, .datetime_ { true }
			else { false }
		} }
		.eq { true }
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

fn query_rows_from_database_index(session DatabaseSession, mut db PersistentDatabase, spec TypedTableSpec, plan QueryPlan) ![]TypedSchemaRow {
	fetch_limit := if plan.post_filter_count > 0 {
		0
	} else if plan.limit > 0 {
		plan.limit + 1
	} else {
		0
	}
	return match plan.index_filter.op {
		.prefix {
			session.lookup_index_prefix(mut db, plan.table_name, plan.index_name, plan.index_filter.value,
				fetch_limit)!
		}
		.after {
			session.lookup_index_after(mut db, plan.table_name, plan.index_name, plan.index_filter.value,
				fetch_limit)!
		}
		.before {
			session.lookup_index_before(mut db, plan.table_name, plan.index_name, plan.index_filter.value,
				fetch_limit)!
		}
		.between {
			session.lookup_index_between(mut db, plan.table_name, plan.index_name, plan.index_filter.value,
				plan.index_filter.second_value, fetch_limit)!
		}
		.eq {
			session.lookup_index(mut db, plan.table_name, plan.index_name, plan.index_filter.value,
				fetch_limit)!
		}
	}
}

fn query_rows_from_database_scan(session DatabaseSession, mut db PersistentDatabase, spec TypedTableSpec, plan QueryPlan) ![]TypedSchemaRow {
	return session.scan_table(mut db, plan.table_name, 0)
}

fn query_rows_from_transaction_index(session TransactionSession, spec TypedTableSpec, plan QueryPlan) ![]TypedSchemaRow {
	fetch_limit := if plan.post_filter_count > 0 {
		0
	} else if plan.limit > 0 {
		plan.limit + 1
	} else {
		0
	}
	return match plan.index_filter.op {
		.prefix {
			session.scan_table(plan.table_name, 0)!
		}
		.after {
			session.lookup_index_after(plan.table_name, plan.index_name, plan.index_filter.value,
				fetch_limit)!
		}
		.before {
			session.lookup_index_before(plan.table_name, plan.index_name, plan.index_filter.value,
				fetch_limit)!
		}
		.between {
			session.lookup_index_between(plan.table_name, plan.index_name, plan.index_filter.value,
				plan.index_filter.second_value, fetch_limit)!
		}
		.eq {
			session.lookup_index(plan.table_name, plan.index_name, plan.index_filter.value, fetch_limit)!
		}
	}
}

fn query_rows_from_transaction_scan(session TransactionSession, spec TypedTableSpec, plan QueryPlan) ![]TypedSchemaRow {
	return session.scan_table(plan.table_name, 0)
}

fn filter_query_rows(root_dir string, table TableDef, rows []TypedSchemaRow, filters []QueryFilter, start_primary_key []u8, start_index_value ColumnValue, has_start_index_value bool, index_filter QueryFilter, limit int) !QueryFilterResult {
	mut matched := []TypedSchemaRow{}
	for row in rows {
		if has_start_index_value && index_filter.column_name.len > 0 {
			row_index_value := query_row_anchor_value(root_dir, table, row, index_filter) or { NullValue{} }
			if query_should_skip_from_anchor(row.primary_key, row_index_value, start_primary_key,
				start_index_value, has_start_index_value) {
				continue
			}
		} else if start_primary_key.len > 0 && compare_key_bytes(row.primary_key, start_primary_key) <= 0 {
			continue
		}
		if query_row_matches_all_filters(root_dir, table, row, filters)! {
			if limit > 0 && matched.len >= limit {
				last_anchor := if matched.len > 0 && index_filter.column_name.len > 0 {
					query_row_anchor_value(root_dir, table, matched[matched.len - 1], index_filter) or {
						NullValue{}
					}
				} else {
					NullValue{}
				}
				return QueryFilterResult{
					rows: matched
					has_more: true
					next_primary_key: matched[matched.len - 1].primary_key.clone()
					next_index_value: last_anchor
				}
			}
			matched << row
		}
	}
	return QueryFilterResult{
		rows: matched
		has_more: false
		next_primary_key: if matched.len > 0 { matched[matched.len - 1].primary_key.clone() } else { []u8{} }
		next_index_value: if matched.len > 0 && index_filter.column_name.len > 0 {
			query_row_anchor_value(root_dir, table, matched[matched.len - 1], index_filter) or { NullValue{} }
		} else {
			NullValue{}
		}
	}
}

fn query_should_skip_from_anchor(primary_key []u8, row_index_value ColumnValue, start_primary_key []u8, start_index_value ColumnValue, has_start_index_value bool) bool {
	if !has_start_index_value {
		return start_primary_key.len > 0 && compare_key_bytes(primary_key, start_primary_key) <= 0
	}
	value_cmp := query_compare_column_values(row_index_value, start_index_value)
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
	values := expand_field_selector_index_values(root_dir, column, row.data.get(column.name)!, index)!
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
		.eq { column_values_equal(value, filter.value) }
		.prefix { query_value_has_prefix(value, filter.value) }
		.after { query_compare_column_values(value, filter.value) > 0 }
		.before { query_compare_column_values(value, filter.value) < 0 }
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
		else { false }
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
				else { 0 }
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
				else { 0 }
			}
		}
		string {
			match right {
				string { if left < right { -1 } else if left > right { 1 } else { 0 } }
				else { 0 }
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
				MarkdownRef { if left.doc_root_id < right.doc_root_id { -1 } else if left.doc_root_id > right.doc_root_id { 1 } else { 0 } }
				else { 0 }
			}
		}
		NullValue { 0 }
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
			data: data
		}
	}
	return projected
}
