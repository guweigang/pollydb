module storage

pub struct FtsQueryPlan {
pub:
	table_name  string
	column_name string
	scope       FtsScope
	kind        FtsQueryKind
	strategy    string
	index_name  string
	selector    string
	term_count  int
	limit       int
}

pub struct FtsQueryPreview {
pub:
	plan     FtsQueryPlan
	warnings []string
	notes    []string
}

pub struct FtsQueryResult {
pub:
	rows  []TypedSchemaRow
	plan  FtsQueryPlan
}

pub fn fts_selector(scope FtsScope) string {
	return match scope {
		.any { 'fts' }
		else { 'fts:${fts_scope_name(scope)}' }
	}
}

pub fn (database PersistentDatabase) preview_fts_query(query FtsQuery) !FtsQueryPlan {
	spec := database.table_spec(query.table_name)!
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	return plan_fts_query(spec, normalized)
}

pub fn (database PersistentDatabase) preview_fts_query_details(query FtsQuery) !FtsQueryPreview {
	spec := database.table_spec(query.table_name)!
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	plan := plan_fts_query(spec, normalized)
	return build_fts_query_preview(spec, normalized, plan)
}

pub fn (session DatabaseSession) preview_fts_query(query FtsQuery) !FtsQueryPlan {
	spec := session.table_spec(query.table_name)!
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	return plan_fts_query(spec, normalized)
}

pub fn (session DatabaseSession) preview_fts_query_details(query FtsQuery) !FtsQueryPreview {
	spec := session.table_spec(query.table_name)!
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	plan := plan_fts_query(spec, normalized)
	return build_fts_query_preview(spec, normalized, plan)
}

pub fn (session DatabaseSession) query_fts(mut db PersistentDatabase, query FtsQuery) !FtsQueryResult {
	spec := session.table_spec(query.table_name)!
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	plan := plan_fts_query(spec, normalized)
	mut rows := if plan.index_name.len > 0 {
		query_fts_rows_from_database_index(session, mut db, normalized, plan)!
	} else {
		query_fts_rows_from_database_scan(session, mut db, spec, normalized)!
	}
	rows = project_query_rows(rows, normalized.select_columns)!
	return FtsQueryResult{
		rows: rows
		plan: plan
	}
}

pub fn (session TransactionSession) preview_fts_query(query FtsQuery) !FtsQueryPlan {
	spec := session.working_set.transaction().specs[query.table_name] or {
		return error('typed table not registered: ${query.table_name}')
	}
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	return plan_fts_query(spec, normalized)
}

pub fn (session TransactionSession) preview_fts_query_details(query FtsQuery) !FtsQueryPreview {
	spec := session.working_set.transaction().specs[query.table_name] or {
		return error('typed table not registered: ${query.table_name}')
	}
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	plan := plan_fts_query(spec, normalized)
	return build_fts_query_preview(spec, normalized, plan)
}

pub fn (session TransactionSession) query_fts(query FtsQuery) !FtsQueryResult {
	spec := session.working_set.transaction().specs[query.table_name] or {
		return error('typed table not registered: ${query.table_name}')
	}
	normalized := normalize_fts_query(query)
	validate_fts_query_request(spec, normalized)!
	plan := plan_fts_query(spec, normalized)
	mut rows := if plan.index_name.len > 0 && normalized.kind != .prefix {
		query_fts_rows_from_transaction_index(session, normalized, plan)!
	} else {
		query_fts_rows_from_transaction_scan(session, spec, normalized)!
	}
	rows = project_query_rows(rows, normalized.select_columns)!
	return FtsQueryResult{
		rows: rows
		plan: plan
	}
}

fn normalize_fts_query(query FtsQuery) FtsQuery {
	mut seen := map[string]bool{}
	mut terms := []string{}
	for term in fts_normalize_terms(query.terms) {
		if seen[term] {
			continue
		}
		seen[term] = true
		terms << term
	}
	return FtsQuery{
		...query
		terms: terms
	}
}

fn validate_fts_query_request(spec TypedTableSpec, query FtsQuery) ! {
	validate_fts_query(query)!
	column := spec.table.column(query.column_name)!
	if column.typ != .markdown_ {
		return error('fts query requires markdown column: ${query.column_name}')
	}
	for column_name in query.select_columns {
		if !spec.table.has_column(column_name) {
			return error('fts query select column not found: ${column_name}')
		}
	}
}

fn plan_fts_query(spec TypedTableSpec, query FtsQuery) FtsQueryPlan {
	selector := fts_selector(query.scope)
	index := fts_query_index_for_selector(spec, query.column_name, selector) or { SchemaIndexDef{} }
	strategy := if index.name.len > 0 {
		match query.kind {
			.term { 'index_exact' }
			.prefix { 'index_prefix' }
			.all { 'fts_index_all' }
			.any { 'fts_index_any' }
		}
	} else {
		'fts_scan_${fts_query_kind_name(query.kind)}'
	}
	return FtsQueryPlan{
		table_name: query.table_name
		column_name: query.column_name
		scope: query.scope
		kind: query.kind
		strategy: strategy
		index_name: index.name
		selector: selector
		term_count: query.terms.len
		limit: query.limit
	}
}

fn build_fts_query_preview(spec TypedTableSpec, query FtsQuery, plan FtsQueryPlan) FtsQueryPreview {
	mut warnings := []string{}
	mut notes := []string{}
	if plan.index_name.len == 0 {
		warnings << 'No matching Markdown FTS derived index found; query will fall back to table scan.'
	}
	match query.kind {
		.all {
			notes << 'Planner will intersect exact FTS term matches across ${query.terms.len} term(s).'
		}
		.any {
			notes << 'Planner will union exact FTS term matches across ${query.terms.len} term(s).'
		}
		.term, .prefix {}
	}
	return FtsQueryPreview{
		plan: plan
		warnings: warnings
		notes: notes
	}
}

fn fts_query_index_for_selector(spec TypedTableSpec, column_name string, selector string) ?SchemaIndexDef {
	for index in spec.indexes {
		if !index.is_field_selector() {
			continue
		}
		if index.column != column_name {
			continue
		}
		if index.field_selector_plugin() == 'markdown' && index.field_selector() == selector {
			return index
		}
	}
	return none
}

fn query_fts_rows_from_database_index(session DatabaseSession, mut db PersistentDatabase, query FtsQuery, plan FtsQueryPlan) ![]TypedSchemaRow {
	return match query.kind {
		.term {
			session.lookup_index(mut db, query.table_name, plan.index_name, query.terms[0], query.limit)!
		}
		.prefix {
			session.lookup_index_prefix(mut db, query.table_name, plan.index_name, query.terms[0],
				query.limit)!
		}
		.all {
			fts_intersect_database_index_rows(session, mut db, query.table_name, plan.index_name,
				query.terms, query.limit)!
		}
		.any {
			fts_union_database_index_rows(session, mut db, query.table_name, plan.index_name, query.terms,
				query.limit)!
		}
	}
}

fn query_fts_rows_from_transaction_index(session TransactionSession, query FtsQuery, plan FtsQueryPlan) ![]TypedSchemaRow {
	return match query.kind {
		.term {
			session.lookup_index(query.table_name, plan.index_name, query.terms[0], query.limit)!
		}
		.prefix { []TypedSchemaRow{} }
		.all {
			fts_intersect_transaction_index_rows(session, query.table_name, plan.index_name, query.terms,
				query.limit)!
		}
		.any {
			fts_union_transaction_index_rows(session, query.table_name, plan.index_name, query.terms,
				query.limit)!
		}
	}
}

fn query_fts_rows_from_database_scan(session DatabaseSession, mut db PersistentDatabase, spec TypedTableSpec, query FtsQuery) ![]TypedSchemaRow {
	rows := session.scan_table(mut db, query.table_name, 0)!
	return fts_filter_rows_by_scan(db.root_dir, spec.table, query, rows)
}

fn query_fts_rows_from_transaction_scan(session TransactionSession, spec TypedTableSpec, query FtsQuery) ![]TypedSchemaRow {
	rows := session.scan_table(query.table_name, 0)!
	return fts_filter_rows_by_scan(session.root_dir, spec.table, query, rows)
}

fn fts_intersect_database_index_rows(session DatabaseSession, mut db PersistentDatabase, table_name string, index_name string, terms []string, limit int) ![]TypedSchemaRow {
	mut matched := map[string]TypedSchemaRow{}
	for idx, term in terms {
		rows := session.lookup_index(mut db, table_name, index_name, term, 0)!
		if idx == 0 {
			for row in rows {
				matched[fts_primary_key_key(row.primary_key)] = row
			}
			continue
		}
		mut current := map[string]bool{}
		for row in rows {
			current[fts_primary_key_key(row.primary_key)] = true
		}
		for key, _ in matched {
			if key !in current {
				matched.delete(key)
			}
		}
		if matched.len == 0 {
			break
		}
	}
	return fts_sorted_rows_from_map(matched, limit)
}

fn fts_union_database_index_rows(session DatabaseSession, mut db PersistentDatabase, table_name string, index_name string, terms []string, limit int) ![]TypedSchemaRow {
	mut matched := map[string]TypedSchemaRow{}
	for term in terms {
		rows := session.lookup_index(mut db, table_name, index_name, term, 0)!
		for row in rows {
			matched[fts_primary_key_key(row.primary_key)] = row
		}
	}
	return fts_sorted_rows_from_map(matched, limit)
}

fn fts_intersect_transaction_index_rows(session TransactionSession, table_name string, index_name string, terms []string, limit int) ![]TypedSchemaRow {
	mut matched := map[string]TypedSchemaRow{}
	for idx, term in terms {
		rows := session.lookup_index(table_name, index_name, term, 0)!
		if idx == 0 {
			for row in rows {
				matched[fts_primary_key_key(row.primary_key)] = row
			}
			continue
		}
		mut current := map[string]bool{}
		for row in rows {
			current[fts_primary_key_key(row.primary_key)] = true
		}
		for key, _ in matched {
			if key !in current {
				matched.delete(key)
			}
		}
		if matched.len == 0 {
			break
		}
	}
	return fts_sorted_rows_from_map(matched, limit)
}

fn fts_union_transaction_index_rows(session TransactionSession, table_name string, index_name string, terms []string, limit int) ![]TypedSchemaRow {
	mut matched := map[string]TypedSchemaRow{}
	for term in terms {
		rows := session.lookup_index(table_name, index_name, term, 0)!
		for row in rows {
			matched[fts_primary_key_key(row.primary_key)] = row
		}
	}
	return fts_sorted_rows_from_map(matched, limit)
}

fn fts_filter_rows_by_scan(root_dir string, table TableDef, query FtsQuery, rows []TypedSchemaRow) ![]TypedSchemaRow {
	column := table.column(query.column_name)!
	index := SchemaIndexDef.field_selector('__fts_scan__', column.name, 'markdown', fts_selector(query.scope),
		.string_, false)!
	mut matched := []TypedSchemaRow{}
	for row in rows {
		stored := if row.data.has(column.name) { row.data.get(column.name)! } else { NullValue{} }
		values := expand_field_selector_index_values(root_dir, column, stored, index)!
		if fts_values_match_query(values, query) {
			matched << row
		}
	}
	fts_sort_rows(mut matched)
	if query.limit > 0 && matched.len > query.limit {
		return matched[..query.limit]
	}
	return matched
}

fn fts_values_match_query(values []ColumnValue, query FtsQuery) bool {
	mut terms := map[string]bool{}
	for value in values {
		match value {
			string { terms[value] = true }
			else {}
		}
	}
	match query.kind {
		.term {
			return query.terms[0] in terms
		}
		.prefix {
			for term, _ in terms {
				if term.starts_with(query.terms[0]) {
					return true
				}
			}
			return false
		}
		.all {
			for term in query.terms {
				if term !in terms {
					return false
				}
			}
			return true
		}
		.any {
			for term in query.terms {
				if term in terms {
					return true
				}
			}
			return false
		}
	}
}

fn fts_primary_key_key(primary_key []u8) string {
	return primary_key.hex()
}

fn fts_sort_rows(mut rows []TypedSchemaRow) {
	rows.sort_with_compare(fn (a &TypedSchemaRow, b &TypedSchemaRow) int {
		return compare_key_bytes(a.primary_key, b.primary_key)
	})
}

fn fts_sorted_rows_from_map(rows_map map[string]TypedSchemaRow, limit int) []TypedSchemaRow {
	mut rows := []TypedSchemaRow{}
	for _, row in rows_map {
		rows << row
	}
	fts_sort_rows(mut rows)
	if limit > 0 && rows.len > limit {
		return rows[..limit]
	}
	return rows
}
