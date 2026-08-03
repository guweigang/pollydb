module query

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
	if request.kind == .all {
		for term in request.terms {
			if term !in matched_terms_seen {
				return error('fts row does not satisfy all terms')
			}
		}
	}
	if matched_terms.len == 0 {
		return error('fts row did not match request')
	}
	matched_scopes.sort_with_compare(fn (a &FtsScope, b &FtsScope) int {
		return int(*a) - int(*b)
	})
	return FtsHit{
		primary_key:    row.primary_key.clone()
		score:          score
		matched_terms:  matched_terms
		matched_scopes: matched_scopes
		summary:        fts_hit_summary_query(matched_terms, matched_scopes)
	}
}
