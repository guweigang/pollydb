module storage

pub struct QueryPlannerHint {
pub:
	op         QueryFilterOp
	strategy   string
	index_name string
	stores_row bool
	score      int
}

pub struct QueryFilterShapeCapability {
pub:
	op                  QueryFilterOp
	value_type          ColumnType
	indexed             bool
	index_name          string
	planner_strategy    string
	planner_score       int
	projection_only     bool
	continuation_anchor bool
	sample_explain      QuerySamplePlanExplain
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

pub struct QueryColumnCapability {
pub:
	name          string
	typ           ColumnType
	nullable      bool
	filter_ops    []QueryFilterOp
	index_names   []string
	planner_hints []QueryPlannerHint
	filter_shapes []QueryFilterShapeCapability
}

pub struct QueryIndexCapability {
pub:
	name                string
	column_name         string
	value_type          ColumnType
	stores_row          bool
	json_field          string
	field_selector_meta FieldSelectorMeta
	filter_ops          []QueryFilterOp
}

pub struct QueryFieldSelectorCapability {
pub:
	column_name       string
	plugin_name       string
	selector          string
	value_type        ColumnType
	stores_row        bool
	filter_ops        []QueryFilterOp
	index_names       []string
	projection_names  []string
	planner_hints     []QueryPlannerHint
	filter_shapes     []QueryFilterShapeCapability
}

pub struct QueryProjectionCapability {
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

pub struct TableQuerySchema {
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

pub fn query_supported_filter_ops() []QueryFilterOp {
	return [.eq, .prefix, .after, .before, .between]
}

fn query_supported_ops_for_type(typ ColumnType) []QueryFilterOp {
	return match typ {
		.bool_, .json_, .markdown_ { [.eq] }
		.i64_ { [.eq, .after, .before, .between] }
		.string_, .bytes_, .enum_, .datetime_ { [.eq, .prefix, .after, .before, .between] }
	}
}

fn query_sample_value_for_type(typ ColumnType) ColumnValue {
	return match typ {
		.bool_ { ColumnValue(true) }
		.i64_ { ColumnValue(i64(1)) }
		.string_, .enum_, .json_, .datetime_ { ColumnValue('x') }
		.bytes_ { ColumnValue('x'.bytes()) }
		.markdown_ { ColumnValue(MarkdownRef{}) }
	}
}

fn query_sample_filter(column_name string, plugin_name string, selector string, value_type ColumnType, op QueryFilterOp) QueryFilter {
	first := query_sample_value_for_type(value_type)
	second := query_sample_value_for_type(value_type)
	if plugin_name.len > 0 || selector.len > 0 {
		return match op {
			.eq { QueryFilter.field_eq(column_name, plugin_name, selector, first) }
			.prefix { QueryFilter.field_prefix(column_name, plugin_name, selector, first) }
			.after { QueryFilter.field_after(column_name, plugin_name, selector, first) }
			.before { QueryFilter.field_before(column_name, plugin_name, selector, first) }
			.between { QueryFilter.field_between(column_name, plugin_name, selector, first, second) }
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

fn query_planner_hints_for_target(spec TypedTableSpec, column_name string, plugin_name string, selector string, value_type ColumnType) []QueryPlannerHint {
	mut hints := []QueryPlannerHint{}
	for op in query_supported_ops_for_type(value_type) {
		filter := query_sample_filter(column_name, plugin_name, selector, value_type, op)
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
		if best_score < 0 {
			continue
		}
		hints << QueryPlannerHint{
			op: op
			strategy: query_plan_strategy_name(op)
			index_name: best_index.name
			stores_row: best_index.stores_row
			score: best_score
		}
	}
	return hints
}

fn query_sample_plan_explain(spec TypedTableSpec, projectors map[string]AggregateProjectionDef, table_name string, filter QueryFilter) QuerySamplePlanExplain {
	plan := plan_query_request(spec, QueryRequest{
		table_name: table_name
		filters: [filter]
	}) or {
		return QuerySamplePlanExplain{
			strategy: 'table_scan'
			index_name: ''
			warnings: ['Unable to build sample plan preview for this filter shape.']
			notes: []string{}
			default_result_shape: 'page'
			supports_continuation_token: true
		}
	}
	preview := build_query_plan_preview(spec, projectors, QueryRequest{
		table_name: table_name
		filters: [filter]
	}, plan, false)
	return preview.sample_explain()
}

fn query_filter_shapes_for_target(spec TypedTableSpec, projectors map[string]AggregateProjectionDef, table_name string, column_name string, plugin_name string, selector string, value_type ColumnType, projection_names []string) []QueryFilterShapeCapability {
	mut shapes := []QueryFilterShapeCapability{}
	for op in query_supported_ops_for_type(value_type) {
		filter := query_sample_filter(column_name, plugin_name, selector, value_type, op)
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
		shapes << QueryFilterShapeCapability{
			op: op
			value_type: value_type
			indexed: best_score >= 0
			index_name: if best_score >= 0 { best_index.name } else { '' }
			planner_strategy: if best_score >= 0 { query_plan_strategy_name(op) } else { 'table_scan' }
			planner_score: if best_score >= 0 { best_score } else { -1 }
			projection_only: best_score < 0 && projection_names.len > 0
			continuation_anchor: best_score >= 0
			sample_explain: query_sample_plan_explain(spec, projectors, table_name, filter)
		}
	}
	return shapes
}

pub fn (database PersistentDatabase) table_query_schema(table_name string) !TableQuerySchema {
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
			name: column.name
			typ: column.typ
			nullable: column.nullable
			filter_ops: query_supported_ops_for_type(column.typ)
			index_names: index_names
			planner_hints: query_planner_hints_for_target(spec, column.name, '', '', column.typ)
			filter_shapes: query_filter_shapes_for_target(spec, database.projectors, table_name,
				column.name, '', '', column.typ, []string{})
		}
	}
	mut indexes := []QueryIndexCapability{cap: spec.indexes.len}
	for index in spec.indexes {
		value_column := index.value_column(spec.table)!
		indexes << QueryIndexCapability{
			name: index.name
			column_name: index.column
			value_type: value_column.typ
			stores_row: index.stores_row
			json_field: index.json_field
			field_selector_meta: index.field_selector_meta() or { FieldSelectorMeta{} }
			filter_ops: query_supported_ops_for_type(value_column.typ)
		}
	}
	mut field_selector_entries := map[string]QueryFieldSelectorCapability{}
	for index in spec.indexes {
		meta := index.field_selector_meta() or { continue }
		key := '${index.column}\n${meta.plugin_name}\n${meta.selector}'
		mut capability := field_selector_entries[key] or {
			QueryFieldSelectorCapability{
				column_name: index.column
				plugin_name: meta.plugin_name
				selector: meta.selector
				value_type: meta.value_type
				stores_row: meta.stores_row
				filter_ops: query_supported_ops_for_type(meta.value_type)
				index_names: []string{}
				projection_names: []string{}
				planner_hints: query_planner_hints_for_target(spec, index.column, meta.plugin_name,
					meta.selector, meta.value_type)
				filter_shapes: []QueryFilterShapeCapability{}
			}
		}
		mut index_names := capability.index_names.clone()
		index_names << index.name
		field_selector_entries[key] = QueryFieldSelectorCapability{
			...capability
			stores_row: capability.stores_row || meta.stores_row
			index_names: index_names
			filter_shapes: query_filter_shapes_for_target(spec, database.projectors, table_name,
				index.column, meta.plugin_name, meta.selector, meta.value_type,
				capability.projection_names)
		}
	}
	mut projection_metrics := []QueryProjectionCapability{}
	for name in sorted_projector_names(database.projectors) {
		projector := database.projectors[name] or { continue }
		if projector.table_name != table_name {
			continue
		}
		mut capability := QueryProjectionCapability{
			name: projector.name
			column_name: projector.column_name
			source_json_path: projector.source_json_path
			plugin_name: ''
			selector: ''
			value_type: .i64_
			aggregate: projector.aggregate
			priority: projector.priority
			cost_hint: projector.cost_hint
		}
		if selector_meta := projector.field_projection_meta() {
			capability = QueryProjectionCapability{
				...capability
				plugin_name: selector_meta.plugin_name
				selector: selector_meta.selector
				value_type: selector_meta.value_type
			}
			key := '${projector.column_name}\n${selector_meta.plugin_name}\n${selector_meta.selector}'
			mut selector_capability := field_selector_entries[key] or {
				QueryFieldSelectorCapability{
					column_name: projector.column_name
					plugin_name: selector_meta.plugin_name
					selector: selector_meta.selector
					value_type: selector_meta.value_type
					stores_row: selector_meta.stores_row
					filter_ops: query_supported_ops_for_type(selector_meta.value_type)
					index_names: []string{}
					projection_names: []string{}
					planner_hints: query_planner_hints_for_target(spec, projector.column_name,
						selector_meta.plugin_name, selector_meta.selector, selector_meta.value_type)
					filter_shapes: []QueryFilterShapeCapability{}
				}
			}
			mut projection_names := selector_capability.projection_names.clone()
			projection_names << projector.name
			field_selector_entries[key] = QueryFieldSelectorCapability{
				...selector_capability
				projection_names: projection_names
				filter_shapes: query_filter_shapes_for_target(spec, database.projectors, table_name,
					projector.column_name, selector_meta.plugin_name, selector_meta.selector,
					selector_meta.value_type, projection_names)
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
		table_name: spec.table.name
		primary_key: spec.table.primary_key.clone()
		columns: columns
		indexes: indexes
		field_selectors: field_selectors
		projection_metrics: projection_metrics
		supported_filter_ops: query_supported_filter_ops()
		default_result_shape: 'page'
		supports_continuation_token: true
		supports_select_projection: true
	}
}
