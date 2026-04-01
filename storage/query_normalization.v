module storage

pub enum QueryComparisonOp {
	eq
	prefix
	gt
	lt
	between
}

pub struct NormalizedQueryPredicate {
pub:
	target           QueryPredicateTarget
	op               QueryComparisonOp
	value            ColumnValue
	second_value     ColumnValue = NullValue{}
	has_second_value bool
}

pub fn NormalizedQueryPredicate.column_eq(column_name string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op: .eq
		value: clone_column_value(value)
	}
}

pub fn NormalizedQueryPredicate.column_prefix(column_name string, prefix string) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op: .prefix
		value: prefix
	}
}

pub fn NormalizedQueryPredicate.column_gt(column_name string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op: .gt
		value: clone_column_value(value)
	}
}

pub fn NormalizedQueryPredicate.column_lt(column_name string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op: .lt
		value: clone_column_value(value)
	}
}

pub fn NormalizedQueryPredicate.column_between(column_name string, start_value ColumnValue, end_value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
		}
		op: .between
		value: clone_column_value(start_value)
		second_value: clone_column_value(end_value)
		has_second_value: true
	}
}

pub fn NormalizedQueryPredicate.field_eq(column_name string, plugin_name string, selector string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		op: .eq
		value: clone_column_value(value)
	}
}

pub fn NormalizedQueryPredicate.field_prefix(column_name string, plugin_name string, selector string, prefix string) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		op: .prefix
		value: prefix
	}
}

pub fn NormalizedQueryPredicate.field_gt(column_name string, plugin_name string, selector string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		op: .gt
		value: clone_column_value(value)
	}
}

pub fn NormalizedQueryPredicate.field_lt(column_name string, plugin_name string, selector string, value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
		target: QueryPredicateTarget{
			column_name: column_name
			plugin_name: plugin_name
			selector: selector
		}
		op: .lt
		value: clone_column_value(value)
	}
}

pub fn NormalizedQueryPredicate.field_between(column_name string, plugin_name string, selector string, start_value ColumnValue, end_value ColumnValue) NormalizedQueryPredicate {
	return NormalizedQueryPredicate{
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

pub fn (predicate NormalizedQueryPredicate) to_query_predicate_spec() !QueryPredicateSpec {
	return QueryPredicateSpec{
		target: predicate.target
		op: normalized_query_op_to_filter_op(predicate.op)
		value: clone_column_value(predicate.value)
		second_value: clone_column_value(predicate.second_value)
		has_second_value: predicate.has_second_value
	}
}

pub fn (database PersistentDatabase) lower_normalized_query_request(input QueryNormalizedLoweringRequest) !QueryRequest {
	mut predicates := []QueryPredicateSpec{cap: input.predicates.len}
	for predicate in input.predicates {
		predicates << predicate.to_query_predicate_spec()!
	}
	return database.lower_query_request(QueryLoweringRequest{
		table_name: input.table_name
		predicates: predicates
		select_columns: input.select_columns.clone()
		limit: input.limit
	})
}

pub struct QueryNormalizedLoweringRequest {
pub:
	table_name     string
	predicates     []NormalizedQueryPredicate
	select_columns []string
	limit          int
}

fn normalized_query_op_to_filter_op(op QueryComparisonOp) QueryFilterOp {
	return match op {
		.eq { .eq }
		.prefix { .prefix }
		.gt { .after }
		.lt { .before }
		.between { .between }
	}
}
