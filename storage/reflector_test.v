module storage

import os

struct ReflectorTestEmbeddingEngine {
pub:
	dims    int
	vectors map[string][]f32
}

struct ReflectorTestGenerator {
	output string
mut:
	prompts []string
}

fn (mut generator ReflectorTestGenerator) generate(prompt string) !string {
	generator.prompts << prompt
	return generator.output
}

fn (engine ReflectorTestEmbeddingEngine) model_name() string {
	return 'test'
}

fn (engine ReflectorTestEmbeddingEngine) dimensions() int {
	return engine.dims
}

fn (mut engine ReflectorTestEmbeddingEngine) embed(text string) ![]f32 {
	if text !in engine.vectors {
		return error('missing test vector for `${text}`')
	}
	return engine.vectors[text].clone()
}

fn (mut engine ReflectorTestEmbeddingEngine) embed_batch(texts []string) ![][]f32 {
	mut out := [][]f32{cap: texts.len}
	for text in texts {
		out << engine.embed(text)!
	}
	return out
}

fn reflector_docs_spec() !TypedTableSpec {
	return TypedTableSpec.new(TableDef.new('docs', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!, [
		SchemaIndexDef.embedding_markdown('body_path_vec_idx', 'body', .path, 'bge-small')!,
	])!
}

fn test_index_reflective_markdown_fields_and_build_reflection_job() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-reflector-job')
	os.rmdir_all(dir) or {}
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	spec := reflector_docs_spec() or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.register_memory_capability(MemoryCapabilityDef.reflective_field('docs', 'body',
		ReflectionOptions{
		embedding_index: 'body_path_vec_idx'
		reflection_kind: 'summary'
	}) or { panic(err) }) or { panic(err) }
	ref_a := db.ingest_markdown('# Query\n\n数据库优化和查询规划\n') or { panic(err) }
	ref_b := db.ingest_markdown('# Indexes\n\n数据库索引设计与查询优化\n') or {
		panic(err)
	}
	ref_c := db.ingest_markdown('# Weather\n\n今天天气不错，晚上吃面。\n') or {
		panic(err)
	}
	codec := TypedRowCodec.new(spec.table)
	mut row_a := TypedRowData.new()
	row_a.set('id', 'doc-1')
	row_a.set('body', ref_a)
	mut row_b := TypedRowData.new()
	row_b.set('id', 'doc-2')
	row_b.set('body', ref_b)
	mut row_c := TypedRowData.new()
	row_c.set('id', 'doc-3')
	row_c.set('body', ref_c)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('doc-1'.bytes())
			value: codec.encode(row_a)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('doc-2'.bytes())
			value: codec.encode(row_b)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('doc-3'.bytes())
			value: codec.encode(row_c)!
		},
	], ChunkConfig.default()) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed docs'
		timestamp: 1
	}) or { panic(err) }

	mut engine := ReflectorTestEmbeddingEngine{
		dims:    2
		vectors: {
			'数据库优化和查询规划':                [f32(1.0), 0.0]
			'数据库优化':                          [f32(0.99), 0.01]
			'数据库索引设计与查询优化':            [f32(0.97), 0.03]
			'今天天气不错，晚上吃面。':             [f32(0.0), 1.0]
			'Query\n\n数据库优化和查询规划':       [f32(0.98), 0.02]
			'Indexes\n\n数据库索引设计与查询优化': [f32(0.96), 0.04]
			'Weather\n\n今天天气不错，晚上吃面。':  [f32(0.0), 1.0]
		}
	}

	indexed_a := db.index_reflective_markdown_fields('main', 'docs', 'doc-1'.bytes(), mut
		engine) or { panic(err) }
	indexed_b := db.index_reflective_markdown_fields('main', 'docs', 'doc-2'.bytes(), mut
		engine) or { panic(err) }
	indexed_c := db.index_reflective_markdown_fields('main', 'docs', 'doc-3'.bytes(), mut
		engine) or { panic(err) }
	assert indexed_a == ['body']
	assert indexed_b == ['body']
	assert indexed_c == ['body']

	job := db.build_markdown_reflection_job('main', 'docs', 'doc-1'.bytes(), 'body', mut
		engine, 2) or { panic(err) }
	assert job.branch_name == 'main'
	assert job.table_name == 'docs'
	assert job.primary_key.bytestr() == 'doc-1'
	assert job.column_name == 'body'
	assert job.reflection_kind == 'summary'
	assert job.seed_scope == .path
	assert job.seed_text.contains('数据库优化和查询规划')
	assert job.evidence.len == 2
	assert job.evidence[0].table_name == 'docs'
	assert job.evidence[0].column_name == 'body'
	assert job.evidence[0].primary_key.bytestr() == 'doc-2'
	assert job.evidence[0].score > job.evidence[1].score
	assert job.evidence[1].primary_key.bytestr() == 'doc-3'

	hits := db.query_markdown_text_embeddings(mut engine, '数据库优化和查询规划',
		VectorSearchQuery{
		branch_name: 'main'
		limit:       2
		scope:       .path
		scope_set:   true
	}) or { panic(err) }
	assert hits.len == 2
	assert hits[0].table_name == 'docs'
	assert hits[0].column_name == 'body'
	assert hits[0].primary_key.len > 0

	persisted := db.persist_reflection_job(job, ReflectionPersistInput{
		title:      '数据库优化讨论'
		summary_md: '# Summary\n\n我们集中讨论了数据库查询优化。\n'
		insight_md: '## Insight\n\n优先保留本地优先和可回放证据。\n'
		topic_key:  'db-optimization'
	}, ChunkConfig.default(), CommitMeta{
		author:    'gwg'
		message:   'persist reflection'
		timestamp: 2
	}) or { panic(err) }
	assert persisted.reflection_id.len > 0
	assert persisted.derived_from_root_hash.len > 0
	assert persisted.source_refs.len == 2
	assert persisted.links.len == 4

	session := db.open_session('main') or { panic(err) }
	stored := session.get_row(mut db, 'memory_reflections', persisted.reflection_id.bytes()) or {
		panic(err)
	}
	stored_summary := stored.data.get('summary_md') or { panic(err) }
	match stored_summary {
		MarkdownRef {
			assert db.load_markdown(stored_summary) or { panic(err) } == '# Summary\n\n我们集中讨论了数据库查询优化。\n'
		}
		else {
			panic('expected markdown summary ref')
		}
	}
	stored_source_refs := stored.data.get('source_refs') or { panic(err) }
	match stored_source_refs {
		string {
			refs := decode_reflection_source_refs(stored_source_refs) or { panic(err) }
			assert refs.len == 2
			assert refs[0].table_name == 'docs'
			assert refs[0].column_name == 'body'
		}
		else {
			panic('expected source_refs json payload')
		}
	}

	link_rows := session.scan_table(mut db, 'memory_links', 10) or { panic(err) }
	assert link_rows.len == 4
	mut derived_from_count := 0
	mut semantic_neighbor_count := 0
	for link_row in link_rows {
		link_kind := link_row.data.get('link_kind') or { panic(err) }
		match link_kind {
			string {
				if link_kind == 'derived_from' {
					derived_from_count++
					from_table := link_row.data.get('from_table_name') or { panic(err) }
					match from_table {
						string { assert from_table == 'memory_reflections' }
						else { panic('expected from_table_name string') }
					}
				} else if link_kind == 'semantic_neighbor' {
					semantic_neighbor_count++
					from_table := link_row.data.get('from_table_name') or { panic(err) }
					match from_table {
						string { assert from_table == 'docs' }
						else { panic('expected from_table_name string') }
					}
				} else {
					panic('unexpected link kind: ${link_kind}')
				}
			}
			else {
				panic('expected link_kind string')
			}
		}
		to_table := link_row.data.get('to_table_name') or { panic(err) }
		match to_table {
			string { assert to_table == 'docs' }
			else { panic('expected to_table_name string') }
		}
		metadata_json := link_row.data.get('metadata_json') or { panic(err) }
		match metadata_json {
			string {
				assert metadata_json.contains('"anchor"')
				assert metadata_json.contains('"target_id"')
				assert metadata_json.contains('"seed_anchor"')
				assert metadata_json.contains('"reflection_kind"')
			}
			else {
				panic('expected metadata json string')
			}
		}
	}
	assert derived_from_count == 2
	assert semantic_neighbor_count == 2

	replay := db.replay_query(mut engine, ReplayQueryRequest{
		branch_name:      'main'
		text:             '数据库优化'
		seed_limit:       2
		neighbor_limit:   4
		reflection_limit: 2
	}) or { panic(err) }
	assert replay.source_hits.len == 2
	assert replay.source_hits[0].table_name == 'docs'
	assert replay.evidence_hits.len >= 2
	assert replay.evidence_hits.any(it.via_link_kind == 'semantic_neighbor')
	assert replay.reflections.len == 1
	assert replay.reflections[0].title == '数据库优化讨论'
	assert replay.reflections[0].summary_md.contains('数据库查询优化')
	assert replay.reflections[0].source_refs.len == 2

	overview := db.replay_overview(mut engine, ReplayQueryRequest{
		branch_name:      'main'
		text:             '数据库优化'
		seed_limit:       2
		neighbor_limit:   4
		reflection_limit: 2
	}) or { panic(err) }
	assert overview.topics.len == 1
	assert overview.topics[0].title == '数据库优化讨论'
	assert overview.topics[0].evidence_count == 2
	assert overview.evidence.len >= 2
	assert overview.evidence.any(it.via_link_kind == 'semantic_neighbor')
	assert overview.timeline.branch_name == 'main'
	assert overview.timeline.derived_from_root_hashes.len == 1
	assert overview.timeline.reflection_ids.len == 1
	assert overview.timeline.source_keys.len >= 2
}

fn test_reflect_memory_once_indexes_generates_and_persists() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-reflector-once')
	os.rmdir_all(dir) or {}
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	spec := reflector_docs_spec() or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.register_memory_capability(MemoryCapabilityDef.reflective_field('docs', 'body',
		ReflectionOptions{
		embedding_index: 'body_path_vec_idx'
		reflection_kind: 'summary'
	}) or { panic(err) }) or { panic(err) }
	ref_a := db.ingest_markdown('# Query\n\n数据库优化和查询规划\n') or { panic(err) }
	ref_b := db.ingest_markdown('# Indexes\n\n数据库索引设计与查询优化\n') or {
		panic(err)
	}
	mut row_a := TypedRowData.new()
	row_a.set('id', 'doc-1')
	row_a.set('body', ref_a)
	mut row_b := TypedRowData.new()
	row_b.set('id', 'doc-2')
	row_b.set('body', ref_b)
	codec := TypedRowCodec.new(spec.table)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('doc-1'.bytes())
			value: codec.encode(row_a)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('doc-2'.bytes())
			value: codec.encode(row_b)!
		},
	], ChunkConfig.default()) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed docs'
		timestamp: 1
	}) or { panic(err) }
	mut engine := ReflectorTestEmbeddingEngine{
		dims:    2
		vectors: {
			'数据库优化和查询规划':                [f32(1.0), 0.0]
			'数据库索引设计与查询优化':            [f32(0.97), 0.03]
			'Query\n\n数据库优化和查询规划':       [f32(0.98), 0.02]
			'Indexes\n\n数据库索引设计与查询优化': [f32(0.96), 0.04]
		}
	}
	mut generator := ReflectorTestGenerator{
		output: 'BEGIN_REFLECTION
TITLE: 数据库优化复盘
TOPIC: db-optimization
SUMMARY_MD:
# Summary

- 讨论了数据库优化和索引设计。

INSIGHT_MD:
## Insight

- 保留语义证据链。
END_REFLECTION'
	}
	persisted := db.reflect_memory_once('main', mut engine, mut generator, ReflectMemoryOptions{
		neighbor_limit: 2
		max_jobs:       1
		meta:           CommitMeta{
			author:    'gwg'
			message:   'auto reflect'
			timestamp: 2
		}
	}) or { panic(err) }
	assert persisted.len == 1
	assert persisted[0].title == '数据库优化复盘'
	assert persisted[0].source_refs.len == 1
	assert persisted[0].links.len == 2
	assert generator.prompts.len == 1
	assert generator.prompts[0].contains('数据库优化和查询规划')
	assert generator.prompts[0].contains('数据库索引设计与查询优化')
	session := db.open_session('main') or { panic(err) }
	reflection_rows := session.scan_table(mut db, 'memory_reflections', 0) or { panic(err) }
	link_rows := session.scan_table(mut db, 'memory_links', 0) or { panic(err) }
	assert reflection_rows.len == 1
	assert link_rows.len == 2

	second_pass := db.reflect_memory_once('main', mut engine, mut generator, ReflectMemoryOptions{
		neighbor_limit: 2
		max_jobs:       1
	}) or { panic(err) }
	assert second_pass.len == 1
	assert second_pass[0].reflection_id != persisted[0].reflection_id
	third_pass := db.reflect_memory_once('main', mut engine, mut generator, ReflectMemoryOptions{
		neighbor_limit: 2
		max_jobs:       1
	}) or { panic(err) }
	assert third_pass.len == 0
}

fn test_reflector_scheduler_threshold_decision() {
	mut scheduler := ReflectorScheduler.new(ReflectorScheduleOptions{
		write_threshold: 3
	})
	assert scheduler.decision().should_reflect == false
	scheduler.note_write(2)
	assert scheduler.decision().should_reflect == false
	scheduler.note_write(1)
	decision := scheduler.decision()
	assert decision.should_reflect == true
	assert decision.reason == 'write_threshold'
	assert decision.pending_writes == 3
	scheduler.reset_after_reflect(0)
	assert scheduler.decision().should_reflect == true
	scheduler.reset_after_reflect(1)
	assert scheduler.decision().should_reflect == false
}

fn test_reflector_state_persists_pending_writes() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-reflector-state')
	os.rmdir_all(dir) or {}
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	spec := reflector_docs_spec() or { panic(err) }
	db.register_table(spec) or { panic(err) }
	ref := db.ingest_markdown('# Init\n\n初始化分支\n') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', 'doc-1')
	row.set('body', ref)
	codec := TypedRowCodec.new(spec.table)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('doc-1'.bytes())
			value: codec.encode(row)!
		},
	], ChunkConfig.default()) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'init branch'
		timestamp: 1
	}) or { panic(err) }
	state := db.load_reflector_state('main') or { panic(err) }
	assert state.branch_name == 'main'
	assert state.pending_writes == 0
	updated := db.note_reflector_writes('main', 5, ChunkConfig.default(), CommitMeta{
		author:    'gwg'
		message:   'note writes'
		timestamp: 1
	}) or { panic(err) }
	assert updated.pending_writes == 5
	assert updated.updated_at.len > 0
	reloaded := db.load_reflector_state('main') or { panic(err) }
	assert reloaded.pending_writes == 5
	assert reloaded.last_reflected_root_hash.len == 0
}

fn test_reflector_scheduler_persistent_reflect_resets_state() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-reflector-persistent-scheduler')
	os.rmdir_all(dir) or {}
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	spec := reflector_docs_spec() or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.register_memory_capability(MemoryCapabilityDef.reflective_field('docs', 'body',
		ReflectionOptions{
		embedding_index: 'body_path_vec_idx'
		reflection_kind: 'summary'
	}) or { panic(err) }) or { panic(err) }
	ref_a := db.ingest_markdown('# Query\n\n数据库优化和查询规划\n') or { panic(err) }
	ref_b := db.ingest_markdown('# Indexes\n\n数据库索引设计与查询优化\n') or {
		panic(err)
	}
	mut row_a := TypedRowData.new()
	row_a.set('id', 'doc-1')
	row_a.set('body', ref_a)
	mut row_b := TypedRowData.new()
	row_b.set('id', 'doc-2')
	row_b.set('body', ref_b)
	codec := TypedRowCodec.new(spec.table)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('doc-1'.bytes())
			value: codec.encode(row_a)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('doc-2'.bytes())
			value: codec.encode(row_b)!
		},
	], ChunkConfig.default()) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed docs'
		timestamp: 1
	}) or { panic(err) }
	_ = db.note_reflector_writes('main', 3, ChunkConfig.default(), CommitMeta{
		author:    'gwg'
		message:   'note writes'
		timestamp: 2
	}) or { panic(err) }
	mut engine := ReflectorTestEmbeddingEngine{
		dims:    2
		vectors: {
			'数据库优化和查询规划':                [f32(1.0), 0.0]
			'数据库索引设计与查询优化':            [f32(0.97), 0.03]
			'Query\n\n数据库优化和查询规划':       [f32(0.98), 0.02]
			'Indexes\n\n数据库索引设计与查询优化': [f32(0.96), 0.04]
		}
	}
	mut generator := ReflectorTestGenerator{
		output: 'BEGIN_REFLECTION
TITLE: 持久调度复盘
TOPIC: db-optimization
SUMMARY_MD:
# Summary

- 讨论了数据库优化和索引设计。

INSIGHT_MD:
## Insight

- 写入阈值触发反思。
END_REFLECTION'
	}
	mut scheduler := ReflectorScheduler.new(ReflectorScheduleOptions{
		write_threshold: 3
		neighbor_limit:  2
		max_jobs:        1
	})
	persisted := scheduler.maybe_reflect_persistent(mut db, 'main', mut engine, mut generator,
		ChunkConfig.default(), CommitMeta{
		author:    'gwg'
		message:   'scheduled reflect'
		timestamp: 3
	}) or { panic(err) }
	assert persisted.len == 1
	state := db.load_reflector_state('main') or { panic(err) }
	assert state.pending_writes == 0
	assert state.last_reflected_root_hash == persisted[0].derived_from_root_hash
	assert state.last_reflected_at == persisted[0].created_at
}
