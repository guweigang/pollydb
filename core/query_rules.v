module core

pub struct QueryShapeFlags {
pub:
	projection_only     bool
	continuation_anchor bool
	supports_reverse    bool
	supports_top_n      bool
}

pub struct QueryPlanExplainFlags {
pub:
	supports_continuation bool
	supports_reverse      bool
	supports_top_n        bool
}

pub fn query_supported_ops_for_type_name(type_name string) []string {
	return match type_name {
		'bool_', 'json_', 'markdown_' { ['eq'] }
		'i64_' { ['eq', 'after', 'before', 'between'] }
		'string_', 'bytes_', 'enum_', 'datetime_' { ['eq', 'prefix', 'after', 'before', 'between'] }
		else { []string{} }
	}
}

pub fn query_sample_value_kind(type_name string) string {
	return match type_name {
		'bool_' { 'bool' }
		'i64_' { 'i64' }
		'string_', 'enum_', 'json_', 'datetime_' { 'string' }
		'bytes_' { 'bytes' }
		'markdown_' { 'markdown' }
		else { '' }
	}
}

pub fn query_type_supports_order(type_name string) bool {
	return type_name in ['i64_', 'string_', 'bytes_', 'enum_', 'datetime_']
}

pub fn query_type_supports_filter_op(type_name string, op string) bool {
	return match op {
		'prefix' {
			type_name in ['string_', 'bytes_', 'enum_', 'datetime_']
		}
		'after', 'before', 'between' {
			query_type_supports_order(type_name)
		}
		'eq' {
			true
		}
		else {
			false
		}
	}
}

pub fn query_supports_reverse_scan(indexed bool, plugin_name string, selector string, op string) bool {
	return indexed && plugin_name.len == 0 && selector.len == 0
		&& op in ['before', 'after', 'between', 'prefix']
}

pub fn query_supports_top_n(indexed bool, plugin_name string, selector string, op string) bool {
	return indexed && plugin_name.len == 0 && selector.len == 0
		&& op in ['eq', 'before', 'after', 'between', 'prefix']
}

pub fn query_supported_markdown_fts_kinds(plugin_name string, selector string) []string {
	if plugin_name != 'markdown' || !selector.starts_with('fts') {
		return []string{}
	}
	return ['term', 'prefix', 'all', 'any']
}

pub fn query_supports_order_shapes(plugin_name string, selector string) bool {
	return plugin_name.len == 0 && selector.len == 0
}

pub fn query_projection_only(indexed bool, projection_count int) bool {
	return !indexed && projection_count > 0
}

pub fn query_continuation_anchor(indexed bool) bool {
	return indexed
}

pub fn query_sample_fts_terms(kind string) []string {
	return match kind {
		'term' { ['roadmap'] }
		'prefix' { ['road'] }
		'all' { ['pollydb', 'merge'] }
		'any' { ['agent', 'sync'] }
		else { []string{} }
	}
}

pub fn query_sample_plan_fallback_warnings() []string {
	return ['Unable to build sample plan preview for this filter shape.']
}

pub fn query_sample_general_fts_notes(index_name string) []string {
	return [
		'Query can be issued via QueryRequest.general_fts using the `${index_name}` index.',
		'Execution uses the SQLite FTS5 sidecar backend.',
	]
}

pub fn query_sample_order_direction(indexed bool, plugin_name string, selector string, op string) string {
	if !indexed || plugin_name.len > 0 || selector.len > 0 {
		return ''
	}
	if op in ['eq', 'before', 'after', 'between', 'prefix'] {
		return 'desc'
	}
	return ''
}

pub fn query_plan_uses_projection_pushdown(strategy string) bool {
	return strategy.ends_with('_projected')
}

pub fn query_plan_strategy_name(op string, projected bool) string {
	base := match op {
		'eq' { 'index_exact' }
		'prefix' { 'index_prefix' }
		'after' { 'index_after' }
		'before' { 'index_before' }
		'between' { 'index_between' }
		else { '' }
	}
	return if projected && base.len > 0 { '${base}_projected' } else { base }
}

pub fn query_plan_filter_order_strategy_name(filter_op string, same_column_order bool, order_desc bool, projected bool) string {
	if same_column_order {
		base := match filter_op {
			'eq' {
				if order_desc { 'index_eq_order_desc' } else { 'index_eq_order_asc' }
			}
			'prefix' {
				if order_desc { 'index_prefix_order_desc' } else { 'index_prefix_order_asc' }
			}
			'after' {
				if order_desc { 'index_after_order_desc' } else { 'index_after_order_asc' }
			}
			'before' {
				if order_desc { 'index_before_order_desc' } else { 'index_before_order_asc' }
			}
			'between' {
				if order_desc { 'index_between_order_desc' } else { 'index_between_order_asc' }
			}
			else {
				''
			}
		}
		return if projected && base.len > 0 { '${base}_projected' } else { base }
	}
	return query_plan_strategy_name(filter_op, projected)
}

pub fn query_plan_order_strategy_name(order_desc bool, projected bool) string {
	base := if order_desc { 'index_order_desc' } else { 'index_order_asc' }
	return if projected { '${base}_projected' } else { base }
}

pub fn query_plan_base_strategy(strategy string) string {
	if query_plan_uses_projection_pushdown(strategy) {
		return strategy.all_before_last('_projected')
	}
	return strategy
}

pub fn query_plan_supports_reverse_scan(index_name string, strategy string) bool {
	base := query_plan_base_strategy(strategy)
	return index_name.len > 0 && (base == 'index_before'
		|| base == 'index_order_desc' || base == 'index_before_order_desc'
		|| base == 'index_after_order_desc' || base == 'index_between_order_desc'
		|| base == 'index_prefix_order_desc')
}

pub fn query_plan_supports_top_n(index_name string, strategy string) bool {
	base := query_plan_base_strategy(strategy)
	return index_name.len > 0 && (base == 'index_before'
		|| base == 'index_order_desc' || base == 'index_order_asc'
		|| base == 'index_before_order_desc' || base == 'index_after_order_desc'
		|| base == 'index_after_order_asc' || base == 'index_between_order_desc'
		|| base == 'index_between_order_asc' || base == 'index_prefix_order_desc'
		|| base == 'index_prefix_order_asc' || base == 'index_eq_order_desc'
		|| base == 'index_eq_order_asc')
}

pub fn query_index_score(op string, stores_row bool, field_selector bool, select_column_count int) int {
	mut score := 10
	match op {
		'eq' { score += 4 }
		'between', 'after', 'before' { score += 3 }
		'prefix' { score += 2 }
		else {}
	}
	if stores_row {
		score += 2
	}
	if field_selector {
		score += 1
	}
	if select_column_count > 0 && stores_row {
		score += 1
	}
	return score
}

pub fn query_order_with_filters_error(filter_count int, field_selector bool, same_column bool, indexed_filter bool, op string, order_desc bool) string {
	if filter_count != 1 {
		return 'query order_by with filters currently requires a single indexed filter'
	}
	if field_selector {
		return 'query order_by does not yet support field selector filters'
	}
	if !same_column {
		return 'query order_by with filters currently requires ordering on the same indexed column'
	}
	if !indexed_filter {
		return 'query order_by with filters requires an indexed filter column'
	}
	if op == 'before' && !order_desc {
		return 'query order_by asc is not yet supported for before-filtered queries'
	}
	return ''
}

pub fn query_filter_bounds_error(op string, prefix_value_compatible bool, has_second_value bool, same_kind bool) string {
	match op {
		'prefix' {
			if !prefix_value_compatible {
				return 'query prefix filters require string or bytes values'
			}
		}
		'between' {
			if !has_second_value {
				return 'query between filters require second_value'
			}
			if !same_kind {
				return 'query filter values must use the same type'
			}
		}
		'after', 'before' {
			if has_second_value {
				return 'query after/before filters do not accept second_value'
			}
		}
		else {}
	}
	return ''
}

pub fn query_order_index_eligible(field_selector bool, json_path bool, fts bool, same_column bool) bool {
	return !field_selector && !json_path && !fts && same_column
}

pub fn query_order_index_score(stores_row bool, select_column_count int) int {
	mut score := 10
	if select_column_count > 0 && stores_row {
		score += 5
	}
	return score
}

pub fn query_filter_index_eligible(filter_field_selector bool, index_field_selector bool, index_json_path bool, index_fts bool, same_column bool, selector_plugin_match bool, selector_name_match bool, type_supports_filter_op bool) bool {
	if filter_field_selector {
		return index_field_selector && same_column && selector_plugin_match && selector_name_match
	}
	return !index_field_selector && !index_json_path && !index_fts && same_column
		&& type_supports_filter_op
}

pub fn query_projection_pushdown_eligible(select_column_count int, stores_row bool, field_selector bool, fts bool, post_filter_count int) bool {
	return select_column_count > 0 && stores_row && !field_selector && !fts
		&& post_filter_count == 0
}

pub fn query_fetch_limit(post_filter_count int, limit int) int {
	if post_filter_count > 0 {
		return 0
	}
	if limit > 0 {
		return limit + 1
	}
	return 0
}

pub fn query_ordered_index_scan(base_strategy string) bool {
	return base_strategy == 'index_order_asc' || base_strategy == 'index_order_desc'
}

pub fn query_reverse_filtered_order(order_column_name string, filter_column_name string, order_desc bool, filter_op string) bool {
	return order_column_name.len > 0 && order_column_name == filter_column_name && order_desc
		&& filter_op != 'eq'
}

pub fn query_requires_base_row_fetch(has_index bool, select_column_count int, stores_row bool) bool {
	return has_index && select_column_count > 0 && !stores_row
}

pub fn query_shape_flags(indexed bool, projection_count int, plugin_name string, selector string, op string) QueryShapeFlags {
	return QueryShapeFlags{
		projection_only:     query_projection_only(indexed, projection_count)
		continuation_anchor: query_continuation_anchor(indexed)
		supports_reverse:    query_supports_reverse_scan(indexed, plugin_name, selector,
			op)
		supports_top_n:      query_supports_top_n(indexed, plugin_name, selector, op)
	}
}

pub fn query_plan_explain_flags(index_name string, strategy string, supports_continuation bool) QueryPlanExplainFlags {
	return QueryPlanExplainFlags{
		supports_continuation: supports_continuation
		supports_reverse:      query_plan_supports_reverse_scan(index_name, strategy)
		supports_top_n:        query_plan_supports_top_n(index_name, strategy)
	}
}

pub fn query_plan_table_scan_warning() string {
	return 'No eligible index matched; planner will fall back to table scan.'
}

pub fn query_plan_post_filter_note() string {
	return 'Additional filters will run as post-filters after the primary planner step.'
}

pub fn query_plan_projection_pushdown_note() string {
	return 'Selected columns will be satisfied directly from the covering index.'
}

pub fn query_plan_base_row_fetch_note() string {
	return 'Selected columns may require base-row fetches because the chosen index is non-covering.'
}

pub fn query_plan_reverse_scan_note() string {
	return 'A reverse index scan executor is available for this filter shape.'
}

pub fn query_plan_top_n_note() string {
	return 'Top-N retrieval can be satisfied by combining the reverse executor with a limit.'
}

pub fn query_plan_order_note() string {
	return 'Requested ordering can be satisfied directly from the chosen index.'
}

pub fn query_plan_preview_warnings(table_scan bool) []string {
	mut warnings := []string{}
	if table_scan {
		warnings << query_plan_table_scan_warning()
	}
	return warnings
}

pub fn query_plan_preview_notes(post_filter_count int, uses_projection_pushdown bool, requires_base_row_fetch bool, supports_reverse bool, supports_top_n bool, has_order bool) []string {
	mut notes := []string{}
	if post_filter_count > 0 {
		notes << query_plan_post_filter_note()
	}
	if uses_projection_pushdown {
		notes << query_plan_projection_pushdown_note()
	} else if requires_base_row_fetch {
		notes << query_plan_base_row_fetch_note()
	}
	if supports_reverse {
		notes << query_plan_reverse_scan_note()
	}
	if supports_top_n {
		notes << query_plan_top_n_note()
	}
	if has_order {
		notes << query_plan_order_note()
	}
	return notes
}

pub fn query_field_selector_planning_warning(field_ref string, projection_only bool) string {
	if projection_only {
		return query_field_selector_projection_only_warning(field_ref)
	}
	return query_field_selector_unindexed_warning(field_ref)
}

pub fn query_fts_preview_warnings(index_name string) []string {
	if index_name.len == 0 {
		return [
			'No matching Markdown FTS derived index found; query will fall back to table scan.',
		]
	}
	return []string{}
}

pub fn query_fts_preview_notes(kind string, term_count int) []string {
	return match kind {
		'all' {
			[
				'Planner will intersect exact FTS term matches across ${term_count} term(s).',
			]
		}
		'any' {
			[
				'Planner will union exact FTS term matches across ${term_count} term(s).',
			]
		}
		else {
			[]string{}
		}
	}
}

pub fn query_field_selector_projection_only_warning(field_ref string) string {
	return 'Field selector `${field_ref}` is projection-only in the current schema and cannot be planned with an index.'
}

pub fn query_field_selector_unindexed_warning(field_ref string) string {
	return 'Field selector `${field_ref}` has no matching derived index and will not benefit from indexed planning.'
}
