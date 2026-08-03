module query

import core
import storage
import time

fn fetch_query_rows_profiled_query(session storage.DatabaseSession, mut db storage.PersistentDatabase, schema TableSchemaDef, plan Plan, request Request) !QueryFetchedProfile {
	fetch := query_index_fetch_spec_query(schema, plan, request)
	mut scan_sw := time.new_stopwatch()
	if query_plan_uses_ordered_index_scan_query(fetch) {
		if fetch.push_projection {
			mut reader := session.index_reader(mut db, plan.table_name, plan.index_name)!
			projected_rows := reader.find_rows_covering_ordered_projected(storage_value_query(request.start_index_value),
				request.has_start_index_value, request.start_primary_key, fetch.fetch_limit,
				fetch.projected_columns, fetch.base_strategy == 'index_order_desc')!
			return QueryFetchedProfile{
				rows:    query_rows_from_storage(projected_rows)
				scan_ms: scan_sw.elapsed().milliseconds()
			}
		}
		rows := session.lookup_index_ordered(mut db, plan.table_name, plan.index_name,
			storage_value_query(request.start_index_value), request.has_start_index_value,
			request.start_primary_key, fetch.fetch_limit, fetch.base_strategy == 'index_order_desc')!
		return QueryFetchedProfile{
			rows:    query_rows_from_storage(rows)
			scan_ms: scan_sw.elapsed().milliseconds()
		}
	}
	if query_plan_uses_reverse_filtered_order_query(plan) {
		rows := query_rows_from_database_reverse_filtered_index_query(session, mut db, plan, fetch)!
		return QueryFetchedProfile{
			rows:    rows
			scan_ms: scan_sw.elapsed().milliseconds()
		}
	}
	rows := query_rows_from_database_filtered_index_query(session, mut db, plan, fetch)!
	return QueryFetchedProfile{
		rows:    rows
		scan_ms: scan_sw.elapsed().milliseconds()
	}
}

fn fetch_query_rows_profiled_in_transaction_query(session storage.TransactionSession, schema TableSchemaDef, plan Plan, request Request) !QueryFetchedProfile {
	fetch := query_index_fetch_spec_query(schema, plan, request)
	mut scan_sw := time.new_stopwatch()
	if query_plan_uses_ordered_index_scan_query(fetch) {
		rows := if fetch.push_projection {
			session.lookup_index_ordered_projected(plan.table_name, plan.index_name,
				storage_value_query(request.start_index_value), request.has_start_index_value,
				request.start_primary_key, fetch.fetch_limit, fetch.projected_columns,
				fetch.base_strategy == 'index_order_desc')!
		} else {
			session.lookup_index_ordered(plan.table_name, plan.index_name,
				storage_value_query(request.start_index_value), request.has_start_index_value,
				request.start_primary_key, fetch.fetch_limit,
				fetch.base_strategy == 'index_order_desc')!
		}
		return QueryFetchedProfile{
			rows:    query_rows_from_storage(rows)
			scan_ms: scan_sw.elapsed().milliseconds()
		}
	}
	if query_plan_uses_reverse_filtered_order_query(plan) {
		rows := query_rows_from_transaction_reverse_filtered_index_query(session, plan, fetch)!
		if rows.len > 0 {
			return QueryFetchedProfile{
				rows:    rows
				scan_ms: scan_sw.elapsed().milliseconds()
			}
		}
	}
	rows := query_rows_from_transaction_filtered_index_query(session, plan, fetch)!
	return QueryFetchedProfile{
		rows:    rows
		scan_ms: scan_sw.elapsed().milliseconds()
	}
}

fn query_index_fetch_spec_query(schema TableSchemaDef, plan Plan, request Request) QueryIndexFetchSpec {
	return QueryIndexFetchSpec{
		fetch_limit:       fetch_limit(plan.post_filter_count, plan.limit)
		push_projection:   query_can_push_projection_query(schema, plan, request.select_columns)
		projected_columns: query_projected_fetch_columns_query(plan, request.select_columns)
		base_strategy:     core.query_plan_base_strategy(plan.strategy)
	}
}

fn query_rows_from_database_reverse_filtered_index_query(session storage.DatabaseSession, mut db storage.PersistentDatabase, plan Plan, fetch QueryIndexFetchSpec) ![]QueryRow {
	return match plan.index_filter.op {
		.prefix {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_prefix_reverse_projected(mut db,
					plan.table_name, plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_prefix_reverse(mut db,
					plan.table_name, plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.before {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_before_reverse_projected(mut db,
					plan.table_name, plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_before_reverse(mut db,
					plan.table_name, plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.after {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_after_reverse_projected(mut db,
					plan.table_name, plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_after_reverse(mut db, plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.between {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_between_reverse_projected(mut db,
					plan.table_name, plan.index_name, storage_value_query(plan.index_filter.value),
					storage_value_query(plan.index_filter.second_value), fetch.fetch_limit,
					fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_between_reverse(mut db,
					plan.table_name, plan.index_name, storage_value_query(plan.index_filter.value),
					storage_value_query(plan.index_filter.second_value), fetch.fetch_limit)!)
			}
		}
		else {
			[]QueryRow{}
		}
	}
}

fn query_rows_from_transaction_reverse_filtered_index_query(session storage.TransactionSession, plan Plan, fetch QueryIndexFetchSpec) ![]QueryRow {
	return match plan.index_filter.op {
		.prefix {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_prefix_reverse_projected(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_prefix_reverse(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.before {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_before_reverse_projected(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_before_reverse(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.after {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_after_reverse_projected(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_after_reverse(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.between {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_between_reverse_projected(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					storage_value_query(plan.index_filter.second_value), fetch.fetch_limit,
					fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_between_reverse(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					storage_value_query(plan.index_filter.second_value), fetch.fetch_limit)!)
			}
		}
		else {
			[]QueryRow{}
		}
	}
}

fn query_rows_from_database_filtered_index_query(session storage.DatabaseSession, mut db storage.PersistentDatabase, plan Plan, fetch QueryIndexFetchSpec) ![]QueryRow {
	return match plan.index_filter.op {
		.prefix {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_prefix_projected(mut db,
					plan.table_name, plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_prefix(mut db, plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.after {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_after_projected(mut db,
					plan.table_name, plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_after(mut db, plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.before {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_before_projected(mut db,
					plan.table_name, plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_before(mut db, plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.between {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_between_projected(mut db,
					plan.table_name, plan.index_name, storage_value_query(plan.index_filter.value),
					storage_value_query(plan.index_filter.second_value), fetch.fetch_limit,
					fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_between(mut db, plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					storage_value_query(plan.index_filter.second_value), fetch.fetch_limit)!)
			}
		}
		.eq {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_projected(mut db, plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index(mut db, plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
	}
}

fn query_rows_from_transaction_filtered_index_query(session storage.TransactionSession, plan Plan, fetch QueryIndexFetchSpec) ![]QueryRow {
	return match plan.index_filter.op {
		.prefix {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_prefix_projected(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_prefix(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.after {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_after_projected(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_after(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.before {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_before_projected(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_before(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit)!)
			}
		}
		.between {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_between_projected(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					storage_value_query(plan.index_filter.second_value), fetch.fetch_limit,
					fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index_between(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					storage_value_query(plan.index_filter.second_value), fetch.fetch_limit)!)
			}
		}
		.eq {
			if fetch.push_projection {
				query_rows_from_storage(session.lookup_index_projected(plan.table_name,
					plan.index_name, storage_value_query(plan.index_filter.value),
					fetch.fetch_limit, fetch.projected_columns)!)
			} else {
				query_rows_from_storage(session.lookup_index(plan.table_name, plan.index_name,
					storage_value_query(plan.index_filter.value), fetch.fetch_limit)!)
			}
		}
	}
}

fn query_row_anchor_field_selector_value(root_dir string, column ColumnSchemaDef, row QueryRow, filter Filter) !QueryValue {
	index := storage_field_selector_index_query('__query_anchor__', column.name,
		filter.plugin_name, filter.selector, query_value_type_query(filter.value)!, false)!
	values := storage.expand_field_selector_index_values(root_dir,
		storage_column_schema_query(column), storage_value_query(row.data.get(column.name)!), index)!
	mut matched := []QueryValue{}
	for value in values {
		query_value := query_value_from_storage(value)
		if value_matches_filter_query(query_value, filter) {
			matched << query_value
		}
	}
	if matched.len == 0 {
		return null_query_value()
	}
	mut best := matched[0]
	for value in matched[1..] {
		if compare_query_values(value, best) > 0 {
			best = value
		}
	}
	return best
}

fn query_row_matches_field_selector(root_dir string, column ColumnSchemaDef, row QueryRow, filter Filter) !bool {
	stored := if row.data.has(column.name) {
		storage_value_query(row.data.get(column.name)!)
	} else {
		storage.NullValue{}
	}
	value_type := query_value_type_query(filter.value)!
	index := storage_field_selector_index_query('__query_filter__', column.name,
		filter.plugin_name, filter.selector, value_type, false)!
	values := storage.expand_field_selector_index_values(root_dir,
		storage_column_schema_query(column), stored, index)!
	for candidate in values {
		if value_matches_filter_query(query_value_from_storage(candidate), filter) {
			return true
		}
	}
	return false
}
