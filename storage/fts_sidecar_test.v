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
		SchemaIndexDef.fts_markdown_with_options('body_fts_idx', 'body', .visible_text_with_code,
			FtsIndexOptions{
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

	content_table := fts_sidecar_table_name('docs', 'content_text_fts_idx')
	body_table := fts_sidecar_table_name('docs', 'body_fts_idx')
	content_count := fts_sidecar_branch_row_count(dir, content_table, 'main') or { panic(err) }
	body_count := fts_sidecar_branch_row_count(dir, body_table, 'main') or { panic(err) }
	content_match_count := fts_sidecar_match_count(dir, fts_sidecar_table_name('docs',
		'content_text_fts_idx'), 'main', 'searchable') or { panic(err) }
	body_match_count := fts_sidecar_match_count(dir, fts_sidecar_table_name('docs', 'body_fts_idx'),
		'main', 'token') or { panic(err) }

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
	_ = session.put_row(mut db, 'docs', 'doc-1'.bytes(), updated_row, ChunkConfig.default(),
		CommitMeta{
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

	second_body := db.ingest_markdown('# Keep\n\nSurviving row.\n') or { panic(err) }
	mut second_row := TypedRowData.new()
	second_row.set('id', 'doc-2')
	second_row.set('content_text', 'keep row')
	second_row.set('body', second_body)
	_ = session.put_row(mut db, 'docs', 'doc-2'.bytes(), second_row, ChunkConfig.default(),
		CommitMeta{
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
