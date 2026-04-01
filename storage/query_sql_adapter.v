module storage

pub enum SqlFilterKind {
	eq
	like_prefix
	gt
	lt
	between
}

pub struct SqlFilterFragment {
pub:
	target           QueryPredicateTarget
	kind             SqlFilterKind
	value            ColumnValue
	second_value     ColumnValue = NullValue{}
	has_second_value bool
}

pub struct SqlFilterLoweringRequest {
pub:
	table_name     string
	filters        []SqlFilterFragment
	select_columns []string
	limit          int
}

pub fn SqlFilterFragment.column_eq(column_name string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		kind: .eq
		value: clone_column_value(value)
	}
}

pub fn SqlFilterFragment.column_like_prefix(column_name string, prefix string) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		kind: .like_prefix
		value: prefix
	}
}

pub fn SqlFilterFragment.column_gt(column_name string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		kind: .gt
		value: clone_column_value(value)
	}
}

pub fn SqlFilterFragment.column_lt(column_name string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		kind: .lt
		value: clone_column_value(value)
	}
}

pub fn SqlFilterFragment.column_between(column_name string, start_value ColumnValue, end_value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		kind: .between
		value: clone_column_value(start_value)
		second_value: clone_column_value(end_value)
		has_second_value: true
	}
}

pub fn SqlFilterFragment.field_eq(column_name string, plugin_name string, selector string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		kind: .eq
		value: clone_column_value(value)
	}
}

pub fn SqlFilterFragment.field_like_prefix(column_name string, plugin_name string, selector string, prefix string) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		kind: .like_prefix
		value: prefix
	}
}

pub fn SqlFilterFragment.field_gt(column_name string, plugin_name string, selector string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		kind: .gt
		value: clone_column_value(value)
	}
}

pub fn SqlFilterFragment.field_lt(column_name string, plugin_name string, selector string, value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		kind: .lt
		value: clone_column_value(value)
	}
}

pub fn SqlFilterFragment.field_between(column_name string, plugin_name string, selector string, start_value ColumnValue, end_value ColumnValue) SqlFilterFragment {
	return SqlFilterFragment{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		kind: .between
		value: clone_column_value(start_value)
		second_value: clone_column_value(end_value)
		has_second_value: true
	}
}

pub fn (fragment SqlFilterFragment) to_normalized_query_predicate() !NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: fragment.target
		op: sql_filter_kind_to_query_comparison_op(fragment.kind)
		value: clone_column_value(fragment.value)
		second_value: clone_column_value(fragment.second_value)
		has_second_value: fragment.has_second_value
	}
}

pub fn (database PersistentDatabase) lower_sql_filter_request(input SqlFilterLoweringRequest) !QueryRequest {
	mut predicates := []NormalizedQueryPredicate{cap: input.filters.len}
	for filter in input.filters {
		predicates << filter.to_normalized_query_predicate()!
	}
	return database.lower_normalized_query_request(QueryNormalizedLoweringRequest{
		table_name: input.table_name
		predicates: predicates
		select_columns: input.select_columns.clone()
		limit: input.limit
	})
}

fn sql_filter_kind_to_query_comparison_op(kind SqlFilterKind) QueryComparisonOp {
	return match kind {
		.eq { .eq }
		.like_prefix { .prefix }
		.gt { .gt }
		.lt { .lt }
		.between { .between }
	}
}
