module query

import storage

pub enum ColumnType {
	bool_
	i64_
	string_
	bytes_
	enum_
	json_
	datetime_
	markdown_
}

pub enum ColumnAggregate {
	none
	sum
}

pub enum ProjectionCostHint {
	low
	medium
	high
}

fn query_column_type(typ storage.ColumnType) ColumnType {
	return match typ {
		.bool_ { .bool_ }
		.i64_ { .i64_ }
		.string_ { .string_ }
		.bytes_ { .bytes_ }
		.enum_ { .enum_ }
		.json_ { .json_ }
		.datetime_ { .datetime_ }
		.markdown_ { .markdown_ }
	}
}

fn storage_column_type(typ ColumnType) storage.ColumnType {
	return match typ {
		.bool_ { .bool_ }
		.i64_ { .i64_ }
		.string_ { .string_ }
		.bytes_ { .bytes_ }
		.enum_ { .enum_ }
		.json_ { .json_ }
		.datetime_ { .datetime_ }
		.markdown_ { .markdown_ }
	}
}

fn query_column_aggregate(aggregate storage.ColumnAggregate) ColumnAggregate {
	return match aggregate {
		.none { .none }
		.sum { .sum }
	}
}

fn storage_column_aggregate(aggregate ColumnAggregate) storage.ColumnAggregate {
	return match aggregate {
		.none { .none }
		.sum { .sum }
	}
}

fn query_projection_cost_hint(cost_hint storage.AggregateProjectionCostHint) ProjectionCostHint {
	return match cost_hint {
		.low { .low }
		.medium { .medium }
		.high { .high }
	}
}

fn storage_projection_cost_hint(cost_hint ProjectionCostHint) storage.AggregateProjectionCostHint {
	return match cost_hint {
		.low { .low }
		.medium { .medium }
		.high { .high }
	}
}

pub enum FilterOp {
	eq
	prefix
	after
	before
	between
}

pub struct Filter {
pub:
	column_name      string
	plugin_name      string
	selector         string
	op               FilterOp
	value            QueryValue
	second_value     QueryValue = QueryValue{
		value: NullValue{}
	}
	has_second_value bool
}

pub fn Filter.eq(column_name string, value QueryValue) Filter {
	return Filter{
		column_name: column_name
		op:          .eq
		value:       value
	}
}

pub fn Filter.prefix(column_name string, value QueryValue) Filter {
	return Filter{
		column_name: column_name
		op:          .prefix
		value:       value
	}
}

pub fn Filter.after(column_name string, value QueryValue) Filter {
	return Filter{
		column_name: column_name
		op:          .after
		value:       value
	}
}

pub fn Filter.before(column_name string, value QueryValue) Filter {
	return Filter{
		column_name: column_name
		op:          .before
		value:       value
	}
}

pub fn Filter.between(column_name string, start_value QueryValue, end_value QueryValue) Filter {
	return Filter{
		column_name:      column_name
		op:               .between
		value:            start_value
		second_value:     end_value
		has_second_value: true
	}
}

pub fn Filter.field_eq(column_name string, plugin_name string, selector string, value QueryValue) Filter {
	return Filter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .eq
		value:       value
	}
}

pub fn Filter.field_prefix(column_name string, plugin_name string, selector string, value QueryValue) Filter {
	return Filter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .prefix
		value:       value
	}
}

pub fn Filter.field_after(column_name string, plugin_name string, selector string, value QueryValue) Filter {
	return Filter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .after
		value:       value
	}
}

pub fn Filter.field_before(column_name string, plugin_name string, selector string, value QueryValue) Filter {
	return Filter{
		column_name: column_name
		plugin_name: plugin_name
		selector:    selector
		op:          .before
		value:       value
	}
}

pub fn Filter.field_between(column_name string, plugin_name string, selector string, start_value QueryValue, end_value QueryValue) Filter {
	return Filter{
		column_name:      column_name
		plugin_name:      plugin_name
		selector:         selector
		op:               .between
		value:            start_value
		second_value:     end_value
		has_second_value: true
	}
}

pub fn (filter Filter) is_field_selector() bool {
	return filter.plugin_name.len > 0 || filter.selector.len > 0
}

pub enum OrderDirection {
	asc
	desc
}

pub struct Order {
pub:
	column_name string
	direction   OrderDirection = .asc
}

pub struct GeneralFtsClause {
pub:
	index_name string
	kind       FtsKind
	terms      []string
}

pub struct QueryValue {
	value QueryScalarValue
}

type QueryScalarValue = MarkdownRef | NullValue | []u8 | bool | i64 | string

fn query_value_from_storage(value storage.ColumnValue) QueryValue {
	return QueryValue{
		value: query_scalar_value_from_storage(value)
	}
}

fn storage_value_query(value QueryValue) storage.ColumnValue {
	return storage_value_from_query_scalar(value.value)
}

fn null_query_value() QueryValue {
	return QueryValue{
		value: NullValue{}
	}
}

pub fn QueryValue.null_value() QueryValue {
	return null_query_value()
}

pub fn QueryValue.bool_value(value bool) QueryValue {
	return query_value_from_storage(value)
}

pub fn QueryValue.i64_value(value i64) QueryValue {
	return query_value_from_storage(value)
}

pub fn QueryValue.string_value(value string) QueryValue {
	return query_value_from_storage(value)
}

pub fn QueryValue.bytes_value(value []u8) QueryValue {
	return query_value_from_storage(value)
}

pub fn QueryValue.markdown_ref(value MarkdownRef) QueryValue {
	return query_value_from_storage(storage_markdown_ref_query(value))
}

fn (value QueryValue) storage_value() storage.ColumnValue {
	return storage_value_query(value)
}

pub fn (value QueryValue) is_null() bool {
	return value.value is NullValue
}

pub fn (value QueryValue) as_bool() !bool {
	stored := value.storage_value()
	return match stored {
		bool { stored }
		else { return error('query value is not bool') }
	}
}

pub fn (value QueryValue) as_i64() !i64 {
	stored := value.storage_value()
	return match stored {
		i64 { stored }
		else { return error('query value is not i64') }
	}
}

pub fn (value QueryValue) as_string() !string {
	stored := value.storage_value()
	return match stored {
		string { stored }
		else { return error('query value is not string') }
	}
}

pub fn (value QueryValue) as_bytes() ![]u8 {
	stored := value.storage_value()
	return match stored {
		[]u8 { stored.clone() }
		else { return error('query value is not bytes') }
	}
}

pub fn (value QueryValue) as_markdown_ref() !MarkdownRef {
	stored := value.storage_value()
	return match stored {
		storage.MarkdownRef { query_markdown_ref_from_storage(stored) }
		else { return error('query value is not markdown ref') }
	}
}

pub fn (value QueryValue) display_string() string {
	stored := value.storage_value()
	return match stored {
		storage.MarkdownRef {
			'md:${stored.doc_root_id}'
		}
		storage.NullValue {
			'null'
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
			'hex:' + stored.hex()
		}
	}
}

fn query_value_type_query(value QueryValue) !ColumnType {
	return query_scalar_value_type(value.value)
}

fn query_values_equal(left QueryValue, right QueryValue) bool {
	return query_scalar_values_equal(left.value, right.value)
}

fn query_value_has_prefix(value QueryValue, prefix QueryValue) bool {
	return query_scalar_value_has_prefix(value.value, prefix.value)
}

fn compare_query_values(left QueryValue, right QueryValue) int {
	return compare_query_scalar_values(left.value, right.value)
}

fn query_values_use_same_kind(left QueryValue, right QueryValue) bool {
	return query_scalar_values_use_same_kind(left.value, right.value)
}

fn query_scalar_values_equal(left QueryScalarValue, right QueryScalarValue) bool {
	return match left {
		bool {
			match right {
				bool { left == right }
				else { false }
			}
		}
		i64 {
			match right {
				i64 { left == right }
				else { false }
			}
		}
		string {
			match right {
				string { left == right }
				else { false }
			}
		}
		[]u8 {
			match right {
				[]u8 { left == right }
				else { false }
			}
		}
		MarkdownRef {
			match right {
				MarkdownRef { left.doc_root_id == right.doc_root_id }
				else { false }
			}
		}
		NullValue {
			right is NullValue
		}
	}
}

fn query_scalar_value_has_prefix(value QueryScalarValue, prefix QueryScalarValue) bool {
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

fn compare_query_scalar_values(left QueryScalarValue, right QueryScalarValue) int {
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
				[]u8 { compare_key_bytes_query_values(left, right) }
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

fn compare_key_bytes_query_values(a []u8, b []u8) int {
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

fn query_scalar_values_use_same_kind(left QueryScalarValue, right QueryScalarValue) bool {
	return match left {
		bool { right is bool }
		i64 { right is i64 }
		string { right is string }
		[]u8 { right is []u8 }
		MarkdownRef { right is MarkdownRef }
		NullValue { right is NullValue }
	}
}

fn query_scalar_value_type(value QueryScalarValue) !ColumnType {
	return match value {
		MarkdownRef { .markdown_ }
		NullValue { return error('query filters do not support null values') }
		bool { .bool_ }
		i64 { .i64_ }
		string { .string_ }
		[]u8 { .bytes_ }
	}
}

pub struct Request {
pub:
	table_name            string
	filters               []Filter
	general_fts           GeneralFtsClause
	order_by              Order
	select_columns        []string
	start_primary_key     []u8
	start_index_value     QueryValue = QueryValue{
		value: NullValue{}
	}
	has_start_index_value bool
	continuation_token    string
	limit                 int
}

pub struct Plan {
pub:
	table_name        string
	strategy          string
	index_name        string
	index_filter      Filter
	order_by          Order
	post_filters      []Filter
	post_filter_count int
	limit             int
}

pub struct PlanPreview {
pub:
	plan                        Plan
	warnings                    []string
	notes                       []string
	default_result_shape        string
	supports_continuation_token bool
}

pub struct CursorState {
pub:
	has_more                bool
	next_primary_key        []u8
	next_index_value        QueryValue = QueryValue{
		value: NullValue{}
	}
	next_continuation_token string
}

pub struct QueryRowData {
mut:
	values map[string]QueryScalarValue
}

fn query_row_data_from_storage(data storage.TypedRowData) QueryRowData {
	mut values := map[string]QueryScalarValue{}
	for name, value in data.fields() {
		values[name] = query_scalar_value_from_storage(value)
	}
	return QueryRowData{
		values: values
	}
}

fn storage_row_data_query(data QueryRowData) storage.TypedRowData {
	mut out := storage.TypedRowData.new()
	for name, value in data.values {
		out.set(name, storage_value_from_query_scalar(value))
	}
	return out
}

pub fn (data QueryRowData) has(name string) bool {
	return name in data.values
}

pub fn (data QueryRowData) get(name string) !QueryValue {
	value := data.values[name] or { return error('query row field not found: ${name}') }
	return QueryValue{
		value: clone_query_scalar_value(value)
	}
}

pub fn (mut data QueryRowData) set(name string, value QueryValue) {
	data.values[name] = clone_query_scalar_value(value.value)
}

pub fn (data QueryRowData) clone() QueryRowData {
	mut copied := map[string]QueryScalarValue{}
	for name, value in data.values {
		copied[name] = clone_query_scalar_value(value)
	}
	return QueryRowData{
		values: copied
	}
}

pub struct QueryRow {
pub:
	primary_key []u8
	data        QueryRowData
}

fn query_row_from_storage(row storage.TypedSchemaRow) QueryRow {
	return QueryRow{
		primary_key: row.primary_key.clone()
		data:        query_row_data_from_storage(row.data)
	}
}

fn query_rows_from_storage(rows []storage.TypedSchemaRow) []QueryRow {
	mut out := []QueryRow{cap: rows.len}
	for row in rows {
		out << query_row_from_storage(row)
	}
	return out
}

fn storage_row_query(row QueryRow) storage.TypedSchemaRow {
	return storage.TypedSchemaRow{
		primary_key: row.primary_key.clone()
		data:        storage_row_data_query(row.data)
	}
}

pub struct CursorPage {
pub:
	rows             []QueryRow
	plan             Plan
	cursor           CursorState
	general_fts_hits []GeneralFtsHit
}

pub struct ExecutionTimings {
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

pub struct ProfiledCursorPage {
pub:
	page    CursorPage
	timings ExecutionTimings
}

pub struct Result {
pub:
	rows                    []QueryRow
	plan                    Plan
	cursor                  CursorState
	general_fts_hits        []GeneralFtsHit
	has_more                bool
	next_primary_key        []u8
	next_index_value        QueryValue = QueryValue{
		value: NullValue{}
	}
	next_continuation_token string
}

pub fn (result Result) cursor_page() CursorPage {
	return CursorPage{
		rows:             result.rows.clone()
		plan:             result.plan
		cursor:           result.cursor
		general_fts_hits: result.general_fts_hits.clone()
	}
}

pub fn (result Result) page() CursorPage {
	return result.cursor_page()
}

pub fn (page CursorPage) result() Result {
	return Result{
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

pub struct NullValue {}

pub struct MarkdownRef {
pub:
	version     u8 = 1
	doc_root_id string
	source_hash string
	source_len  i64
	ast_version u8 = 1
	parse_flags u32
}

fn query_markdown_ref_from_storage(value storage.MarkdownRef) MarkdownRef {
	return MarkdownRef{
		version:     value.version
		doc_root_id: value.doc_root_id
		source_hash: value.source_hash
		source_len:  value.source_len
		ast_version: value.ast_version
		parse_flags: value.parse_flags
	}
}

fn storage_markdown_ref_query(value MarkdownRef) storage.MarkdownRef {
	return storage.MarkdownRef{
		version:     value.version
		doc_root_id: value.doc_root_id
		source_hash: value.source_hash
		source_len:  value.source_len
		ast_version: value.ast_version
		parse_flags: value.parse_flags
	}
}

pub enum FtsScope {
	any
	heading
	paragraph
	code_block
	list_item
}

pub enum FtsKind {
	term
	prefix
	all
	any
}

pub struct FtsRequest {
pub:
	table_name     string
	column_name    string
	scope          FtsScope = .any
	kind           FtsKind
	terms          []string
	select_columns []string
	limit          int
}

pub struct FtsPlan {
pub:
	table_name  string
	column_name string
	scope       FtsScope
	kind        FtsKind
	strategy    string
	index_name  string
	selector    string
	term_count  int
	limit       int
}

pub struct FtsPreview {
pub:
	plan     FtsPlan
	warnings []string
	notes    []string
}

pub struct FtsHit {
pub:
	primary_key    []u8
	score          int
	matched_terms  []string
	matched_scopes []FtsScope
	summary        string
}

pub struct FtsResult {
pub:
	rows []QueryRow
	hits []FtsHit
	plan FtsPlan
}

pub struct GeneralFtsRequest {
pub:
	table_name     string
	index_name     string
	kind           FtsKind
	terms          []string
	select_columns []string
	limit          int
}

pub struct GeneralFtsPlan {
pub:
	table_name  string
	index_name  string
	column_name string
	strategy    string
	backend     string
	term_count  int
	limit       int
}

pub fn (plan GeneralFtsPlan) as_query_plan() Plan {
	return Plan{
		table_name: plan.table_name
		strategy:   plan.strategy
		index_name: plan.index_name
		limit:      plan.limit
	}
}

pub struct GeneralFtsHit {
pub:
	primary_key []u8
	score       f64
	snippet     string
}

pub struct GeneralFtsResult {
pub:
	rows []QueryRow
	hits []GeneralFtsHit
	plan GeneralFtsPlan
}

pub struct PredicateTarget {
pub:
	column_name string
	plugin_name string
	selector    string
}

pub struct PredicateSpec {
pub:
	target           PredicateTarget
	op               FilterOp
	value            QueryValue
	second_value     QueryValue = QueryValue{
		value: NullValue{}
	}
	has_second_value bool
}

pub fn PredicateSpec.column_eq(column_name string, value QueryValue) PredicateSpec {
	return PredicateSpec{
		target: PredicateTarget{
			column_name: column_name
		}
		op:     .eq
		value:  value
	}
}

pub fn PredicateSpec.column_prefix(column_name string, value QueryValue) PredicateSpec {
	return PredicateSpec{
		target: PredicateTarget{
			column_name: column_name
		}
		op:     .prefix
		value:  value
	}
}

pub fn PredicateSpec.column_after(column_name string, value QueryValue) PredicateSpec {
	return PredicateSpec{
		target: PredicateTarget{
			column_name: column_name
		}
		op:     .after
		value:  value
	}
}

pub fn PredicateSpec.column_before(column_name string, value QueryValue) PredicateSpec {
	return PredicateSpec{
		target: PredicateTarget{
			column_name: column_name
		}
		op:     .before
		value:  value
	}
}

pub fn PredicateSpec.column_between(column_name string, start_value QueryValue, end_value QueryValue) PredicateSpec {
	return PredicateSpec{
		target:           PredicateTarget{
			column_name: column_name
		}
		op:               .between
		value:            start_value
		second_value:     end_value
		has_second_value: true
	}
}

pub fn PredicateSpec.field_eq(column_name string, plugin_name string, selector string, value QueryValue) PredicateSpec {
	return PredicateSpec{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .eq
		value:  value
	}
}

pub fn PredicateSpec.field_prefix(column_name string, plugin_name string, selector string, value QueryValue) PredicateSpec {
	return PredicateSpec{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .prefix
		value:  value
	}
}

pub fn PredicateSpec.field_after(column_name string, plugin_name string, selector string, value QueryValue) PredicateSpec {
	return PredicateSpec{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .after
		value:  value
	}
}

pub fn PredicateSpec.field_before(column_name string, plugin_name string, selector string, value QueryValue) PredicateSpec {
	return PredicateSpec{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .before
		value:  value
	}
}

pub fn PredicateSpec.field_between(column_name string, plugin_name string, selector string, start_value QueryValue, end_value QueryValue) PredicateSpec {
	return PredicateSpec{
		target:           PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:               .between
		value:            start_value
		second_value:     end_value
		has_second_value: true
	}
}

pub struct LoweringRequest {
pub:
	table_name     string
	predicates     []PredicateSpec
	select_columns []string
	limit          int
}

pub enum ComparisonOp {
	eq
	prefix
	gt
	lt
	between
}

pub struct NormalizedPredicate {
pub:
	target           PredicateTarget
	op               ComparisonOp
	value            QueryValue
	second_value     QueryValue = QueryValue{
		value: NullValue{}
	}
	has_second_value bool
}

pub fn NormalizedPredicate.column_eq(column_name string, value QueryValue) NormalizedPredicate {
	return NormalizedPredicate{
		target: PredicateTarget{
			column_name: column_name
		}
		op:     .eq
		value:  value
	}
}

pub fn NormalizedPredicate.column_prefix(column_name string, prefix string) NormalizedPredicate {
	return NormalizedPredicate{
		target: PredicateTarget{
			column_name: column_name
		}
		op:     .prefix
		value:  QueryValue.string_value(prefix)
	}
}

pub fn NormalizedPredicate.column_gt(column_name string, value QueryValue) NormalizedPredicate {
	return NormalizedPredicate{
		target: PredicateTarget{
			column_name: column_name
		}
		op:     .gt
		value:  value
	}
}

pub fn NormalizedPredicate.column_lt(column_name string, value QueryValue) NormalizedPredicate {
	return NormalizedPredicate{
		target: PredicateTarget{
			column_name: column_name
		}
		op:     .lt
		value:  value
	}
}

pub fn NormalizedPredicate.column_between(column_name string, start_value QueryValue, end_value QueryValue) NormalizedPredicate {
	return NormalizedPredicate{
		target:           PredicateTarget{
			column_name: column_name
		}
		op:               .between
		value:            start_value
		second_value:     end_value
		has_second_value: true
	}
}

pub fn NormalizedPredicate.field_eq(column_name string, plugin_name string, selector string, value QueryValue) NormalizedPredicate {
	return NormalizedPredicate{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .eq
		value:  value
	}
}

pub fn NormalizedPredicate.field_prefix(column_name string, plugin_name string, selector string, prefix string) NormalizedPredicate {
	return NormalizedPredicate{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .prefix
		value:  QueryValue.string_value(prefix)
	}
}

pub fn NormalizedPredicate.field_gt(column_name string, plugin_name string, selector string, value QueryValue) NormalizedPredicate {
	return NormalizedPredicate{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .gt
		value:  value
	}
}

pub fn NormalizedPredicate.field_lt(column_name string, plugin_name string, selector string, value QueryValue) NormalizedPredicate {
	return NormalizedPredicate{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:     .lt
		value:  value
	}
}

pub fn NormalizedPredicate.field_between(column_name string, plugin_name string, selector string, start_value QueryValue, end_value QueryValue) NormalizedPredicate {
	return NormalizedPredicate{
		target:           PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		op:               .between
		value:            start_value
		second_value:     end_value
		has_second_value: true
	}
}

pub struct NormalizedLoweringRequest {
pub:
	table_name     string
	predicates     []NormalizedPredicate
	select_columns []string
	limit          int
}

pub enum SqlFilterKind {
	eq
	like_prefix
	gt
	lt
	between
}

pub struct SqlFilterFragment {
pub:
	target           PredicateTarget
	kind             SqlFilterKind
	value            QueryValue
	second_value     QueryValue = QueryValue{
		value: NullValue{}
	}
	has_second_value bool
}

pub fn SqlFilterFragment.column_eq(column_name string, value QueryValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: PredicateTarget{
			column_name: column_name
		}
		kind:   .eq
		value:  value
	}
}

pub fn SqlFilterFragment.column_like_prefix(column_name string, prefix string) SqlFilterFragment {
	return SqlFilterFragment{
		target: PredicateTarget{
			column_name: column_name
		}
		kind:   .like_prefix
		value:  QueryValue.string_value(prefix)
	}
}

pub fn SqlFilterFragment.column_gt(column_name string, value QueryValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: PredicateTarget{
			column_name: column_name
		}
		kind:   .gt
		value:  value
	}
}

pub fn SqlFilterFragment.column_lt(column_name string, value QueryValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: PredicateTarget{
			column_name: column_name
		}
		kind:   .lt
		value:  value
	}
}

pub fn SqlFilterFragment.column_between(column_name string, start_value QueryValue, end_value QueryValue) SqlFilterFragment {
	return SqlFilterFragment{
		target:           PredicateTarget{
			column_name: column_name
		}
		kind:             .between
		value:            start_value
		second_value:     end_value
		has_second_value: true
	}
}

pub fn SqlFilterFragment.field_eq(column_name string, plugin_name string, selector string, value QueryValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		kind:   .eq
		value:  value
	}
}

pub fn SqlFilterFragment.field_like_prefix(column_name string, plugin_name string, selector string, prefix string) SqlFilterFragment {
	return SqlFilterFragment{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		kind:   .like_prefix
		value:  QueryValue.string_value(prefix)
	}
}

pub fn SqlFilterFragment.field_gt(column_name string, plugin_name string, selector string, value QueryValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		kind:   .gt
		value:  value
	}
}

pub fn SqlFilterFragment.field_lt(column_name string, plugin_name string, selector string, value QueryValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		kind:   .lt
		value:  value
	}
}

pub fn SqlFilterFragment.field_between(column_name string, plugin_name string, selector string, start_value QueryValue, end_value QueryValue) SqlFilterFragment {
	return SqlFilterFragment{
		target:           PredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector:    selector
		}
		kind:             .between
		value:            start_value
		second_value:     end_value
		has_second_value: true
	}
}

pub struct SqlLoweringRequest {
pub:
	table_name     string
	filters        []SqlFilterFragment
	select_columns []string
	limit          int
}

pub struct PlannerHint {
pub:
	op                    FilterOp
	strategy              string
	index_name            string
	stores_row            bool
	score                 int
	supports_reverse_scan bool
	supports_top_n        bool
}

pub struct SamplePlanExplain {
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

pub struct FilterShapeCapability {
pub:
	op                    FilterOp
	value_type            ColumnType
	indexed               bool
	index_name            string
	planner_strategy      string
	planner_score         int
	projection_only       bool
	continuation_anchor   bool
	supports_reverse_scan bool
	supports_top_n        bool
	sample_explain        SamplePlanExplain
}

pub struct FtsShapeCapability {
pub:
	kind             FtsKind
	indexed          bool
	index_name       string
	planner_strategy string
	sample_explain   SamplePlanExplain
}

pub struct OrderCapability {
pub:
	column_name           string
	direction             OrderDirection
	filter_op             FilterOp
	indexed               bool
	index_name            string
	planner_strategy      string
	supports_continuation bool
	supports_reverse_scan bool
	supports_top_n        bool
	sample_explain        SamplePlanExplain
}

pub struct ColumnCapability {
pub:
	name          string
	typ           ColumnType
	nullable      bool
	filter_ops    []FilterOp
	index_names   []string
	planner_hints []PlannerHint
	filter_shapes []FilterShapeCapability
	order_shapes  []OrderCapability
}

pub struct IndexCapability {
pub:
	name                string
	column_name         string
	value_type          ColumnType
	stores_row          bool
	is_fts              bool
	fts_query_kinds     []FtsKind
	fts_shapes          []FtsShapeCapability
	json_field          string
	field_selector_meta FieldSelectorMetaDef
	filter_ops          []FilterOp
}

pub struct FieldSelectorCapability {
pub:
	column_name      string
	plugin_name      string
	selector         string
	value_type       ColumnType
	stores_row       bool
	filter_ops       []FilterOp
	index_names      []string
	projection_names []string
	planner_hints    []PlannerHint
	filter_shapes    []FilterShapeCapability
	order_shapes     []OrderCapability
	fts_query_kinds  []FtsKind
	fts_shapes       []FtsShapeCapability
}

pub struct ProjectionCapability {
pub:
	name             string
	column_name      string
	source_json_path string
	plugin_name      string
	selector         string
	value_type       ColumnType
	aggregate        ColumnAggregate
	priority         int
	cost_hint        ProjectionCostHint
}

pub struct ProjectionSelectorRef {
pub:
	plugin_name string
	selector    string
}

pub struct ProjectionDef {
pub:
	name                     string
	table_name               string
	column_name              string
	source_json_path         string
	source_markdown_selector string
	aggregate                ColumnAggregate
	priority                 int                = 100
	cost_hint                ProjectionCostHint = .medium
}

pub fn (def ProjectionDef) is_field_projection_selector() bool {
	return def.source_markdown_selector.len > 0
}

pub fn (def ProjectionDef) field_projection_plugin() string {
	if def.source_markdown_selector.len > 0 {
		return 'markdown'
	}
	return ''
}

pub fn (def ProjectionDef) field_projection_selector() string {
	if def.source_markdown_selector.len > 0 {
		return def.source_markdown_selector
	}
	return ''
}

pub fn (def ProjectionDef) field_projection_selector_ref() ?ProjectionSelectorRef {
	plugin_name := def.field_projection_plugin()
	selector := def.field_projection_selector()
	if plugin_name.len == 0 || selector.len == 0 {
		return none
	}
	return ProjectionSelectorRef{
		plugin_name: plugin_name
		selector:    selector
	}
}

pub fn (def ProjectionDef) field_projection_meta() ?FieldSelectorMetaDef {
	plugin_name := def.field_projection_plugin()
	selector := def.field_projection_selector()
	if plugin_name.len == 0 || selector.len == 0 {
		return none
	}
	return FieldSelectorMetaDef{
		plugin_name: plugin_name
		selector:    selector
		value_type:  .i64_
		stores_row:  false
	}
}

pub struct FieldSelectorMetaDef {
pub:
	plugin_name string
	selector    string
	value_type  ColumnType
	stores_row  bool
}

pub struct ColumnSchemaDef {
pub:
	name     string
	typ      ColumnType
	nullable bool
}

pub struct IndexSchemaDef {
pub:
	name              string
	column            string
	json_field        string
	markdown_selector string
	fts_text_mode     string
	json_field_type   ColumnType
	stores_row        bool
	stored_columns    []string
}

pub fn (index IndexSchemaDef) is_json_path() bool {
	return index.json_field.len > 0
}

pub fn (index IndexSchemaDef) is_fts() bool {
	return index.fts_text_mode.len > 0
}

pub fn (index IndexSchemaDef) is_field_selector() bool {
	return index.markdown_selector.len > 0
}

pub fn (index IndexSchemaDef) stores_full_row() bool {
	return index.stores_row && index.stored_columns.len == 0
}

pub fn (index IndexSchemaDef) can_cover_columns(columns []string) bool {
	if !index.stores_row {
		return false
	}
	if index.stored_columns.len == 0 || columns.len == 0 {
		return true
	}
	mut stored := map[string]bool{}
	for name in index.stored_columns {
		stored[name] = true
	}
	for name in columns {
		if name !in stored {
			return false
		}
	}
	return true
}

pub fn (index IndexSchemaDef) field_selector_plugin() string {
	if index.is_field_selector() {
		return 'markdown'
	}
	return ''
}

pub fn (index IndexSchemaDef) field_selector() string {
	if index.is_field_selector() {
		return index.markdown_selector
	}
	return ''
}

pub fn (index IndexSchemaDef) field_selector_meta() ?FieldSelectorMetaDef {
	plugin_name := index.field_selector_plugin()
	selector := index.field_selector()
	if plugin_name.len == 0 || selector.len == 0 {
		return none
	}
	return FieldSelectorMetaDef{
		plugin_name: plugin_name
		selector:    selector
		value_type:  index.json_field_type
		stores_row:  index.stores_row
	}
}

pub fn (index IndexSchemaDef) value_column(table TableSchemaDef) !ColumnSchemaDef {
	if index.is_fts() {
		return ColumnSchemaDef{
			name:     'fts_text'
			typ:      .string_
			nullable: false
		}
	}
	if index.is_field_selector() {
		return ColumnSchemaDef{
			name:     'field_index'
			typ:      index.json_field_type
			nullable: false
		}
	}
	if index.json_field.len == 0 {
		return table.column(index.column)
	}
	return ColumnSchemaDef{
		name:     index.json_field
		typ:      index.json_field_type
		nullable: true
	}
}

pub struct TableSchemaDef {
pub:
	name        string
	primary_key []string
	columns     []ColumnSchemaDef
	indexes     []IndexSchemaDef
}

pub struct QuerySpec {
pub:
	schema      TableSchemaDef
	projections map[string]ProjectionDef
}

pub fn (table TableSchemaDef) has_column(name string) bool {
	for column in table.columns {
		if column.name == name {
			return true
		}
	}
	return false
}

pub fn (table TableSchemaDef) column(name string) !ColumnSchemaDef {
	for column in table.columns {
		if column.name == name {
			return column
		}
	}
	return error('table column not found: ${name}')
}

pub struct TableSchema {
pub:
	table_name                  string
	primary_key                 []string
	columns                     []ColumnCapability
	indexes                     []IndexCapability
	field_selectors             []FieldSelectorCapability
	projection_metrics          []ProjectionCapability
	supported_filter_ops        []FilterOp
	default_result_shape        string
	supports_continuation_token bool
	supports_select_projection  bool
}

fn query_scalar_value_from_storage(value storage.ColumnValue) QueryScalarValue {
	return match value {
		storage.MarkdownRef { query_markdown_ref_from_storage(value) }
		storage.NullValue { NullValue{} }
		bool { value }
		i64 { value }
		string { value.clone() }
		[]u8 { value.clone() }
	}
}

fn storage_value_from_query_scalar(value QueryScalarValue) storage.ColumnValue {
	return match value {
		MarkdownRef { storage.ColumnValue(storage_markdown_ref_query(value)) }
		NullValue { storage.ColumnValue(storage.NullValue{}) }
		bool { storage.ColumnValue(value) }
		i64 { storage.ColumnValue(value) }
		string { storage.ColumnValue(value.clone()) }
		[]u8 { storage.ColumnValue(value.clone()) }
	}
}

fn clone_query_scalar_value(value QueryScalarValue) QueryScalarValue {
	return match value {
		MarkdownRef {
			QueryScalarValue(MarkdownRef{
				version:     value.version
				doc_root_id: value.doc_root_id
				source_hash: value.source_hash
				source_len:  value.source_len
				ast_version: value.ast_version
				parse_flags: value.parse_flags
			})
		}
		NullValue {
			QueryScalarValue(NullValue{})
		}
		bool {
			QueryScalarValue(value)
		}
		i64 {
			QueryScalarValue(value)
		}
		string {
			QueryScalarValue(value.clone())
		}
		[]u8 {
			QueryScalarValue(value.clone())
		}
	}
}
