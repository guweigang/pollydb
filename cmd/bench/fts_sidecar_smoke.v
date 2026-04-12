module main

import os
import storage

fn main() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-fts-sidecar-smoke')
	os.rmdir_all(dir) or {}
	mut db := storage.PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
		os.rmdir_all(dir) or {}
	}
	spec := storage.TypedTableSpec.new(storage.TableDef.new('docs', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('content_text', .string_, false)!,
		storage.ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!, [
		storage.SchemaIndexDef.fts_with_options('content_text_fts_idx', 'content_text',
			storage.FtsIndexOptions{
			tokenizer:      'unicode61 remove_diacritics 2'
			prefix_lengths: [2, 3, 4]
		})!,
		storage.SchemaIndexDef.fts_markdown_with_options('body_fts_idx', 'body', .visible_text_with_code,
			storage.FtsIndexOptions{
			prefix_lengths: [2, 4]
		})!,
	]) or { panic(err) }
	println('register table')
	db.register_table(spec) or { panic(err) }
	body := db.ingest_markdown('# Search Title\n\nVisible paragraph.\n\n```v\nfts code token\n```\n') or {
		panic(err)
	}
	mut row := storage.TypedRowData.new()
	row.set('id', 'doc-1')
	row.set('content_text', 'alpha searchable body')
	row.set('body', body)
	println('build seed tree')
	seed_tree := storage.build_single_row_seed_tree(spec, 'doc-1'.bytes(), row, storage.ChunkConfig.default()) or {
		panic(err)
	}
	println('commit branch')
	_ = db.commit_to_branch('main', seed_tree, storage.CommitMeta{
		author:    'smoke'
		message:   'seed'
		timestamp: 0
	}) or { panic(err) }
	println('rebuild indexes at branch')
	_ = db.rebuild_indexes_at_branch('main', ['docs'], storage.ChunkConfig.default()) or {
		panic(err)
	}
	println(storage.fts_sidecar_branch_row_count(dir, 'fts_docs_content_text_fts_idx',
		'main') or { panic(err) })
	println(storage.fts_sidecar_match_count(dir, 'fts_docs_content_text_fts_idx', 'main',
		'searchable') or { panic(err) })
	println(storage.fts_sidecar_match_count(dir, 'fts_docs_body_fts_idx', 'main', 'token') or {
		panic(err)
	})
	println(storage.fts_sidecar_query_hits(dir, 'fts_docs_content_text_fts_idx', 'main',
		'searchable', 10) or { panic(err) })
}
