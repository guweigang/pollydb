module storage

pub struct SqlPredicateAdapterInput {
pub:
	target           QueryPredicateTarget
	kind             SqlFilterKind
	value            ColumnValue
	second_value     ColumnValue = NullValue{}
	has_second_value bool
	source_sql       string
}

pub fn sql_supported_filter_kinds() []SqlFilterKind {
	return [.eq, .like_prefix, .gt, .lt, .between]
}

pub fn adapt_sql_predicate_fragment(input SqlPredicateAdapterInput) !SqlFilterFragment {
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
		target: input.target
		kind: input.kind
		value: clone_column_value(input.value)
		second_value: clone_column_value(input.second_value)
		has_second_value: input.has_second_value
	}
}
