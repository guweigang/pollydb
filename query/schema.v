module query

import core

pub fn table_schema(database Database, table_name string) !TableSchema {
	spec := database.db.table_spec(table_name)!
	return table_schema_from_spec(query_spec(spec, projector_defs_from_storage(database.db.aggregate_projectors())),
		table_name)
}

pub fn table_schema_from_spec(spec QuerySpec, table_name string) !TableSchema {
	return build_table_schema_from_spec(spec, table_name)
}

pub fn supported_ops_for_type(typ ColumnType) []FilterOp {
	return core.query_supported_ops_for_type_name(storage_column_type(typ).str()).map(query_filter_op_from_name(it))
}

pub fn sample_value_for_type(typ ColumnType) QueryValue {
	return match core.query_sample_value_kind(storage_column_type(typ).str()) {
		'bool' { QueryValue.bool_value(true) }
		'i64' { QueryValue.i64_value(i64(1)) }
		'string' { QueryValue.string_value('x') }
		'bytes' { QueryValue.bytes_value('x'.bytes()) }
		'markdown' { QueryValue.markdown_ref(MarkdownRef{}) }
		else { QueryValue.string_value('') }
	}
}

pub fn sample_filter(column_name string, plugin_name string, selector string, value_type ColumnType, op FilterOp) Filter {
	first := sample_value_for_type(value_type)
	second := sample_value_for_type(value_type)
	if plugin_name.len > 0 || selector.len > 0 {
		return match op {
			.eq {
				Filter.field_eq(column_name, plugin_name, selector, first)
			}
			.prefix {
				Filter.field_prefix(column_name, plugin_name, selector, first)
			}
			.after {
				Filter.field_after(column_name, plugin_name, selector, first)
			}
			.before {
				Filter.field_before(column_name, plugin_name, selector, first)
			}
			.between {
				Filter.field_between(column_name, plugin_name, selector, first, second)
			}
		}
	}
	return match op {
		.eq { Filter.eq(column_name, first) }
		.prefix { Filter.prefix(column_name, first) }
		.after { Filter.after(column_name, first) }
		.before { Filter.before(column_name, first) }
		.between { Filter.between(column_name, first, second) }
	}
}

pub fn filter_op_supports_reverse_scan(indexed bool, plugin_name string, selector string, op FilterOp) bool {
	return core.query_supports_reverse_scan(indexed, plugin_name, selector, query_filter_op_name(op))
}

pub fn filter_op_supports_top_n(indexed bool, plugin_name string, selector string, op FilterOp) bool {
	return core.query_supports_top_n(indexed, plugin_name, selector, query_filter_op_name(op))
}

pub fn supported_fts_kinds_for_selector(plugin_name string, selector string) []FtsKind {
	return core.query_supported_markdown_fts_kinds(plugin_name, selector).map(match it {
		'term' { FtsKind.term }
		'prefix' { .prefix }
		'all' { .all }
		'any' { .any }
		else { .term }
	})
}

pub fn sample_fts_terms(kind FtsKind) []string {
	kind_name := match kind {
		.term { 'term' }
		.prefix { 'prefix' }
		.all { 'all' }
		.any { 'any' }
	}
	return core.query_sample_fts_terms(kind_name)
}

pub fn supports_order_shapes(plugin_name string, selector string) bool {
	return core.query_supports_order_shapes(plugin_name, selector)
}

pub fn filter_shape_projection_only(indexed bool, projection_names []string) bool {
	return core.query_projection_only(indexed, projection_names.len)
}

pub fn filter_shape_continuation_anchor(indexed bool) bool {
	return core.query_continuation_anchor(indexed)
}

pub fn filter_shape_flags(indexed bool, projection_names []string, plugin_name string, selector string, op FilterOp) core.QueryShapeFlags {
	return core.query_shape_flags(indexed, projection_names.len, plugin_name, selector,
		query_filter_op_name(op))
}

pub fn plan_explain_flags(plan Plan, supports_continuation bool) core.QueryPlanExplainFlags {
	return core.query_plan_explain_flags(plan.index_name, plan.strategy, supports_continuation)
}

pub fn order_index_eligible(indexed_field_selector bool, indexed_json_path bool, indexed_fts bool, same_column bool) bool {
	return core.query_order_index_eligible(indexed_field_selector, indexed_json_path,
		indexed_fts, same_column)
}

pub fn order_index_score(stores_row bool, select_columns []string) int {
	return core.query_order_index_score(stores_row, select_columns.len)
}

pub fn filter_index_eligible(filter_is_field_selector bool, index_is_field_selector bool, index_is_json_path bool, index_is_fts bool, same_column bool, selector_plugin_match bool, selector_name_match bool, type_supports_filter_op bool) bool {
	return core.query_filter_index_eligible(filter_is_field_selector, index_is_field_selector,
		index_is_json_path, index_is_fts, same_column, selector_plugin_match, selector_name_match,
		type_supports_filter_op)
}

pub fn sample_plan_fallback_explain() SamplePlanExplain {
	return SamplePlanExplain{
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

pub fn sample_order_for_filter(indexed bool, column_name string, plugin_name string, selector string, op FilterOp) Order {
	direction_name := core.query_sample_order_direction(indexed, plugin_name, selector,
		query_filter_op_name(op))
	if direction_name.len == 0 {
		return Order{}
	}
	return Order{
		column_name: column_name
		direction:   if direction_name == 'desc' { .desc } else { .asc }
	}
}

pub fn sample_plan_request(table_name string, filter Filter, indexed bool) Request {
	return Request{
		table_name: table_name
		filters:    [filter]
		order_by:   sample_order_for_filter(indexed, filter.column_name, filter.plugin_name,
			filter.selector, filter.op)
	}
}

pub fn filter_shape_capability(filter Filter, value_type ColumnType, op FilterOp, projection_names []string, best_score int, best_index_name string, sample_explain SamplePlanExplain) FilterShapeCapability {
	flags := filter_shape_flags(best_score >= 0, projection_names, filter.plugin_name,
		filter.selector, op)
	return FilterShapeCapability{
		op:                    op
		value_type:            value_type
		indexed:               best_score >= 0
		index_name:            if best_score >= 0 { best_index_name } else { '' }
		planner_strategy:      if best_score >= 0 { sample_explain.strategy } else { 'table_scan' }
		planner_score:         if best_score >= 0 { best_score } else { -1 }
		projection_only:       flags.projection_only
		continuation_anchor:   flags.continuation_anchor
		supports_reverse_scan: flags.supports_reverse
		supports_top_n:        flags.supports_top_n
		sample_explain:        sample_explain
	}
}

pub fn order_capability(column_name string, direction OrderDirection, op FilterOp, plan Plan, preview PlanPreview) OrderCapability {
	flags := plan_explain_flags(plan, preview.supports_continuation_token)
	return OrderCapability{
		column_name:           column_name
		direction:             direction
		filter_op:             op
		indexed:               plan.index_name.len > 0
		index_name:            plan.index_name
		planner_strategy:      plan.strategy
		supports_continuation: flags.supports_continuation
		supports_reverse_scan: flags.supports_reverse
		supports_top_n:        flags.supports_top_n
		sample_explain:        sample_explain_from_preview(preview)
	}
}

pub fn field_selector_key(column_name string, plugin_name string, selector string) string {
	return '${column_name}\n${plugin_name}\n${selector}'
}

pub fn field_selector_capability(column_name string, plugin_name string, selector string, value_type ColumnType, stores_row bool, filter_ops []FilterOp, planner_hints []PlannerHint, fts_query_kinds []FtsKind, fts_shapes []FtsShapeCapability) FieldSelectorCapability {
	return FieldSelectorCapability{
		column_name:      column_name
		plugin_name:      plugin_name
		selector:         selector
		value_type:       value_type
		stores_row:       stores_row
		filter_ops:       filter_ops.clone()
		index_names:      []string{}
		projection_names: []string{}
		planner_hints:    planner_hints.clone()
		filter_shapes:    []FilterShapeCapability{}
		order_shapes:     []OrderCapability{}
		fts_query_kinds:  fts_query_kinds.clone()
		fts_shapes:       fts_shapes.clone()
	}
}

pub fn projection_metric_capability(name string, column_name string, source_json_path string, plugin_name string, selector string, value_type ColumnType, aggregate ColumnAggregate, priority int, cost_hint ProjectionCostHint) ProjectionCapability {
	return ProjectionCapability{
		name:             name
		column_name:      column_name
		source_json_path: source_json_path
		plugin_name:      plugin_name
		selector:         selector
		value_type:       value_type
		aggregate:        aggregate
		priority:         priority
		cost_hint:        cost_hint
	}
}

pub fn column_capability(name string, typ ColumnType, nullable bool, filter_ops []FilterOp, index_names []string, planner_hints []PlannerHint, filter_shapes []FilterShapeCapability, order_shapes []OrderCapability) ColumnCapability {
	return ColumnCapability{
		name:          name
		typ:           typ
		nullable:      nullable
		filter_ops:    filter_ops.clone()
		index_names:   index_names.clone()
		planner_hints: planner_hints.clone()
		filter_shapes: filter_shapes.clone()
		order_shapes:  order_shapes.clone()
	}
}

pub fn index_capability(name string, column_name string, value_type ColumnType, stores_row bool, is_fts bool, fts_query_kinds []FtsKind, fts_shapes []FtsShapeCapability, json_field string, field_selector_meta FieldSelectorMetaDef, filter_ops []FilterOp) IndexCapability {
	return IndexCapability{
		name:                name
		column_name:         column_name
		value_type:          value_type
		stores_row:          stores_row
		is_fts:              is_fts
		fts_query_kinds:     fts_query_kinds.clone()
		fts_shapes:          fts_shapes.clone()
		json_field:          json_field
		field_selector_meta: field_selector_meta
		filter_ops:          filter_ops.clone()
	}
}

pub fn table_schema_capability(table_name string, primary_key []string, columns []ColumnCapability, indexes []IndexCapability, field_selectors []FieldSelectorCapability, projection_metrics []ProjectionCapability, supported_filter_ops []FilterOp, default_result_shape string, supports_continuation_token bool, supports_select_projection bool) TableSchema {
	return TableSchema{
		table_name:                  table_name
		primary_key:                 primary_key.clone()
		columns:                     columns.clone()
		indexes:                     indexes.clone()
		field_selectors:             field_selectors.clone()
		projection_metrics:          projection_metrics.clone()
		supported_filter_ops:        supported_filter_ops.clone()
		default_result_shape:        default_result_shape
		supports_continuation_token: supports_continuation_token
		supports_select_projection:  supports_select_projection
	}
}

pub fn sample_explain_from_preview(preview PlanPreview) SamplePlanExplain {
	flags := plan_explain_flags(preview.plan, preview.supports_continuation_token)
	return SamplePlanExplain{
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

pub fn sample_fts_explain_from_preview(preview FtsPreview) SamplePlanExplain {
	return SamplePlanExplain{
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

pub fn sample_general_fts_explain(plan GeneralFtsPlan) SamplePlanExplain {
	return SamplePlanExplain{
		strategy:                    plan.strategy
		index_name:                  plan.index_name
		warnings:                    []string{}
		notes:                       core.query_sample_general_fts_notes(plan.index_name)
		default_result_shape:        'rows'
		supports_continuation_token: false
		supports_reverse_scan:       false
		supports_top_n:              false
	}
}

fn query_filter_op_from_name(name string) FilterOp {
	return match name {
		'eq' { .eq }
		'prefix' { .prefix }
		'after' { .after }
		'before' { .before }
		'between' { .between }
		else { .eq }
	}
}

fn build_table_schema_from_spec(spec QuerySpec, table_name string) !TableSchema {
	schema := spec.schema
	columns := query_schema_column_capabilities(spec, table_name)
	indexes := query_schema_index_capabilities(spec)!
	mut field_selector_entries := query_schema_field_selector_entries_from_indexes(spec, table_name)
	projection_metrics := query_schema_projection_metrics_and_field_selectors(spec, table_name,
		mut field_selector_entries)
	return table_schema_capability(schema.name, schema.primary_key, columns, indexes,
		query_schema_sorted_field_selectors(field_selector_entries), projection_metrics,
		[
		.eq,
		.prefix,
		.after,
		.before,
		.between,
	], 'page', true, true)
}

fn query_schema_column_capabilities(spec QuerySpec, table_name string) []ColumnCapability {
	schema := spec.schema
	mut columns := []ColumnCapability{cap: schema.columns.len}
	for column in schema.columns {
		columns << column_capability(column.name, column.typ, column.nullable, supported_ops_for_type(column.typ),
			query_schema_column_index_names(schema, column.name), query_schema_planner_hints_for_target(spec,
			column.name, '', '', column.typ), query_schema_filter_shapes_for_target(spec,
			table_name, column.name, '', '', column.typ, []string{}), query_schema_order_shapes_for_target(spec,
			table_name, column.name, '', '', column.typ))
	}
	return columns
}

fn query_schema_column_index_names(schema TableSchemaDef, column_name string) []string {
	mut index_names := []string{}
	for index in schema.indexes {
		if index.column == column_name && !index.is_field_selector() {
			index_names << index.name
		}
	}
	return index_names
}

fn query_schema_index_capabilities(spec QuerySpec) ![]IndexCapability {
	schema := spec.schema
	mut indexes := []IndexCapability{cap: schema.indexes.len}
	for index in schema.indexes {
		value_column := index.value_column(schema)!
		indexes << index_capability(index.name, index.column, value_column.typ, index.stores_row,
			index.is_fts(), if index.is_fts() {
			[FtsKind.term, .prefix, .all, .any]
		} else {
			[]FtsKind{}
		}, query_schema_fts_shapes_for_index(spec, index), index.json_field, if meta := index.field_selector_meta() {
			meta
		} else {
			FieldSelectorMetaDef{}
		}, if index.is_fts() {
			[]FilterOp{}
		} else {
			supported_ops_for_type(value_column.typ)
		})
	}
	return indexes
}

fn query_schema_planner_hints_for_target(spec QuerySpec, column_name string, plugin_name string, selector string, value_type ColumnType) []PlannerHint {
	schema := spec.schema
	mut hints := []PlannerHint{}
	for op in supported_ops_for_type(value_type) {
		filter := sample_filter(column_name, plugin_name, selector, value_type, op)
		best := query_schema_best_index_match_for_filter(schema, filter, []string{})
		if best.score < 0 {
			continue
		}
		sample_explain := query_schema_sample_plan_explain(spec, schema.name, filter)
		hints << PlannerHint{
			op:                    op
			strategy:              sample_explain.strategy
			index_name:            best.index.name
			stores_row:            best.index.stores_row
			score:                 best.score
			supports_reverse_scan: filter_op_supports_reverse_scan(best.score >= 0, plugin_name,
				selector, op)
			supports_top_n:        filter_op_supports_top_n(best.score >= 0, plugin_name,
				selector, op)
		}
	}
	return hints
}

struct QuerySchemaBestIndexMatch {
	index IndexSchemaDef
	score int = -1
}

fn query_schema_best_index_match_for_filter(schema TableSchemaDef, filter Filter, select_columns []string) QuerySchemaBestIndexMatch {
	mut best := QuerySchemaBestIndexMatch{}
	for index in schema.indexes {
		if !query_schema_index_matches_filter(schema, index, filter) {
			continue
		}
		score := core.query_index_score(query_filter_op_name(filter.op), index.stores_row,
			filter.is_field_selector(), select_columns.len)
		if score > best.score {
			best = QuerySchemaBestIndexMatch{
				index: index
				score: score
			}
		}
	}
	return best
}

fn query_schema_index_matches_filter(table TableSchemaDef, index IndexSchemaDef, filter Filter) bool {
	column := index.value_column(table) or { return false }
	return filter_index_eligible(filter.is_field_selector(), index.is_field_selector(),
		index.is_json_path(), index.is_fts(), index.column == filter.column_name, index.field_selector_plugin() == filter.plugin_name,
		index.field_selector() == filter.selector, supported_ops_for_type(column.typ).contains(filter.op))
}

fn query_schema_sample_plan_explain(spec QuerySpec, table_name string, filter Filter) SamplePlanExplain {
	best := query_schema_best_index_match_for_filter(spec.schema, filter,
		[]string{})
	request := sample_plan_request(table_name, filter, best.score >= 0)
	plan := preview_plan_from_spec(spec, request) or { return sample_plan_fallback_explain() }
	return sample_explain_from_preview(build_plan_preview_from_spec(spec,
		request, plan))
}

fn query_schema_filter_shapes_for_target(spec QuerySpec, table_name string, column_name string, plugin_name string, selector string, value_type ColumnType, projection_names []string) []FilterShapeCapability {
	schema := spec.schema
	mut shapes := []FilterShapeCapability{}
	for op in supported_ops_for_type(value_type) {
		filter := sample_filter(column_name, plugin_name, selector, value_type, op)
		best := query_schema_best_index_match_for_filter(schema, filter, []string{})
		shapes << filter_shape_capability(filter, value_type, op, projection_names, best.score,
			if best.score >= 0 { best.index.name } else { '' }, query_schema_sample_plan_explain(spec,
			table_name, filter))
	}
	return shapes
}

fn query_schema_order_shapes_for_target(spec QuerySpec, table_name string, column_name string, plugin_name string, selector string, value_type ColumnType) []OrderCapability {
	mut shapes := []OrderCapability{}
	if !supports_order_shapes(plugin_name, selector) {
		return shapes
	}
	for op in supported_ops_for_type(value_type) {
		for direction in [OrderDirection.asc, .desc] {
			request := Request{
				table_name: table_name
				filters:    [
					sample_filter(column_name, plugin_name, selector, value_type, op),
				]
				order_by:   Order{
					column_name: column_name
					direction:   direction
				}
				limit:      10
			}
			plan := preview_plan_from_spec(spec, request) or { continue }
			preview := build_plan_preview_from_spec(spec, request, plan)
			shapes << order_capability(column_name, direction, op, plan, preview)
		}
	}
	return shapes
}

fn query_schema_field_selector_entries_from_indexes(spec QuerySpec, table_name string) map[string]FieldSelectorCapability {
	schema := spec.schema
	mut entries := map[string]FieldSelectorCapability{}
	for index in schema.indexes {
		meta := index.field_selector_meta() or { continue }
		key := field_selector_key(index.column, meta.plugin_name, meta.selector)
		mut current := entries[key] or {
			field_selector_capability(index.column, meta.plugin_name, meta.selector, meta.value_type,
				meta.stores_row, supported_ops_for_type(meta.value_type), query_schema_planner_hints_for_target(spec,
				index.column, meta.plugin_name, meta.selector, meta.value_type), supported_fts_kinds_for_selector(meta.plugin_name,
				meta.selector), query_schema_fts_shapes_for_selector(spec, index.column,
				meta.plugin_name, meta.selector))
		}
		mut index_names := current.index_names.clone()
		index_names << index.name
		current = FieldSelectorCapability{
			...current
			stores_row:    current.stores_row || meta.stores_row
			index_names:   index_names
			filter_shapes: query_schema_filter_shapes_for_target(spec, table_name,
				index.column, meta.plugin_name, meta.selector, meta.value_type, current.projection_names)
			order_shapes:  []OrderCapability{}
		}
		entries[key] = current
	}
	return entries
}

fn query_schema_sorted_projector_names(projectors map[string]ProjectionDef) []string {
	mut names := projectors.keys()
	names.sort()
	return names
}

fn query_schema_projection_metrics_and_field_selectors(spec QuerySpec, table_name string, mut field_selector_entries map[string]FieldSelectorCapability) []ProjectionCapability {
	mut metrics := []ProjectionCapability{}
	for name in query_schema_sorted_projector_names(spec.projections) {
		projector := spec.projections[name] or { continue }
		if projector.table_name != table_name {
			continue
		}
		metrics << projection_metric_capability(projector.name, projector.column_name,
			projector.source_json_path, if meta := projector.field_projection_meta() {
			meta.plugin_name
		} else {
			''
		}, if meta := projector.field_projection_meta() {
			meta.selector
		} else {
			''
		}, if meta := projector.field_projection_meta() {
			meta.value_type
		} else {
			ColumnType.i64_
		}, projector.aggregate, projector.priority, projector.cost_hint)
		selector_meta := projector.field_projection_meta() or { continue }
		key := field_selector_key(projector.column_name, selector_meta.plugin_name, selector_meta.selector)
		mut current := field_selector_entries[key] or {
			field_selector_capability(projector.column_name, selector_meta.plugin_name,
				selector_meta.selector, selector_meta.value_type, selector_meta.stores_row,
				supported_ops_for_type(selector_meta.value_type), query_schema_planner_hints_for_target(spec,
				projector.column_name, selector_meta.plugin_name, selector_meta.selector,
				selector_meta.value_type), supported_fts_kinds_for_selector(selector_meta.plugin_name,
				selector_meta.selector), query_schema_fts_shapes_for_selector(spec, projector.column_name,
				selector_meta.plugin_name, selector_meta.selector))
		}
		mut projection_names := current.projection_names.clone()
		projection_names << projector.name
		current = FieldSelectorCapability{
			...current
			projection_names: projection_names
			filter_shapes:    query_schema_filter_shapes_for_target(spec,
				table_name, projector.column_name, selector_meta.plugin_name, selector_meta.selector,
				selector_meta.value_type, projection_names)
			order_shapes:     []OrderCapability{}
		}
		field_selector_entries[key] = current
	}
	return metrics
}

fn query_schema_sorted_field_selectors(entries map[string]FieldSelectorCapability) []FieldSelectorCapability {
	mut selectors := []FieldSelectorCapability{}
	for _, selector in entries {
		selectors << selector
	}
	selectors.sort_with_compare(fn (a &FieldSelectorCapability, b &FieldSelectorCapability) int {
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
	return selectors
}

fn query_schema_fts_shapes_for_index(spec QuerySpec, index IndexSchemaDef) []FtsShapeCapability {
	schema := spec.schema
	if !index.is_fts() {
		return []FtsShapeCapability{}
	}
	mut shapes := []FtsShapeCapability{}
	for kind in [FtsKind.term, .prefix, .all, .any] {
		plan := preview_general_fts_from_spec(spec, GeneralFtsRequest{
			table_name: schema.name
			index_name: index.name
			kind:       kind
			terms:      sample_fts_terms(kind)
			limit:      10
		}) or { continue }
		shapes << FtsShapeCapability{
			kind:             kind
			indexed:          true
			index_name:       index.name
			planner_strategy: plan.strategy
			sample_explain:   sample_general_fts_explain(plan)
		}
	}
	return shapes
}

fn query_schema_markdown_fts_scope(selector string) FtsScope {
	parts := selector.split(':')
	if parts.len == 1 {
		return .any
	}
	return match parts[1] {
		'heading' { .heading }
		'paragraph' { .paragraph }
		'code_block' { .code_block }
		'list_item' { .list_item }
		else { .any }
	}
}

fn query_schema_fts_shapes_for_selector(spec QuerySpec, column_name string, plugin_name string, selector string) []FtsShapeCapability {
	kinds := supported_fts_kinds_for_selector(plugin_name, selector)
	if kinds.len == 0 {
		return []FtsShapeCapability{}
	}
	scope := query_schema_markdown_fts_scope(selector)
	mut shapes := []FtsShapeCapability{}
	for kind in kinds {
		preview := preview_fts_details_from_spec(spec, FtsRequest{
			table_name:  spec.schema.name
			column_name: column_name
			scope:       scope
			kind:        kind
			terms:       sample_fts_terms(kind)
			limit:       10
		}) or { continue }
		shapes << FtsShapeCapability{
			kind:             kind
			indexed:          preview.plan.index_name.len > 0
			index_name:       preview.plan.index_name
			planner_strategy: preview.plan.strategy
			sample_explain:   sample_fts_explain_from_preview(preview)
		}
	}
	return shapes
}
