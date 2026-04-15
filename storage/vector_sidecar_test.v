module storage

import os

struct TestEmbeddingEngine {
pub:
	dims    int
	vectors map[string][]f32
}

fn (engine TestEmbeddingEngine) model_name() string {
	return 'test'
}

fn (engine TestEmbeddingEngine) dimensions() int {
	return engine.dims
}

fn (mut engine TestEmbeddingEngine) embed(text string) ![]f32 {
	if text !in engine.vectors {
		return error('missing test vector for `${text}`')
	}
	return engine.vectors[text].clone()
}

fn (mut engine TestEmbeddingEngine) embed_batch(texts []string) ![][]f32 {
	mut out := [][]f32{cap: texts.len}
	for text in texts {
		out << engine.embed(text)!
	}
	return out
}

fn test_vector_sidecar_upsert_and_query() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-vector-sidecar-upsert')
	os.rmdir_all(dir) or {}
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	targets := [
		MarkdownEmbeddingTarget{
			id:            'note:block:1'
			scope:         .block
			kind:          'paragraph'
			content_id:    'c1'
			occurrence_id: 'o1'
			parent_id:     'p1'
			anchor:        '/h1:intro'
			order:         0
			path_hint:     'blocks[0]'
			text:          'query-like text'
		},
		MarkdownEmbeddingTarget{
			id:            'note:block:2'
			scope:         .block
			kind:          'paragraph'
			content_id:    'c2'
			occurrence_id: 'o2'
			parent_id:     'p1'
			anchor:        '/h1:other'
			order:         1
			path_hint:     'blocks[1]'
			text:          'far away text'
		},
	]
	db.upsert_markdown_embedding_targets('main', targets, [
		[f32(1.0), 0.0],
		[f32(0.0), 1.0],
	]) or { panic(err) }
	assert !os.exists(os.join_path(dir, '.pollydb', 'vectors', 'vectors.db'))
	session := db.open_session('main') or { panic(err) }
	vector_rows := session.scan_table(mut db, vector_records_table_name, 0) or { panic(err) }
	assert vector_rows.len == 2

	hits := db.query_markdown_embedding_vector([f32(0.9), 0.1], VectorSearchQuery{
		branch_name: 'main'
		limit:       2
	}) or { panic(err) }
	assert hits.len == 2
	assert hits[0].target_id == 'note:block:1'
	assert hits[0].score > hits[1].score
}

fn test_vector_sidecar_scope_filter() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-vector-sidecar-scope')
	os.rmdir_all(dir) or {}
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.upsert_markdown_embedding_targets('main', [
		MarkdownEmbeddingTarget{
			id:    'a'
			scope: .block
			kind:  'paragraph'
			text:  'a'
		},
		MarkdownEmbeddingTarget{
			id:    'b'
			scope: .path
			kind:  'heading_path'
			text:  'b'
		},
	], [
		[f32(1.0), 0.0],
		[f32(0.8), 0.2],
	]) or { panic(err) }

	hits := db.query_markdown_embedding_vector([f32(1.0), 0.0], VectorSearchQuery{
		branch_name: 'main'
		limit:       10
		scope:       .path
		scope_set:   true
	}) or { panic(err) }
	assert hits.len == 1
	assert hits[0].target_id == 'b'
	assert hits[0].scope == .path
}

fn test_index_and_query_markdown_ref_embeddings() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-vector-sidecar-markdown-ref')
	os.rmdir_all(dir) or {}
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	ref := db.ingest_markdown('# Intro\n\n数据库索引优化和查询规划\n\n## Next\n\n今天的天气和晚饭吃什么\n') or {
		panic(err)
	}
	mut engine := TestEmbeddingEngine{
		dims:    2
		vectors: {
			'数据库索引优化和查询规划':                                            [
				f32(1.0),
				0.0,
			]
			'今天的天气和晚饭吃什么':                                              [
				f32(0.0),
				1.0,
			]
			'Intro\n\n数据库索引优化和查询规划\n\nNext\n\n今天的天气和晚饭吃什么': [
				f32(0.6),
				0.4,
			]
			'Next\n\n今天的天气和晚饭吃什么':                                      [
				f32(0.1),
				0.9,
			]
			'数据库优化':                                                          [
				f32(0.95),
				0.05,
			]
		}
	}

	targets := db.index_markdown_ref_embeddings('main', ref, mut engine) or { panic(err) }
	assert targets.len == 4
	hits := db.query_markdown_text_embeddings(mut engine, '数据库优化', VectorSearchQuery{
		branch_name: 'main'
		limit:       2
		scope:       .block
		scope_set:   true
	}) or { panic(err) }
	assert hits.len == 2
	assert hits[0].text == '数据库索引优化和查询规划'
	assert hits[0].score > hits[1].score
}

fn test_vector_cosine_similarity_handles_zero_vectors() {
	assert vector_cosine_similarity([f32(0.0), 0.0], [f32(1.0), 0.0]) == 0.0
}

fn test_vector_backend_usearch_placeholder_returns_clear_error() {
	$if !usearch ? {
		dir := os.join_path(os.vtmp_dir(), 'pollydb-vector-sidecar-usearch-placeholder')
		os.rmdir_all(dir) or {}
		old_backend := os.getenv_opt('POLLYDB_VECTOR_BACKEND') or { '' }
		os.setenv('POLLYDB_VECTOR_BACKEND', 'usearch', true)
		defer {
			if old_backend.len == 0 {
				os.unsetenv('POLLYDB_VECTOR_BACKEND')
			} else {
				os.setenv('POLLYDB_VECTOR_BACKEND', old_backend, true)
			}
		}
		mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
		defer {
			db.close() or {}
		}
		db.upsert_markdown_embedding_targets('main', [
			MarkdownEmbeddingTarget{
				id:    'x'
				scope: .block
				kind:  'paragraph'
				text:  'x'
			},
		], [
			[f32(1.0), 0.0],
		]) or {
			assert err.msg().contains('USearch vector backend requires compiling with -d usearch')
			return
		}
		assert false
	}
}

fn test_vector_target_bindings_are_branch_consistent() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-vector-sidecar-bindings')
	os.rmdir_all(dir) or {}
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.ensure_vector_target_bindings('main', [
		MarkdownEmbeddingTarget{
			id:            'doc:path:a'
			scope:         .path
			kind:          'heading_path'
			content_id:    'ca'
			occurrence_id: 'oa'
			anchor:        '/intro'
			text:          'A'
		},
	]) or { panic(err) }
	assert db.vector_int_id_for_target('main', 'doc:path:a') or { panic(err) } == 1
	assert db.vector_target_id_for_int('main', 1) or { panic(err) } == 'doc:path:a'

	db.ensure_vector_target_bindings('main', [
		MarkdownEmbeddingTarget{
			id:            'doc:path:a'
			scope:         .path
			kind:          'heading_path'
			content_id:    'ca'
			occurrence_id: 'oa'
			anchor:        '/intro'
			text:          'A again'
		},
	]) or { panic(err) }
	assert db.vector_int_id_for_target('main', 'doc:path:a') or { panic(err) } == 1

	db.ensure_vector_target_bindings('main', [
		MarkdownEmbeddingTarget{
			id:            'doc:path:b'
			scope:         .path
			kind:          'heading_path'
			content_id:    'cb'
			occurrence_id: 'ob'
			anchor:        '/next'
			text:          'B'
		},
	]) or { panic(err) }
	assert db.vector_int_id_for_target('main', 'doc:path:b') or { panic(err) } == 2
	assert db.vector_target_id_for_int('main', 2) or { panic(err) } == 'doc:path:b'
}

$if usearch ? {
	fn test_vector_backend_usearch_queries_through_memory_backend() {
		dir := os.join_path(os.vtmp_dir(), 'pollydb-vector-sidecar-usearch-backend')
		os.rmdir_all(dir) or {}
		old_backend := os.getenv_opt('POLLYDB_VECTOR_BACKEND') or { '' }
		os.setenv('POLLYDB_VECTOR_BACKEND', 'usearch', true)
		defer {
			if old_backend.len == 0 {
				os.unsetenv('POLLYDB_VECTOR_BACKEND')
			} else {
				os.setenv('POLLYDB_VECTOR_BACKEND', old_backend, true)
			}
		}
		mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
		defer {
			db.close() or {}
		}
		db.upsert_markdown_embedding_targets('main', [
			MarkdownEmbeddingTarget{
				id:    'a'
				scope: .block
				kind:  'paragraph'
				text:  'near'
			},
			MarkdownEmbeddingTarget{
				id:    'b'
				scope: .block
				kind:  'paragraph'
				text:  'far'
			},
		], [
			[f32(1.0), 0.0],
			[f32(0.0), 1.0],
		]) or { panic(err) }

		hits := db.query_markdown_embedding_vector([f32(0.95), 0.05], VectorSearchQuery{
			branch_name: 'main'
			limit:       2
		}) or { panic(err) }
		assert hits.len == 2
		assert hits[0].target_id == 'a'
		assert hits[0].int_id == 1
		assert hits[0].score > hits[1].score
		index_path := usearch_sidecar_index_path(dir, VectorSearchQuery{
			branch_name: 'main'
			limit:       2
		}, 2)
		assert os.exists(index_path)
		assert os.exists(usearch_sidecar_meta_path(index_path))

		db.upsert_markdown_embedding_targets('main', [
			MarkdownEmbeddingTarget{
				id:    'a'
				scope: .block
				kind:  'paragraph'
				text:  'near'
			},
			MarkdownEmbeddingTarget{
				id:    'b'
				scope: .block
				kind:  'paragraph'
				text:  'far'
			},
		], [
			[f32(0.0), 1.0],
			[f32(1.0), 0.0],
		]) or { panic(err) }

		refreshed := db.query_markdown_embedding_vector([f32(0.95), 0.05], VectorSearchQuery{
			branch_name: 'main'
			limit:       2
		}) or { panic(err) }
		assert refreshed.len == 2
		assert refreshed[0].target_id == 'b'
		assert refreshed[0].score > refreshed[1].score
	}
}
