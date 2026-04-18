module query

pub fn predicate_spec_from_normalized(predicate NormalizedPredicate) !PredicateSpec {
	return PredicateSpec{
		target:           predicate.target
		op:               normalized_query_op_to_filter_op(predicate.op)
		value:            predicate.value
		second_value:     predicate.second_value
		has_second_value: predicate.has_second_value
	}
}
