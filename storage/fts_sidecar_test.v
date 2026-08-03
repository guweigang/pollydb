module storage

import os

fn fts_sidecar_docs_spec() !TypedTableSpec {
	table := TableDef.new('docs', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('content_text', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.fts_with_options('content_text_fts_idx', 'content_text', FtsIndexOptions{
			tokenizer:      'unicode61 remove_diacritics 2'
			prefix_lengths: [2, 3, 4]
		})!,
		SchemaIndexDef.fts_markdown_with_options('body_fts_idx', 'body', .visible_text_with_code, FtsIndexOptions{
			prefix_lengths: [2, 4]
		})!,
	])
}

fn test_persistent_database_rebuild_indexes_populates_general_fts_sidecar() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-general-fts-sidecar')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := fts_sidecar_docs_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	println('register')
	db.register_table(spec) or { panic(err) }
	println('ingest markdown')
	body := db.ingest_markdown('# Search Title\n\nVisible paragraph.\n\n```v\nfts code token\n```\n') or {
		panic(err)
	}
	mut row := TypedRowData.new()
	row.set('id', 'doc-1')
	row.set('content_text', 'alpha searchable body')
	row.set('body', body)
	seed_tree := build_single_row_seed_tree(spec, 'doc-1'.bytes(), row, ChunkConfig.default()) or {
		panic(err)
	}
	println('commit')
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'test'
		message:   'seed docs'
		timestamp: 0
	}) or { panic(err) }
	println('rebuild branch indexes')
	_ = db.rebuild_indexes_at_branch('main', ['docs'], ChunkConfig.default()) or { panic(err) }
	db.optimize_fts_indexes(['docs']) or { panic(err) }

	content_table := fts_sidecar_table_name('docs', 'content_text_fts_idx')
	body_table := fts_sidecar_table_name('docs', 'body_fts_idx')
	content_count := fts_sidecar_branch_row_count(dir, content_table, 'main') or { panic(err) }
	body_count := fts_sidecar_branch_row_count(dir, body_table, 'main') or { panic(err) }
	content_match_count := fts_sidecar_match_count(dir, fts_sidecar_table_name('docs',
		'content_text_fts_idx'), 'main', 'searchable') or { panic(err) }
	body_match_count := fts_sidecar_match_count(dir,
		fts_sidecar_table_name('docs', 'body_fts_idx'), 'main', 'token') or { panic(err) }

	assert content_count == 1
	assert body_count == 1
	assert content_match_count == 1
	assert body_match_count == 1
}

fn test_persistent_database_row_writes_update_general_fts_sidecar_incrementally() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-general-fts-sidecar-incremental')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := fts_sidecar_docs_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	initial_body := db.ingest_markdown('# Search Title\n\nVisible paragraph.\n') or { panic(err) }
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'doc-1')
	seed_row.set('content_text', 'alpha searchable body')
	seed_row.set('body', initial_body)
	seed_tree := build_single_row_seed_tree(spec, 'doc-1'.bytes(), seed_row, ChunkConfig.default()) or {
		panic(err)
	}
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'test'
		message:   'seed docs'
		timestamp: 0
	}) or { panic(err) }
	_ = db.rebuild_indexes_at_branch('main', ['docs'], ChunkConfig.default()) or { panic(err) }

	session := db.begin_session(SessionOptions.for_branch('main')) or { panic(err) }
	updated_body := db.ingest_markdown('# Search Title\n\nUpdated beta token.\n\n```v\ncode-gamma\n```\n') or {
		panic(err)
	}
	mut updated_row := TypedRowData.new()
	updated_row.set('id', 'doc-1')
	updated_row.set('content_text', 'beta updated body')
	updated_row.set('body', updated_body)
	_ = session.put_row(mut db, 'docs', 'doc-1'.bytes(), updated_row, ChunkConfig.default(), CommitMeta{
		author:    'test'
		message:   'update doc'
		timestamp: 0
	}) or { panic(err) }

	content_table := fts_sidecar_table_name('docs', 'content_text_fts_idx')
	body_table := fts_sidecar_table_name('docs', 'body_fts_idx')
	assert fts_sidecar_match_count(dir, content_table, 'main', 'searchable') or { panic(err) } == 0
	assert fts_sidecar_match_count(dir, content_table, 'main', 'beta') or { panic(err) } == 1
	assert fts_sidecar_match_count(dir, body_table, 'main', 'paragraph') or { panic(err) } == 0
	assert fts_sidecar_match_count(dir, body_table, 'main', 'gamma') or { panic(err) } == 1

	mut metadata_row := updated_row.clone()
	metadata_row.set('id', 'doc-1')
	metadata_row.set('content_text', 'beta updated body')
	metadata_row.set('body', updated_body)
	mut metadata_write := TypedWriteSet.new()
	metadata_write.put('docs', 'doc-1'.bytes(), metadata_row)
	metadata_result := db.apply_typed_write_set_with_specs('main', [spec], metadata_write,
		ChunkConfig.default(), CommitMeta{
		author:    'test'
		message:   'metadata-only update doc'
		timestamp: 0
	}) or { panic(err) }
	assert metadata_result.timings.fts_begin_us == 0
	assert metadata_result.timings.fts_ensure_us == 0
	assert metadata_result.timings.fts_docid_select_us == 0
	assert metadata_result.timings.fts_delete_us == 0
	assert metadata_result.timings.fts_insert_us == 0
	assert metadata_result.timings.fts_commit_us == 0

	second_body := db.ingest_markdown('# Keep\n\nSurviving row.\n') or { panic(err) }
	mut second_row := TypedRowData.new()
	second_row.set('id', 'doc-2')
	second_row.set('content_text', 'keep row')
	second_row.set('body', second_body)
	_ = session.put_row(mut db, 'docs', 'doc-2'.bytes(), second_row, ChunkConfig.default(), CommitMeta{
		author:    'test'
		message:   'insert second doc'
		timestamp: 0
	}) or { panic(err) }

	_ = session.delete_row(mut db, 'docs', 'doc-1'.bytes(), ChunkConfig.default(), CommitMeta{
		author:    'test'
		message:   'delete doc'
		timestamp: 0
	}) or { panic(err) }

	assert fts_sidecar_branch_row_count(dir, content_table, 'main') or { panic(err) } == 1
	assert fts_sidecar_branch_row_count(dir, body_table, 'main') or { panic(err) } == 1
	assert fts_sidecar_match_count(dir, content_table, 'main', 'beta') or { panic(err) } == 0
	assert fts_sidecar_match_count(dir, content_table, 'main', 'keep') or { panic(err) } == 1
}

fn test_persistent_database_new_fts_rows_skip_docid_lookup() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-general-fts-sidecar-new-skip-docid')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := fts_sidecar_docs_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut write := TypedWriteSet.new()
	for idx in 0 .. 3 {
		body := db.ingest_markdown('# New ${idx}\n\nFresh visible token ${idx}.\n') or {
			panic(err)
		}
		mut row := TypedRowData.new()
		row.set('id', 'doc-${idx}')
		row.set('content_text', 'fresh searchable ${idx}')
		row.set('body', body)
		write.put('docs', 'doc-${idx}'.bytes(), row)
	}
	result := db.apply_typed_write_set_with_specs('main', [spec], write, ChunkConfig.default(), CommitMeta{
		author:    'test'
		message:   'insert new docs'
		timestamp: 0
	}) or { panic(err) }
	assert result.timings.fts_docid_select_us == 0

	content_table := fts_sidecar_table_name('docs', 'content_text_fts_idx')
	body_table := fts_sidecar_table_name('docs', 'body_fts_idx')
	assert fts_sidecar_match_count(dir, content_table, 'main', 'fresh') or { panic(err) } == 3
	assert fts_sidecar_match_count(dir, body_table, 'main', 'visible') or { panic(err) } == 3
}

fn test_fts_sidecar_docid_allocator_owns_fts_rowid() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-general-fts-sidecar-docid-allocator')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := fts_sidecar_docs_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut write := TypedWriteSet.new()
	body := db.ingest_markdown('# Allocator\n\nStable visible token.\n') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', 'doc-allocator')
	row.set('content_text', 'allocator searchable text')
	row.set('body', body)
	write.put('docs', 'doc-allocator'.bytes(), row)
	_ = db.apply_typed_write_set_with_specs('main', [spec], write, ChunkConfig.default(), CommitMeta{
		author:    'test'
		message:   'insert allocator doc'
		timestamp: 0
	}) or { panic(err) }
	db.close() or { panic(err) }

	content_table := fts_sidecar_table_name('docs', 'content_text_fts_idx')
	docid_table := fts_sidecar_docid_table_name('docs', 'content_text_fts_idx')
	mut sidecar := open_fts_sidecar(dir) or { panic(err) }
	defer {
		sidecar.close() or {}
	}
	docid_pk := sidecar.q_int('select pk from pragma_table_info(${sqlite_text(docid_table)}) where name = \'docid\'') or {
		panic(err)
	}
	assert docid_pk == 1
	row_pk_hex := 'doc-allocator'.bytes().hex()
	docid := sidecar.q_int('select docid from ${sqlite_ident(docid_table)} where branch_name = \'main\' and row_pk = ${sqlite_text(row_pk_hex)}') or {
		panic(err)
	}
	fts_rowid := sidecar.q_int('select rowid from ${sqlite_ident(content_table)} where branch_name = \'main\' and row_pk = ${sqlite_text(row_pk_hex)}') or {
		panic(err)
	}
	assert docid > 0
	assert fts_rowid == docid
}

fn test_persistent_database_group_commit_updates_general_fts_sidecar() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-general-fts-sidecar-group-commit')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := fts_sidecar_docs_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_body := db.ingest_markdown('# Seed\n\nInitial seed text.\n') or { panic(err) }
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'doc-0')
	seed_row.set('content_text', 'seed body')
	seed_row.set('body', seed_body)
	seed_tree := build_single_row_seed_tree(spec, 'doc-0'.bytes(), seed_row, ChunkConfig.default()) or {
		panic(err)
	}
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'test'
		message:   'seed docs'
		timestamp: 0
	}) or { panic(err) }
	_ = db.rebuild_indexes_at_branch('main', ['docs'], ChunkConfig.default()) or { panic(err) }
	mut session := db.begin_default_group_commit_session(GroupCommitOptions{
		checkpoint_every: 2
		checkpoint_mode:  .full
	}) or { panic(err) }
	first_body := db.ingest_markdown('# Alpha\n\nVisible alpha text.\n') or { panic(err) }
	mut first_row := TypedRowData.new()
	first_row.set('id', 'doc-1')
	first_row.set('content_text', 'alpha searchable body')
	first_row.set('body', first_body)
	_ = session.put_row(mut db, 'docs', 'doc-1'.bytes(), first_row, ChunkConfig.default(), CommitMeta{
		author:    'test'
		message:   'group insert doc'
		timestamp: 0
	}) or { panic(err) }
	second_body := db.ingest_markdown('# Beta\n\nVisible beta text.\n') or { panic(err) }
	mut second_row := TypedRowData.new()
	second_row.set('id', 'doc-2')
	second_row.set('content_text', 'beta searchable body')
	second_row.set('body', second_body)
	flush_result := session.put_row(mut db, 'docs', 'doc-2'.bytes(), second_row,
		ChunkConfig.default(), CommitMeta{
		author:    'test'
		message:   'group insert doc 2'
		timestamp: 0
	}) or { panic(err) }

	content_table := fts_sidecar_table_name('docs', 'content_text_fts_idx')
	body_table := fts_sidecar_table_name('docs', 'body_fts_idx')
	assert flush_result.group_commit.flushed
	assert fts_sidecar_match_count(dir, content_table, 'main', 'alpha') or { panic(err) } == 1
	assert fts_sidecar_match_count(dir, content_table, 'main', 'beta') or { panic(err) } == 1
	assert fts_sidecar_match_count(dir, body_table, 'main', 'visible') or { panic(err) } == 2

	updated_body := db.ingest_markdown('# Gamma\n\nUpdated gamma text.\n') or { panic(err) }
	mut updated_row := TypedRowData.new()
	updated_row.set('id', 'doc-1')
	updated_row.set('content_text', 'gamma updated body')
	updated_row.set('body', updated_body)
	_ = session.put_row(mut db, 'docs', 'doc-1'.bytes(), updated_row, ChunkConfig.default(), CommitMeta{
		author:    'test'
		message:   'group update doc'
		timestamp: 0
	}) or { panic(err) }
	_ = session.delete_row(mut db, 'docs', 'doc-2'.bytes(), ChunkConfig.default(), CommitMeta{
		author:    'test'
		message:   'group delete doc'
		timestamp: 0
	}) or { panic(err) }

	assert fts_sidecar_match_count(dir, content_table, 'main', 'alpha') or { panic(err) } == 0
	assert fts_sidecar_match_count(dir, content_table, 'main', 'beta') or { panic(err) } == 0
	assert fts_sidecar_match_count(dir, content_table, 'main', 'gamma') or { panic(err) } == 1
	assert fts_sidecar_branch_row_count(dir, content_table, 'main') or { panic(err) } == 2
}
