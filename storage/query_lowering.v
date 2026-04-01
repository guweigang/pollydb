module storage

pub struct QueryPredicateTarget {
pub:
	column_name string
	plugin_name string
	selector    string
}

pub struct QueryPredicateSpec {
pub:
	target           QueryPredicateTarget
	op               QueryFilterOp
	value            ColumnValue
	second_value     ColumnValue = NullValue{}
	has_second_value bool
}

pub struct QueryLoweringRequest {
pub:
	table_name     string
	predicates     []QueryPredicateSpec
	select_columns []string
	limit          int
}

pub fn QueryPredicateSpec.column_eq(column_name string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op: .eq
		value: clone_column_value(value)
	}
}

pub fn QueryPredicateSpec.column_prefix(column_name string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op: .prefix
		value: clone_column_value(value)
	}
}

pub fn QueryPredicateSpec.column_after(column_name string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op: .after
		value: clone_column_value(value)
	}
}

pub fn QueryPredicateSpec.column_before(column_name string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op: .before
		value: clone_column_value(value)
	}
}

pub fn QueryPredicateSpec.column_between(column_name string, start_value ColumnValue, end_value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op: .between
		value: clone_column_value(start_value)
		second_value: clone_column_value(end_value)
		has_second_value: true
	}
}

pub fn QueryPredicateSpec.field_eq(column_name string, plugin_name string, selector string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		op: .eq
		value: clone_column_value(value)
	}
}

pub fn QueryPredicateSpec.field_prefix(column_name string, plugin_name string, selector string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		op: .prefix
		value: clone_column_value(value)
	}
}

pub fn QueryPredicateSpec.field_after(column_name string, plugin_name string, selector string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		op: .after
		value: clone_column_value(value)
	}
}

pub fn QueryPredicateSpec.field_before(column_name string, plugin_name string, selector string, value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		op: .before
		value: clone_column_value(value)
	}
}

pub fn QueryPredicateSpec.field_between(column_name string, plugin_name string, selector string, start_value ColumnValue, end_value ColumnValue) QueryPredicateSpec {
	return QueryPredicateSpec{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		op: .between
		value: clone_column_value(start_value)
		second_value: clone_column_value(end_value)
		has_second_value: true
	}
}

pub fn (database PersistentDatabase) lower_query_request(input QueryLoweringRequest) !QueryRequest {
	schema := database.table_query_schema(input.table_name)!
	mut filters := []QueryFilter{cap: input.predicates.len}
	for predicate in input.predicates {
		filters << lower_query_predicate(schema, predicate)!
	}
	return QueryRequest{
		table_name: input.table_name
		filters: filters
		select_columns: input.select_columns.clone()
		limit: input.limit
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
			.eq { QueryFilter.field_eq(predicate.target.column_name, predicate.target.plugin_name, predicate.target.selector, predicate.value) }
			.prefix { QueryFilter.field_prefix(predicate.target.column_name, predicate.target.plugin_name, predicate.target.selector, predicate.value) }
			.after { QueryFilter.field_after(predicate.target.column_name, predicate.target.plugin_name, predicate.target.selector, predicate.value) }
			.before { QueryFilter.field_before(predicate.target.column_name, predicate.target.plugin_name, predicate.target.selector, predicate.value) }
			.between { QueryFilter.field_between(predicate.target.column_name, predicate.target.plugin_name, predicate.target.selector, predicate.value, predicate.second_value) }
		}
	}
	return match predicate.op {
		.eq { QueryFilter.eq(predicate.target.column_name, predicate.value) }
		.prefix { QueryFilter.prefix(predicate.target.column_name, predicate.value) }
		.after { QueryFilter.after(predicate.target.column_name, predicate.value) }
		.before { QueryFilter.before(predicate.target.column_name, predicate.value) }
		.between { QueryFilter.between(predicate.target.column_name, predicate.value, predicate.second_value) }
	}
}
