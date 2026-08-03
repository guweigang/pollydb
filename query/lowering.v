module query

import core

pub fn lower_request(database Database, input LoweringRequest) !Request {
	schema := table_schema(database, input.table_name)!
	return lower_request_with_schema(schema, input)
}

pub fn lower_request_from_spec(spec QuerySpec, input LoweringRequest) !Request {
	schema := table_schema_from_spec(spec, input.table_name)!
	return lower_request_with_schema(schema, input)
}

pub fn lower_request_with_schema(schema TableSchema, input LoweringRequest) !Request {
	mut filters := []Filter{cap: input.predicates.len}
	for predicate in input.predicates {
		filters << lower_query_predicate(schema, predicate)!
	}
	return Request{
		table_name:     input.table_name
		filters:        filters
		select_columns: input.select_columns.clone()
		limit:          input.limit
	}
}

pub fn lower_normalized_request(database Database, input NormalizedLoweringRequest) !Request {
	mut predicates := []PredicateSpec{cap: input.predicates.len}
	for predicate in input.predicates {
		predicates << predicate_spec_from_normalized(predicate)!
	}
	return lower_request(database, LoweringRequest{
		table_name:     input.table_name
		predicates:     predicates
		select_columns: input.select_columns.clone()
		limit:          input.limit
	})
}

pub fn lower_normalized_request_from_spec(spec QuerySpec, input NormalizedLoweringRequest) !Request {
	mut predicates := []PredicateSpec{cap: input.predicates.len}
	for predicate in input.predicates {
		predicates << predicate_spec_from_normalized(predicate)!
	}
	return lower_request_from_spec(spec, LoweringRequest{
		table_name:     input.table_name
		predicates:     predicates
		select_columns: input.select_columns.clone()
		limit:          input.limit
	})
}

pub fn lower_sql_filter_request(database Database, input SqlLoweringRequest) !Request {
	mut predicates := []NormalizedPredicate{cap: input.filters.len}
	for filter in input.filters {
		predicates << normalized_predicate_from_sql_filter(filter)!
	}
	return lower_normalized_request(database, NormalizedLoweringRequest{
		table_name:     input.table_name
		predicates:     predicates
		select_columns: input.select_columns.clone()
		limit:          input.limit
	})
}

pub fn lower_sql_filter_request_from_spec(spec QuerySpec, input SqlLoweringRequest) !Request {
	mut predicates := []NormalizedPredicate{cap: input.filters.len}
	for filter in input.filters {
		predicates << normalized_predicate_from_sql_filter(filter)!
	}
	return lower_normalized_request_from_spec(spec, NormalizedLoweringRequest{
		table_name:     input.table_name
		predicates:     predicates
		select_columns: input.select_columns.clone()
		limit:          input.limit
	})
}

pub fn supported_filter_ops() []FilterOp {
	return [.eq, .prefix, .after, .before, .between]
}

fn lower_query_predicate(schema TableSchema, predicate PredicateSpec) !Filter {
	if predicate.target.column_name.len == 0 {
		return error('query predicate target requires column_name')
	}
	if predicate.target.plugin_name.len > 0 || predicate.target.selector.len > 0 {
		return lower_field_selector_predicate(schema, predicate)
	}
	return lower_column_predicate(schema, predicate)
}

fn lower_column_predicate(schema TableSchema, predicate PredicateSpec) !Filter {
	for column in schema.columns {
		if column.name != predicate.target.column_name {
			continue
		}
		query_lowering_validate_types(column.typ, predicate)!
		query_lowering_validate_shape(column.filter_shapes, predicate.op, 'column `${predicate.target.column_name}`')!
		return query_filter_from_predicate(predicate)
	}
	return error('query column not found in schema: ${predicate.target.column_name}')
}

fn lower_field_selector_predicate(schema TableSchema, predicate PredicateSpec) !Filter {
	if predicate.target.plugin_name.len == 0 || predicate.target.selector.len == 0 {
		return error('field selector predicate requires plugin_name and selector: ${predicate.target.column_name}')
	}
	for selector in schema.field_selectors {
		if selector.column_name != predicate.target.column_name
			|| selector.plugin_name != predicate.target.plugin_name
			|| selector.selector != predicate.target.selector {
			continue
		}
		query_lowering_validate_types(selector.value_type, predicate)!
		query_lowering_validate_shape(selector.filter_shapes, predicate.op,
			'field selector `${predicate.target.column_name}.${predicate.target.plugin_name}:${predicate.target.selector}`')!
		return query_filter_from_predicate(predicate)
	}
	return error('field selector not found in schema: ${predicate.target.column_name}.${predicate.target.plugin_name}:${predicate.target.selector}')
}

fn query_lowering_validate_types(expected_type ColumnType, predicate PredicateSpec) ! {
	value_type := query_value_type_query(predicate.value)!
	if value_type != expected_type {
		return error('query predicate value type mismatch: expected ${expected_type}, got ${value_type}')
	}
	if predicate.has_second_value {
		second_type := query_value_type_query(predicate.second_value)!
		if second_type != expected_type {
			return error('query predicate second value type mismatch: expected ${expected_type}, got ${second_type}')
		}
	}
	validate_query_filter_bounds(predicate.op, predicate.value, predicate.second_value,
		predicate.has_second_value)!
}

fn query_lowering_validate_shape(shapes []FilterShapeCapability, op FilterOp, target_label string) ! {
	for shape in shapes {
		if shape.op == op {
			return
		}
	}
	return error('query predicate op `${query_filter_op_name(op)}` is not supported for ${target_label}')
}

fn query_filter_from_predicate(predicate PredicateSpec) !Filter {
	if predicate.target.plugin_name.len > 0 || predicate.target.selector.len > 0 {
		return match predicate.op {
			.eq {
				Filter.field_eq(predicate.target.column_name, predicate.target.plugin_name,
					predicate.target.selector, predicate.value)
			}
			.prefix {
				Filter.field_prefix(predicate.target.column_name, predicate.target.plugin_name,
					predicate.target.selector, predicate.value)
			}
			.after {
				Filter.field_after(predicate.target.column_name, predicate.target.plugin_name,
					predicate.target.selector, predicate.value)
			}
			.before {
				Filter.field_before(predicate.target.column_name, predicate.target.plugin_name,
					predicate.target.selector, predicate.value)
			}
			.between {
				Filter.field_between(predicate.target.column_name, predicate.target.plugin_name,
					predicate.target.selector, predicate.value, predicate.second_value)
			}
		}
	}
	return match predicate.op {
		.eq { Filter.eq(predicate.target.column_name, predicate.value) }
		.prefix { Filter.prefix(predicate.target.column_name, predicate.value) }
		.after { Filter.after(predicate.target.column_name, predicate.value) }
		.before { Filter.before(predicate.target.column_name, predicate.value) }
		.between { Filter.between(predicate.target.column_name, predicate.value, predicate.second_value) }
	}
}

fn normalized_query_op_to_filter_op(op ComparisonOp) FilterOp {
	return match op {
		.eq { .eq }
		.prefix { .prefix }
		.gt { .after }
		.lt { .before }
		.between { .between }
	}
}

fn sql_filter_kind_to_query_comparison_op(kind SqlFilterKind) ComparisonOp {
	return match kind {
		.eq { .eq }
		.like_prefix { .prefix }
		.gt { .gt }
		.lt { .lt }
		.between { .between }
	}
}

fn validate_query_filter_bounds(op FilterOp, value QueryValue, second_value QueryValue, has_second_value bool) ! {
	prefix_value_compatible := match value.value {
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

fn query_filter_op_name(op FilterOp) string {
	return match op {
		.eq { 'eq' }
		.prefix { 'prefix' }
		.after { 'after' }
		.before { 'before' }
		.between { 'between' }
	}
}
