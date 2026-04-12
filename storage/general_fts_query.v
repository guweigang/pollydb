module storage

pub struct GeneralFtsQuery {
pub:
	table_name     string
	index_name     string
	kind           FtsQueryKind
	terms          []string
	select_columns []string
	limit          int
}

pub struct GeneralFtsQueryPlan {
pub:
	table_name  string
	index_name  string
	column_name string
	strategy    string
	backend     string
	term_count  int
	limit       int
}

pub struct GeneralFtsHit {
pub:
	primary_key []u8
	score       f64
	snippet     string
}

pub struct GeneralFtsQueryResult {
pub:
	rows []TypedSchemaRow
	hits []GeneralFtsHit
	plan GeneralFtsQueryPlan
}

pub fn validate_general_fts_query(query GeneralFtsQuery) ! {
	if query.table_name.len == 0 {
		return error('general fts query requires table_name')
	}
	if query.index_name.len == 0 {
		return error('general fts query requires index_name')
	}
	if query.terms.len == 0 {
		return error('general fts query requires at least one term')
	}
	normalized := fts_normalize_terms(query.terms)
	if normalized.len == 0 {
		return error('general fts query terms cannot all be empty')
	}
	match query.kind {
		.term, .prefix {
			if normalized.len != 1 {
				return error('general fts ${fts_query_kind_name(query.kind)} query requires exactly one term')
			}
		}
		.all, .any {}
	}
}

pub fn (database PersistentDatabase) preview_general_fts_query(query GeneralFtsQuery) !GeneralFtsQueryPlan {
	spec := database.table_spec(query.table_name)!
	normalized := normalize_general_fts_query(query)
	index := validate_general_fts_query_request(spec, normalized)!
	return plan_general_fts_query(spec, index, normalized)
}

pub fn (session DatabaseSession) preview_general_fts_query(query GeneralFtsQuery) !GeneralFtsQueryPlan {
	spec := session.table_spec(query.table_name)!
	normalized := normalize_general_fts_query(query)
	index := validate_general_fts_query_request(spec, normalized)!
	return plan_general_fts_query(spec, index, normalized)
}

pub fn (mut database PersistentDatabase) query_general_fts(branch_name string, query GeneralFtsQuery) !GeneralFtsQueryResult {
	mut session := database.open_session(branch_name)!
	return session.query_general_fts(mut database, query)
}

pub fn (session DatabaseSession) query_general_fts(mut db PersistentDatabase, query GeneralFtsQuery) !GeneralFtsQueryResult {
	spec := session.table_spec(query.table_name)!
	normalized := normalize_general_fts_query(query)
	index := validate_general_fts_query_request(spec, normalized)!
	plan := plan_general_fts_query(spec, index, normalized)
	match_query := compile_general_fts_match_query(normalized)
	sidecar_hits := fts_sidecar_query_hits(db.root_dir, fts_sidecar_table_name(query.table_name,
		query.index_name), session.branch_name, match_query, normalized.limit)!
	primary_keys := sidecar_hits.map(general_fts_decode_row_pk_hex(it.row_pk_hex) or { []u8{} }).filter(it.len > 0)
	full_rows := fetch_general_fts_rows(session, mut db, normalized.table_name, primary_keys,
		[]string{})!
	rows := project_query_rows(full_rows, normalized.select_columns)!
	mut hits := []GeneralFtsHit{}
	for idx, sidecar_hit in sidecar_hits {
		primary_key := general_fts_decode_row_pk_hex(sidecar_hit.row_pk_hex) or { continue }
		source_row := if idx < full_rows.len { full_rows[idx] } else { TypedSchemaRow{} }
		hits << GeneralFtsHit{
			primary_key: primary_key
			score:       sidecar_hit.score
			snippet:     general_fts_build_snippet(db, spec.table, source_row, index,
				normalized)
		}
	}
	return GeneralFtsQueryResult{
		rows: rows
		hits: hits
		plan: plan
	}
}

fn general_fts_build_snippet(database &PersistentDatabase, table TableDef, row TypedSchemaRow, index SchemaIndexDef, query GeneralFtsQuery) string {
	if row.primary_key.len == 0 {
		return ''
	}
	source := fts_sidecar_document_text(database, table, row, index) or { return '' }
	return general_fts_snippet_from_text(source, query)
}

fn general_fts_snippet_from_text(source string, query GeneralFtsQuery) string {
	trimmed := source.trim_space()
	if trimmed.len == 0 {
		return ''
	}
	lower_source := trimmed.to_lower()
	mut best_idx := -1
	mut best_len := 0
	for term in query.terms {
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

fn normalize_general_fts_query(query GeneralFtsQuery) GeneralFtsQuery {
	mut seen := map[string]bool{}
	mut terms := []string{}
	for term in fts_normalize_terms(query.terms) {
		if seen[term] {
			continue
		}
		seen[term] = true
		terms << term
	}
	return GeneralFtsQuery{
		...query
		terms: terms
	}
}

fn validate_general_fts_query_request(spec TypedTableSpec, query GeneralFtsQuery) !SchemaIndexDef {
	validate_general_fts_query(query)!
	index := general_fts_index_by_name(spec, query.index_name)!
	if !index.is_fts() {
		return error('index is not an fts index: ${query.index_name}')
	}
	for column_name in query.select_columns {
		if !spec.table.has_column(column_name) {
			return error('general fts query select column not found: ${column_name}')
		}
	}
	return index
}

fn general_fts_index_by_name(spec TypedTableSpec, index_name string) !SchemaIndexDef {
	for index in spec.indexes {
		if index.name == index_name {
			return index
		}
	}
	return error('typed table index not found: ${index_name}')
}

fn plan_general_fts_query(spec TypedTableSpec, index SchemaIndexDef, query GeneralFtsQuery) GeneralFtsQueryPlan {
	return GeneralFtsQueryPlan{
		table_name:  spec.table.name
		index_name:  index.name
		column_name: index.column
		strategy:    'sqlite_fts5_match'
		backend:     'sqlite_fts5'
		term_count:  query.terms.len
		limit:       query.limit
	}
}

fn compile_general_fts_match_query(query GeneralFtsQuery) string {
	return match query.kind {
		.term {
			query.terms[0]
		}
		.prefix {
			'${query.terms[0]}*'
		}
		.all {
			query.terms.join(' ')
		}
		.any {
			query.terms.join(' OR ')
		}
	}
}

fn fetch_general_fts_rows(session DatabaseSession, mut db PersistentDatabase, table_name string, primary_keys [][]u8, columns []string) ![]TypedSchemaRow {
	if primary_keys.len == 0 {
		return []TypedSchemaRow{}
	}
	if columns.len > 0 {
		return session.get_rows_projected(mut db, table_name, primary_keys, columns)
	}
	mut rows := []TypedSchemaRow{cap: primary_keys.len}
	for primary_key in primary_keys {
		rows << session.get_row(mut db, table_name, primary_key)!
	}
	return rows
}

fn general_fts_decode_row_pk_hex(raw string) ![]u8 {
	if raw.len == 0 {
		return []u8{}
	}
	if raw.len % 2 != 0 {
		return error('invalid row_pk hex length')
	}
	mut out := []u8{cap: raw.len / 2}
	for idx := 0; idx < raw.len; idx += 2 {
		hi := general_fts_hex_value(raw[idx])!
		lo := general_fts_hex_value(raw[idx + 1])!
		out << u8((u8(hi) << 4) | u8(lo))
	}
	return out
}

fn general_fts_hex_value(ch u8) !int {
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
