module query

import core
import storage

fn storage_fts_scope_query(scope FtsScope) storage.FtsScope {
	return unsafe { storage.FtsScope(int(scope)) }
}

fn query_fts_scope_query(scope storage.FtsScope) FtsScope {
	return unsafe { FtsScope(int(scope)) }
}

fn storage_fts_kind_query(kind FtsKind) storage.FtsQueryKind {
	return unsafe { storage.FtsQueryKind(int(kind)) }
}

fn query_fts_kind_query(kind storage.FtsQueryKind) FtsKind {
	return unsafe { FtsKind(int(kind)) }
}

pub fn general_fts_plan_preview(plan GeneralFtsPlan) PlanPreview {
	query_plan := plan.as_query_plan()
	return PlanPreview{
		plan:                        query_plan
		warnings:                    []string{}
		notes:                       [
			'Query will execute against the SQLite FTS5 sidecar for index `${plan.index_name}`.',
		]
		default_result_shape:        'rows'
		supports_continuation_token: false
	}
}

pub fn preview_general_fts_details(database Database, request GeneralFtsRequest) !PlanPreview {
	plan := preview_general_fts(database, request)!
	return general_fts_plan_preview(plan)
}

pub fn preview_general_fts_details_from_spec(spec QuerySpec, request GeneralFtsRequest) !PlanPreview {
	plan := preview_general_fts_from_spec(spec, request)!
	return general_fts_plan_preview(plan)
}

pub fn preview_general_fts_details_in_session(session Session, request GeneralFtsRequest) !PlanPreview {
	plan := preview_general_fts_in_session(session, request)!
	return general_fts_plan_preview(plan)
}

pub fn general_fts_request_from_clause(table_name string, clause GeneralFtsClause, select_columns []string, limit int) GeneralFtsRequest {
	return GeneralFtsRequest{
		table_name:     table_name
		index_name:     clause.index_name
		kind:           clause.kind
		terms:          clause.terms.clone()
		select_columns: select_columns.clone()
		limit:          limit
	}
}

pub fn fts_plan_preview(plan FtsPlan, request FtsRequest) FtsPreview {
	return FtsPreview{
		plan:     plan
		warnings: core.query_fts_preview_warnings(plan.index_name)
		notes:    core.query_fts_preview_notes(fts_kind_name(request.kind), request.terms.len)
	}
}

pub fn preview_fts(database Database, request FtsRequest) !FtsPlan {
	spec := query_spec(database.db.table_spec(request.table_name)!, map[string]ProjectionDef{})
	normalized := normalize_fts_request(request)
	validate_fts_request(spec, normalized)!
	return plan_fts_request(spec, normalized)
}

pub fn preview_fts_from_spec(spec QuerySpec, request FtsRequest) !FtsPlan {
	normalized := normalize_fts_request(request)
	validate_fts_request(spec, normalized)!
	return plan_fts_request(spec, normalized)
}

pub fn preview_fts_details(database Database, request FtsRequest) !FtsPreview {
	plan := preview_fts(database, request)!
	return fts_plan_preview(plan, request)
}

pub fn preview_fts_details_from_spec(spec QuerySpec, request FtsRequest) !FtsPreview {
	plan := preview_fts_from_spec(spec, request)!
	return fts_plan_preview(plan, request)
}

pub fn preview_fts_in_session(session Session, request FtsRequest) !FtsPlan {
	spec := query_spec(session.session.table_spec(request.table_name)!, map[string]ProjectionDef{})
	normalized := normalize_fts_request(request)
	validate_fts_request(spec, normalized)!
	return plan_fts_request(spec, normalized)
}

pub fn preview_fts_details_in_session(session Session, request FtsRequest) !FtsPreview {
	plan := preview_fts_in_session(session, request)!
	return fts_plan_preview(plan, request)
}

pub fn query_fts(session Session, mut database Database, request FtsRequest) !FtsResult {
	spec := query_spec(session.session.table_spec(request.table_name)!, map[string]ProjectionDef{})
	schema := spec.schema
	normalized := normalize_fts_request(request)
	validate_fts_request(spec, normalized)!
	plan := plan_fts_request(spec, normalized)!
	rows := fetch_fts_rows_query(session.session, mut database.db, spec, normalized, plan)!
	ranked_rows, ranked_hits := rank_fts_rows_query(database.db.root_dir, schema, normalized, rows)!
	return FtsResult{
		rows: project_fts_rows(ranked_rows, normalized.select_columns)!
		hits: ranked_hits
		plan: plan
	}
}

pub fn preview_fts_in_transaction(session Transaction, request FtsRequest) !FtsPlan {
	spec := query_spec(session.tx.table_spec(request.table_name)!, map[string]ProjectionDef{})
	normalized := normalize_fts_request(request)
	validate_fts_request(spec, normalized)!
	return plan_fts_request(spec, normalized)
}

pub fn preview_fts_details_in_transaction(session Transaction, request FtsRequest) !FtsPreview {
	plan := preview_fts_in_transaction(session, request)!
	return fts_plan_preview(plan, request)
}

pub fn query_fts_in_transaction(session Transaction, request FtsRequest) !FtsResult {
	spec := query_spec(session.tx.table_spec(request.table_name)!, map[string]ProjectionDef{})
	schema := spec.schema
	normalized := normalize_fts_request(request)
	validate_fts_request(spec, normalized)!
	plan := plan_fts_request(spec, normalized)!
	rows := fetch_fts_rows_in_transaction_query(session.tx, spec, normalized, plan)!
	ranked_rows, ranked_hits := rank_fts_rows_query(session.tx.root_dir, schema, normalized, rows)!
	return FtsResult{
		rows: project_fts_rows(ranked_rows, normalized.select_columns)!
		hits: ranked_hits
		plan: plan
	}
}

pub fn preview_general_fts(database Database, request GeneralFtsRequest) !GeneralFtsPlan {
	spec := query_spec(database.db.table_spec(request.table_name)!, map[string]ProjectionDef{})
	normalized := normalize_general_fts_request(request)
	index := validate_general_fts_request(spec, normalized)!
	return plan_general_fts_request(spec, index, normalized)
}

pub fn preview_general_fts_from_spec(spec QuerySpec, request GeneralFtsRequest) !GeneralFtsPlan {
	normalized := normalize_general_fts_request(request)
	index := validate_general_fts_request(spec, normalized)!
	return plan_general_fts_request(spec, index, normalized)
}

pub fn preview_general_fts_in_session(session Session, request GeneralFtsRequest) !GeneralFtsPlan {
	spec := query_spec(session.session.table_spec(request.table_name)!, map[string]ProjectionDef{})
	normalized := normalize_general_fts_request(request)
	index := validate_general_fts_request(spec, normalized)!
	return plan_general_fts_request(spec, index, normalized)
}

pub fn query_general_fts(mut database Database, branch_name string, request GeneralFtsRequest) !GeneralFtsResult {
	session := database.open_session(branch_name)!
	return query_general_fts_in_session(session, mut database, request)
}

pub fn query_general_fts_in_session(session Session, mut database Database, request GeneralFtsRequest) !GeneralFtsResult {
	spec := query_spec(session.session.table_spec(request.table_name)!, map[string]ProjectionDef{})
	normalized := normalize_general_fts_request(request)
	index := validate_general_fts_request(spec, normalized)!
	plan := plan_general_fts_request(spec, index, normalized)!
	rows, sidecar_hits := fetch_general_fts_rows_query(session.session, mut database.db, normalized)!
	return GeneralFtsResult{
		rows: project_fts_rows(rows, normalized.select_columns)!
		hits: sidecar_hits_to_general_fts_hits_with_snippets(mut database.db, storage_table_def_query(spec.schema)!,
			index,
			normalized, rows, sidecar_hits)
		plan: plan
	}
}

pub fn fts_scope_name(scope FtsScope) string {
	return match scope {
		.any { 'any' }
		.heading { 'heading' }
		.paragraph { 'paragraph' }
		.code_block { 'code_block' }
		.list_item { 'list_item' }
	}
}

pub fn fts_kind_name(kind FtsKind) string {
	return match kind {
		.term { 'term' }
		.prefix { 'prefix' }
		.all { 'all' }
		.any { 'any' }
	}
}

fn normalize_fts_request(request FtsRequest) FtsRequest {
	mut seen := map[string]bool{}
	mut terms := []string{}
	for term in fts_normalize_terms_query(request.terms) {
		if seen[term] {
			continue
		}
		seen[term] = true
		terms << term
	}
	return FtsRequest{
		...request
		terms: terms
	}
}

fn validate_fts_request(spec QuerySpec, request FtsRequest) ! {
	validate_fts_request_query(request)!
	schema := spec.schema
	column := schema.column(request.column_name)!
	if column.typ != .markdown_ {
		return error('fts query requires markdown column: ${request.column_name}')
	}
	for column_name in request.select_columns {
		if !schema.has_column(column_name) {
			return error('fts query select column not found: ${column_name}')
		}
	}
}

fn plan_fts_request(spec QuerySpec, request FtsRequest) !FtsPlan {
	schema := spec.schema
	selector := fts_selector_query(request.scope)
	index := fts_index_for_selector(schema, request.column_name, selector) or { IndexSchemaDef{} }
	strategy := if index.name.len > 0 {
		match request.kind {
			.term { 'index_exact' }
			.prefix { 'index_prefix' }
			.all { 'fts_index_all' }
			.any { 'fts_index_any' }
		}
	} else {
		'fts_scan_${fts_kind_name(request.kind)}'
	}
	return FtsPlan{
		table_name:  request.table_name
		column_name: request.column_name
		scope:       request.scope
		kind:        request.kind
		strategy:    strategy
		index_name:  index.name
		selector:    selector
		term_count:  request.terms.len
		limit:       request.limit
	}
}

fn fts_index_for_selector(schema TableSchemaDef, column_name string, selector string) ?IndexSchemaDef {
	for index in schema.indexes {
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

fn project_fts_rows(rows []QueryRow, select_columns []string) ![]QueryRow {
	if select_columns.len == 0 {
		return rows.clone()
	}
	mut projected := []QueryRow{cap: rows.len}
	for row in rows {
		mut data := QueryRowData{}
		for name in select_columns {
			if row.data.has(name) {
				data.set(name, row.data.get(name)!)
			}
		}
		projected << QueryRow{
			primary_key: row.primary_key.clone()
			data:        data
		}
	}
	return projected
}

fn normalize_general_fts_request(request GeneralFtsRequest) GeneralFtsRequest {
	mut seen := map[string]bool{}
	mut terms := []string{}
	for term in fts_normalize_terms_query(request.terms) {
		if seen[term] {
			continue
		}
		seen[term] = true
		terms << term
	}
	return GeneralFtsRequest{
		...request
		terms: terms
	}
}

fn validate_general_fts_request(spec QuerySpec, request GeneralFtsRequest) !IndexSchemaDef {
	validate_general_fts_request_query(request)!
	schema := spec.schema
	index := general_fts_index_by_name(schema, request.index_name)!
	if !index.is_fts() {
		return error('index is not an fts index: ${request.index_name}')
	}
	for column_name in request.select_columns {
		if !schema.has_column(column_name) {
			return error('general fts query select column not found: ${column_name}')
		}
	}
	return index
}

fn general_fts_index_by_name(schema TableSchemaDef, index_name string) !IndexSchemaDef {
	for index in schema.indexes {
		if index.name == index_name {
			return index
		}
	}
	return error('typed table index not found: ${index_name}')
}

fn fts_selector_query(scope FtsScope) string {
	return match scope {
		.any { 'fts' }
		else { 'fts:${fts_scope_name(scope)}' }
	}
}

fn fts_query_kind_name_query(kind FtsKind) string {
	return match kind {
		.term { 'term' }
		.prefix { 'prefix' }
		.all { 'all' }
		.any { 'any' }
	}
}

fn fts_normalize_term_query(raw string) string {
	return raw.to_lower().trim_space()
}

fn fts_normalize_terms_query(raw_terms []string) []string {
	mut out := []string{}
	for raw in raw_terms {
		normalized := fts_normalize_term_query(raw)
		if normalized.len == 0 {
			continue
		}
		out << normalized
	}
	return out
}

fn validate_fts_request_query(request FtsRequest) ! {
	if request.table_name.len == 0 {
		return error('fts query requires table_name')
	}
	if request.column_name.len == 0 {
		return error('fts query requires column_name')
	}
	if request.terms.len == 0 {
		return error('fts query requires at least one term')
	}
	normalized := fts_normalize_terms_query(request.terms)
	if normalized.len == 0 {
		return error('fts query terms cannot all be empty')
	}
	match request.kind {
		.term, .prefix {
			if normalized.len != 1 {
				return error('fts ${fts_query_kind_name_query(request.kind)} query requires exactly one term')
			}
		}
		.all, .any {}
	}
}

fn validate_general_fts_request_query(request GeneralFtsRequest) ! {
	if request.table_name.len == 0 {
		return error('general fts query requires table_name')
	}
	if request.index_name.len == 0 {
		return error('general fts query requires index_name')
	}
	if request.terms.len == 0 {
		return error('general fts query requires at least one term')
	}
	normalized := fts_normalize_terms_query(request.terms)
	if normalized.len == 0 {
		return error('general fts query terms cannot all be empty')
	}
	match request.kind {
		.term, .prefix {
			if normalized.len != 1 {
				return error('general fts ${fts_query_kind_name_query(request.kind)} query requires exactly one term')
			}
		}
		.all, .any {}
	}
}

fn plan_general_fts_request(spec QuerySpec, index IndexSchemaDef, request GeneralFtsRequest) !GeneralFtsPlan {
	schema := spec.schema
	return GeneralFtsPlan{
		table_name:  schema.name
		index_name:  index.name
		column_name: index.column
		strategy:    'sqlite_fts5_match'
		backend:     'sqlite_fts5'
		term_count:  request.terms.len
		limit:       request.limit
	}
}

fn sidecar_hits_to_general_fts_hits(hits []storage.FtsSidecarHit, snippets []string) []GeneralFtsHit {
	mut out := []GeneralFtsHit{cap: hits.len}
	for idx, hit in hits {
		out << GeneralFtsHit{
			primary_key: decode_general_fts_row_pk_hex(hit.row_pk_hex) or { []u8{} }
			score:       hit.score
			snippet:     if idx < snippets.len { snippets[idx] } else { '' }
		}
	}
	return out
}

fn sidecar_hits_to_general_fts_hits_with_snippets(mut db storage.PersistentDatabase, table storage.TableDef, index IndexSchemaDef, request GeneralFtsRequest, rows []QueryRow, hits []storage.FtsSidecarHit) []GeneralFtsHit {
	snippets := general_fts_snippets_query(mut db, table, index, request, rows, hits)
	return sidecar_hits_to_general_fts_hits(hits, snippets)
}

fn general_fts_snippets_query(mut db storage.PersistentDatabase, table storage.TableDef, index IndexSchemaDef, request GeneralFtsRequest, rows []QueryRow, hits []storage.FtsSidecarHit) []string {
	mut snippets := []string{cap: hits.len}
	for idx, _ in hits {
		source_row := if idx < rows.len { rows[idx] } else { QueryRow{} }
		snippets << general_fts_build_snippet_query(mut db, table, source_row, index, request)
	}
	return snippets
}

fn general_fts_build_snippet_query(mut db storage.PersistentDatabase, table storage.TableDef, row QueryRow, index IndexSchemaDef, request GeneralFtsRequest) string {
	if row.primary_key.len == 0 {
		return ''
	}
	source := storage.fts_sidecar_document_text(db, table, storage_row_query(row),
		storage_index_schema_query(index)) or {
		return ''
	}
	return general_fts_snippet_from_text_query(source, request.terms)
}

fn general_fts_snippet_from_text_query(source string, terms []string) string {
	trimmed := source.trim_space()
	if trimmed.len == 0 {
		return ''
	}
	lower_source := trimmed.to_lower()
	mut best_idx := -1
	mut best_len := 0
	for term in terms {
		if term.len == 0 {
			continue
		}
		idx := lower_source.index(term) or { continue }
		if best_idx == -1 || idx < best_idx {
			best_idx = idx
			best_len = term.len
		}
	}
	if best_idx == -1 {
		return if trimmed.len > 120 { trimmed[..120] + ' ...' } else { trimmed }
	}
	start := if best_idx > 36 { best_idx - 36 } else { 0 }
	end_anchor := best_idx + if best_len > 0 { best_len } else { 1 }
	end := if end_anchor + 60 < trimmed.len { end_anchor + 60 } else { trimmed.len }
	mut snippet := trimmed[start..end]
	if start > 0 {
		snippet = '... ' + snippet
	}
	if end < trimmed.len {
		snippet += ' ...'
	}
	return snippet
}

fn fetch_general_fts_rows_query(session storage.DatabaseSession, mut db storage.PersistentDatabase, request GeneralFtsRequest) !([]QueryRow, []storage.FtsSidecarHit) {
	match_query := compile_general_fts_match_query_query(request)
	sidecar_hits := storage.fts_sidecar_query_hits(db.root_dir,
		fts_sidecar_table_name_query(request.table_name, request.index_name), session.branch_name,
		match_query, request.limit)!
	primary_keys := sidecar_hits.map(decode_general_fts_row_pk_hex(it.row_pk_hex) or { []u8{} }).filter(it.len > 0)
	if primary_keys.len == 0 {
		return []QueryRow{}, sidecar_hits
	}
	rows := session.get_rows_projected(mut db, request.table_name, primary_keys, []string{})!
	return query_rows_from_storage(rows), sidecar_hits
}

fn compile_general_fts_match_query_query(request GeneralFtsRequest) string {
	return match request.kind {
		.term { request.terms[0] }
		.prefix { '${request.terms[0]}*' }
		.all { request.terms.join(' ') }
		.any { request.terms.join(' OR ') }
	}
}

fn fts_sidecar_table_name_query(table_name string, index_name string) string {
	return 'fts_${sqlite_safe_identifier_query(table_name)}_${sqlite_safe_identifier_query(index_name)}'
}

fn sqlite_safe_identifier_query(raw string) string {
	if raw.len == 0 {
		return '_'
	}
	mut out := []u8{}
	for ch in raw.bytes() {
		if (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`) {
			out << ch
		} else {
			out << `_`
		}
	}
	return out.bytestr()
}

fn fetch_fts_rows_query(session storage.DatabaseSession, mut db storage.PersistentDatabase, spec QuerySpec, request FtsRequest, plan FtsPlan) ![]QueryRow {
	if plan.index_name.len > 0 {
		return match request.kind {
			.term { query_rows_from_storage(session.lookup_index(mut db, request.table_name, plan.index_name, request.terms[0], request.limit)!) }
			.prefix { query_rows_from_storage(session.lookup_index_prefix(mut db, request.table_name, plan.index_name, request.terms[0], request.limit)!) }
			.all { fts_intersect_database_index_rows_query(session, mut db, request.table_name, plan.index_name, request.terms, request.limit)! }
			.any { fts_union_database_index_rows_query(session, mut db, request.table_name, plan.index_name, request.terms, request.limit)! }
		}
	}
	rows := session.scan_table(mut db, request.table_name, 0)!
	return fts_filter_rows_by_scan_query(db.root_dir, spec.schema, request,
		query_rows_from_storage(rows))
}

fn fetch_fts_rows_in_transaction_query(session storage.TransactionSession, spec QuerySpec, request FtsRequest, plan FtsPlan) ![]QueryRow {
	if plan.index_name.len > 0 && request.kind != .prefix {
		return match request.kind {
			.term { query_rows_from_storage(session.lookup_index(request.table_name, plan.index_name, request.terms[0], request.limit)!) }
			.prefix { []QueryRow{} }
			.all { fts_intersect_transaction_index_rows_query(session, request.table_name, plan.index_name, request.terms, request.limit)! }
			.any { fts_union_transaction_index_rows_query(session, request.table_name, plan.index_name, request.terms, request.limit)! }
		}
	}
	rows := session.scan_table(request.table_name, 0)!
	return fts_filter_rows_by_scan_query(session.root_dir, spec.schema,
		request, query_rows_from_storage(rows))
}

fn fts_intersect_database_index_rows_query(session storage.DatabaseSession, mut db storage.PersistentDatabase, table_name string, index_name string, terms []string, limit int) ![]QueryRow {
	mut matched := map[string]QueryRow{}
	for idx, term in terms {
		rows := query_rows_from_storage(session.lookup_index(mut db, table_name, index_name, term, 0)!)
		if idx == 0 {
			for row in rows {
				matched[fts_primary_key_key_query(row.primary_key)] = row
			}
			continue
		}
		mut current := map[string]bool{}
		for row in rows {
			current[fts_primary_key_key_query(row.primary_key)] = true
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
	return fts_sorted_rows_from_map_query(matched, limit)
}

fn fts_union_database_index_rows_query(session storage.DatabaseSession, mut db storage.PersistentDatabase, table_name string, index_name string, terms []string, limit int) ![]QueryRow {
	mut matched := map[string]QueryRow{}
	for term in terms {
		rows := query_rows_from_storage(session.lookup_index(mut db, table_name, index_name, term, 0)!)
		for row in rows {
			matched[fts_primary_key_key_query(row.primary_key)] = row
		}
	}
	return fts_sorted_rows_from_map_query(matched, limit)
}

fn fts_intersect_transaction_index_rows_query(session storage.TransactionSession, table_name string, index_name string, terms []string, limit int) ![]QueryRow {
	mut matched := map[string]QueryRow{}
	for idx, term in terms {
		rows := query_rows_from_storage(session.lookup_index(table_name, index_name, term, 0)!)
		if idx == 0 {
			for row in rows {
				matched[fts_primary_key_key_query(row.primary_key)] = row
			}
			continue
		}
		mut current := map[string]bool{}
		for row in rows {
			current[fts_primary_key_key_query(row.primary_key)] = true
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
	return fts_sorted_rows_from_map_query(matched, limit)
}

fn fts_union_transaction_index_rows_query(session storage.TransactionSession, table_name string, index_name string, terms []string, limit int) ![]QueryRow {
	mut matched := map[string]QueryRow{}
	for term in terms {
		rows := query_rows_from_storage(session.lookup_index(table_name, index_name, term, 0)!)
		for row in rows {
			matched[fts_primary_key_key_query(row.primary_key)] = row
		}
	}
	return fts_sorted_rows_from_map_query(matched, limit)
}

fn fts_filter_rows_by_scan_query(root_dir string, schema TableSchemaDef, request FtsRequest, rows []QueryRow) ![]QueryRow {
	column := schema.column(request.column_name)!
	index := storage_field_selector_index_query('__fts_scan__', column.name, 'markdown',
		fts_selector_query(request.scope), .string_, false)!
	storage_column := storage_column_schema_query(column)
	mut matched := []QueryRow{}
	for row in rows {
		stored := if row.data.has(column.name) { storage_value_query(row.data.get(column.name)!) } else { storage.NullValue{} }
		values := storage.expand_field_selector_index_values(root_dir, storage_column, stored,
			index)!
		if fts_values_match_query(values.map(query_value_from_storage(it)), request) {
			matched << row
		}
	}
	fts_sort_rows_query(mut matched)
	if request.limit > 0 && matched.len > request.limit {
		return matched[..request.limit]
	}
	return matched
}

fn fts_values_match_query(values []QueryValue, request FtsRequest) bool {
	mut terms := map[string]bool{}
	for value in values {
		term := value.as_string() or { continue }
		terms[term] = true
	}
	match request.kind {
		.term { return request.terms[0] in terms }
		.prefix {
			for term, _ in terms {
				if term.starts_with(request.terms[0]) {
					return true
				}
			}
			return false
		}
		.all {
			for term in request.terms {
				if term !in terms {
					return false
				}
			}
			return true
		}
		.any {
			for term in request.terms {
				if term in terms {
					return true
				}
			}
			return false
		}
	}
}

fn fts_primary_key_key_query(primary_key []u8) string {
	return primary_key.hex()
}

fn fts_sort_rows_query(mut rows []QueryRow) {
	rows.sort_with_compare(fn (a &QueryRow, b &QueryRow) int {
		return compare_key_bytes_fts_query(a.primary_key, b.primary_key)
	})
}

fn fts_sorted_rows_from_map_query(rows_map map[string]QueryRow, limit int) []QueryRow {
	mut rows := []QueryRow{}
	for _, row in rows_map {
		rows << row
	}
	fts_sort_rows_query(mut rows)
	if limit > 0 && rows.len > limit {
		return rows[..limit]
	}
	return rows
}

struct QueryFtsRankedRow {
	row QueryRow
	hit FtsHit
}

fn rank_fts_rows_query(root_dir string, schema TableSchemaDef, request FtsRequest, rows []QueryRow) !([]QueryRow, []FtsHit) {
	mut ranked := []QueryFtsRankedRow{}
	column := schema.column(request.column_name)!
	for row in rows {
		hit := explain_fts_row_query(root_dir, column, request, row) or { continue }
		ranked << QueryFtsRankedRow{
			row: row
			hit: hit
		}
	}
	ranked.sort_with_compare(fn (a &QueryFtsRankedRow, b &QueryFtsRankedRow) int {
		if a.hit.score > b.hit.score {
			return -1
		}
		if a.hit.score < b.hit.score {
			return 1
		}
		return compare_key_bytes_fts_query(a.row.primary_key, b.row.primary_key)
	})
	mut out_rows := []QueryRow{cap: ranked.len}
	mut out_hits := []FtsHit{cap: ranked.len}
	for item in ranked {
		out_rows << item.row
		out_hits << item.hit
	}
	if request.limit > 0 && out_rows.len > request.limit {
		return out_rows[..request.limit].clone(), out_hits[..request.limit].clone()
	}
	return out_rows, out_hits
}

fn explain_fts_row_query(root_dir string, column ColumnSchemaDef, request FtsRequest, row QueryRow) !FtsHit {
	if !row.data.has(column.name) {
		return error('missing markdown payload')
	}
	stored := storage_value_query(row.data.get(column.name)!)
	raw := match stored {
		storage.MarkdownRef { storage.load_markdown_source(root_dir, stored.doc_root_id)! }
		string { stored }
		else { return error('fts explanation requires markdown payload') }
	}
	emissions := storage.emit_markdown_fts_tokens(raw)!
	mut matched_terms_seen := map[string]bool{}
	mut matched_scopes_seen := map[string]bool{}
	mut matched_terms := []string{}
	mut matched_scopes := []FtsScope{}
	mut score := 0
	for emission in emissions {
		if request.scope != .any && query_fts_scope_query(emission.scope) != request.scope {
			continue
		}
		if !fts_emission_matches_query_query(emission.term, request) {
			continue
		}
		scope := query_fts_scope_query(emission.scope)
		score += fts_scope_weight_query(scope)
		if !matched_terms_seen[emission.term] {
			matched_terms_seen[emission.term] = true
			matched_terms << emission.term
		}
		scope_name := fts_scope_name(scope)
		if !matched_scopes_seen[scope_name] {
			matched_scopes_seen[scope_name] = true
			matched_scopes << scope
		}
	}
	if score == 0 {
		return error('row does not match fts query')
	}
	matched_terms.sort()
	matched_scopes.sort_with_compare(fn (a &FtsScope, b &FtsScope) int {
		left := fts_scope_weight_query(*a)
		right := fts_scope_weight_query(*b)
		if left > right {
			return -1
		}
		if left < right {
			return 1
		}
		return 0
	})
	return FtsHit{
		primary_key:    row.primary_key.clone()
		score:          score
		matched_terms:  matched_terms
		matched_scopes: matched_scopes
		summary:        fts_hit_summary_query(matched_terms, matched_scopes)
	}
}

fn fts_emission_matches_query_query(term string, request FtsRequest) bool {
	match request.kind {
		.term, .all, .any { return term in request.terms }
		.prefix { return term.starts_with(request.terms[0]) }
	}
}

fn fts_scope_weight_query(scope FtsScope) int {
	return match scope {
		.heading { 8 }
		.paragraph { 4 }
		.list_item { 3 }
		.code_block { 2 }
		.any { 1 }
	}
}

fn fts_hit_summary_query(terms []string, scopes []FtsScope) string {
	mut scope_names := []string{cap: scopes.len}
	for scope in scopes {
		scope_names << fts_scope_name(scope)
	}
	return 'terms=[' + terms.join(', ') + '] scopes=[' + scope_names.join(', ') + ']'
}

fn compare_key_bytes_fts_query(a []u8, b []u8) int {
	limit := if a.len < b.len { a.len } else { b.len }
	for i in 0 .. limit {
		if a[i] < b[i] {
			return -1
		}
		if a[i] > b[i] {
			return 1
		}
	}
	if a.len < b.len {
		return -1
	}
	if a.len > b.len {
		return 1
	}
	return 0
}

fn decode_general_fts_row_pk_hex(raw string) ![]u8 {
	if raw.len == 0 {
		return []u8{}
	}
	if raw.len % 2 != 0 {
		return error('invalid row_pk hex length')
	}
	mut out := []u8{cap: raw.len / 2}
	for idx := 0; idx < raw.len; idx += 2 {
		hi := general_fts_hex_value_query(raw[idx])!
		lo := general_fts_hex_value_query(raw[idx + 1])!
		out << u8((u8(hi) << 4) | u8(lo))
	}
	return out
}

fn general_fts_hex_value_query(ch u8) !int {
	if ch >= `0` && ch <= `9` {
		return int(ch - `0`)
	}
	if ch >= `a` && ch <= `f` {
		return int(ch - `a`) + 10
	}
	if ch >= `A` && ch <= `F` {
		return int(ch - `A`) + 10
	}
	return error('invalid hex digit')
}
