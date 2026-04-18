module query

pub fn normalized_predicate_from_sql_filter(fragment SqlFilterFragment) !NormalizedPredicate {
	return NormalizedPredicate{
		target:           fragment.target
		op:               sql_filter_kind_to_query_comparison_op(fragment.kind)
		value:            fragment.value
		second_value:     fragment.second_value
		has_second_value: fragment.has_second_value
	}
}
