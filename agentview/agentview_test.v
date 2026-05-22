module agentview

import memory
import os
import storage

struct AgentViewTestEmbeddingEngine {
pub:
	dims    int
	vectors map[string][]f32
}

fn (engine AgentViewTestEmbeddingEngine) model_name() string {
	return 'test'
}

fn (engine AgentViewTestEmbeddingEngine) dimensions() int {
	return engine.dims
}

fn (mut engine AgentViewTestEmbeddingEngine) embed(text string) ![]f32 {
	if text !in engine.vectors {
		return error('missing test vector for `${text}`')
	}
	return engine.vectors[text].clone()
}

fn (mut engine AgentViewTestEmbeddingEngine) embed_batch(texts []string) ![][]f32 {
	mut out := [][]f32{cap: texts.len}
	for text in texts {
		out << engine.embed(text)!
	}
	return out
}

fn make_multi_session_codex_fixture(dest_root string) {
	fixture_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	os.rmdir_all(dest_root) or {}
	os.cp_all(fixture_root, dest_root, true) or { panic(err) }
	index_path := os.join_path(dest_root, 'session_index.jsonl')
	mut index_text := os.read_file(index_path) or { panic(err) }
	index_text += '\n{"id":"session-002","thread_name":"Fixture thread two","updated_at":"2026-04-02T11:05:00Z"}\n'
	os.write_file(index_path, index_text) or { panic(err) }
	source_path := os.join_path(dest_root, 'sessions', '2026', '04', '01',
		'rollout-2026-04-01T10-00-00-session-001.jsonl')
	mut second_text := os.read_file(source_path) or { panic(err) }
	second_text = second_text.replace('session-001', 'session-002')
	second_text = second_text.replace('Fixture thread', 'Fixture thread two')
	second_text = second_text.replace('Review this patch', 'Resume fixture second session')
	second_text = second_text.replace('I will inspect the patch.',
		'I will continue from the next batch.')
	second_text = second_text.replace('Checking changed files', 'Continuing batched sync')
	second_text = second_text.replace('call_001', 'call_002')
	second_text = second_text.replace('2026-04-01T10:00:00Z', '2026-04-02T11:00:00Z')
	second_text = second_text.replace('2026-04-01T10:00:05Z', '2026-04-02T11:00:05Z')
	second_text = second_text.replace('2026-04-01T10:00:06Z', '2026-04-02T11:00:06Z')
	second_text = second_text.replace('2026-04-01T10:00:07Z', '2026-04-02T11:00:07Z')
	second_text = second_text.replace('2026-04-01T10:00:08Z', '2026-04-02T11:00:08Z')
	second_text = second_text.replace('2026-04-01T10:00:09Z', '2026-04-02T11:00:09Z')
	second_dir := os.join_path(dest_root, 'sessions', '2026', '04', '02')
	os.mkdir_all(second_dir) or { panic(err) }
	second_path := os.join_path(second_dir, 'rollout-2026-04-02T11-00-00-session-002.jsonl')
	os.write_file(second_path, second_text) or { panic(err) }
}

fn test_session_id_from_path() {
	assert session_id_from_path('/tmp/rollout-2026-04-01T16-26-59-019d4827-2b6a-7161-a45f-7574568616a6.jsonl') == '019d4827-2b6a-7161-a45f-7574568616a6'
}

fn test_compact_snippet_trims_long_text() {
	snippet := compact_snippet('alpha beta gamma delta epsilon zeta eta theta iota kappa lambda',
		'theta', 24)
	assert snippet.contains('theta')
}

fn test_list_and_load_codex_sessions_from_fixture() {
	root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	sessions := list_codex_sessions(root, 10) or { panic(err) }
	assert sessions.len == 1
	assert sessions[0].id == 'session-001'
	assert sessions[0].title == 'Fixture thread'
	assert sessions[0].tool_calls == 1

	transcript := load_codex_session(root, 'session-001') or { panic(err) }
	assert transcript.entries.len == 5
	assert transcript.entries[0].role == 'user'
	assert transcript.entries[1].kind == .message
	assert transcript.entries[2].kind == .reasoning
	assert transcript.entries[3].kind == .tool_call
	assert transcript.entries[4].kind == .tool_result
}

fn test_pollydb_store_sync_and_query_fixture() {
	codex_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-fixture')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	stats := store.sync_codex(codex_root) or { panic(err) }
	assert stats.sessions == 1
	assert stats.entries == 5
	search_stats := store.ensure_search_indexes_with_progress(no_search_index_progress) or {
		panic(err)
	}
	assert search_stats.changed
	assert search_stats.rows_backfilled == 0

	sessions := store.list_sessions(10) or { panic(err) }
	assert sessions.len == 1
	assert sessions[0].title == 'Fixture thread'

	transcript := store.load_session('session-001') or { panic(err) }
	assert transcript.entries.len == 5
	assert transcript.entries[0].text == 'Review this patch'

	search_execution := store.search_entries_explained(SearchRequest{
		query:      'inspect'
		session_id: 'session-001'
		limit:      1
	}) or { panic(err) }
	assert search_execution.explain.strategy in ['general_fts_prefix', 'fts_no_hits',
		'session_index_substring']
	assert search_execution.explain.strategy != 'no_fts_indexes'

	list_page := store.list_sessions_page(SessionListRequest{
		query: 'fixture'
		limit: 10
	}) or { panic(err) }
	assert list_page.total == 1
	assert list_page.sessions.len == 1

	transcript_page := store.load_transcript_page(TranscriptRequest{
		session_id: 'session-001'
		offset:     1
		limit:      2
	}) or { panic(err) }
	assert transcript_page.total_entries == 5
	assert transcript_page.entries.len == 2
	assert transcript_page.entries[0].seq == 1
	assert transcript_page.entries[1].seq == 2

	second := store.sync_codex(codex_root) or { panic(err) }
	assert second.sessions == 0
	assert second.entries == 0
	assert second.skipped == 1
	search_second := store.ensure_search_indexes_with_progress(no_search_index_progress) or {
		panic(err)
	}
	assert search_second.rows_backfilled == 0

	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	spec := session.table_spec('sessions') or { panic(err) }
	assert spec.indexes.any(it.name == 'updated_at_cover_idx')
	entry_spec := session.table_spec('entries') or { panic(err) }
	assert entry_spec.indexes.any(it.name == 'entries_content_text_fts_idx')
	ingest_rows := session.scan_table(mut db, 'ingest_state', 0) or { panic(err) }
	entry_search_rows := session.scan_table(mut db, 'entry_search_state', 0) or { panic(err) }
	assert ingest_rows.len == 1
	assert entry_search_rows.len == 0
}

fn test_pollydb_store_can_enable_memory_schema() {
	codex_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-memory-schema')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	_ = store.sync_codex(codex_root) or { panic(err) }
	changed := store.ensure_memory_schema() or { panic(err) }
	assert changed

	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	entry_spec := session.table_spec('entries') or { panic(err) }
	assert entry_spec.indexes.any(it.name == 'entries_content_block_vec_idx')
	assert entry_spec.indexes.any(it.name == 'entries_content_path_vec_idx')
	capability := db.memory_capability('entries', 'content_md') or { panic(err) }
	assert capability.options.embedding_index == 'entries_content_path_vec_idx'
}

fn test_pollydb_store_sync_populates_markdown_for_memory_entries() {
	codex_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-memory-markdown')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	stats := store.sync_codex(codex_root) or { panic(err) }
	assert stats.sessions == 1
	assert stats.entries == 5

	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	entry_rows := session.scan_table(mut db, 'entries', 0) or { panic(err) }
	assert entry_rows.len == 5
	mut populated := 0
	mut empty := 0
	for row in entry_rows {
		entry := decode_session_entry(row) or { panic(err) }
		ref := opt_markdown_ref(row, 'content_md') or { panic('expected markdown ref') }
		if should_skip_markdown_index(entry, entry.text) {
			if ref.source_len == 0 {
				empty++
			}
			continue
		}
		assert ref.source_len > 0
		populated++
	}
	assert populated == 3
	assert empty == 2
}

fn test_pollydb_store_distills_memory_from_seeded_entries() {
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-memory-e2e')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	_ = store.ensure_memory_schema() or { panic(err) }
	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	cfg := storage.ChunkConfig.default()
	summary := SessionSummary{
		id:          'session-memory-001'
		title:       'Patch review memory'
		updated_at:  '2026-04-01T10:00:09Z'
		started_at:  '2026-04-01T10:00:00Z'
		cwd:         '/tmp/work'
		source:      'codex'
		originator:  'Codex Desktop'
		cli_version: '0.1.0'
		path:        '/tmp/memory-session.jsonl'
		entry_count: 3
		user_turns:  1
	}
	session_spec := sessions_spec() or { panic(err) }
	entry_spec := entries_spec(false) or { panic(err) }
	session_codec := storage.TypedRowCodec.new(session_spec.table)
	entry_codec := storage.TypedRowCodec.new(entry_spec.table)
	session_view := storage.TableView.new(storage.Tree{}, 'sessions')
	entry_view := storage.TableView.new(storage.Tree{}, 'entries')
	mut kvs := []storage.KVPair{}
	kvs << storage.KVPair{
		key:   session_view.row_key(summary.id.bytes())
		value: session_codec.encode(build_session_row(summary)) or {
			panic('encode session row: ${err}')
		}
	}
	entry_a := SessionEntry{
		seq:       0
		timestamp: '2026-04-01T10:00:05Z'
		kind:      .message
		role:      'user'
		text:      '遵循 V 的安装约定'
	}
	entry_b := SessionEntry{
		seq:       1
		timestamp: '2026-04-01T10:00:06Z'
		kind:      .message
		role:      'assistant'
		text:      '代码全面改成 import guweigang.vjsx。'
	}
	entry_c := SessionEntry{
		seq:       2
		timestamp: '2026-04-01T10:00:07Z'
		kind:      .message
		role:      'assistant'
		text:      '不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 这种临时软链方案。'
	}
	entry_a_id, entry_a_row := build_session_entry_row(summary, entry_a, ingest_markdown_for_store(mut db,
		'遵循 V 的安装约定') or { panic(err) })
	kvs << storage.KVPair{
		key:   entry_view.row_key(entry_a_id.bytes())
		value: entry_codec.encode(entry_a_row) or { panic('encode entry_a row: ${err}') }
	}
	entry_b_id, entry_b_row := build_session_entry_row(summary, entry_b, ingest_markdown_for_store(mut db,
		'代码全面改成 import guweigang.vjsx。') or { panic(err) })
	kvs << storage.KVPair{
		key:   entry_view.row_key(entry_b_id.bytes())
		value: entry_codec.encode(entry_b_row) or { panic('encode entry_b row: ${err}') }
	}
	entry_c_id, entry_c_row := build_session_entry_row(summary, entry_c, ingest_markdown_for_store(mut db,
		'不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 这种临时软链方案。') or { panic(err) })
	kvs << storage.KVPair{
		key:   entry_view.row_key(entry_c_id.bytes())
		value: entry_codec.encode(entry_c_row) or { panic('encode entry_c row: ${err}') }
	}
	mut tree := storage.Tree.build(kvs, cfg) or { panic('build tree: ${err}') }
	tree = storage.rebuild_typed_indexes_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or {
		panic('rebuild indexes: ${err}')
	}
	tree = storage.rebuild_typed_aggregates_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or {
		panic('rebuild aggregates: ${err}')
	}
	_ = db.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'gwg'
		message:   'seed agentview memory e2e'
		timestamp: 1
	}) or { panic('commit tree: ${err}') }
	db.close() or { panic(err) }

	mut engine := AgentViewTestEmbeddingEngine{
		dims:    2
		vectors: {
			'遵循 V 的安装约定':                                                                                              [
				f32(1.0),
				0.0,
			]
			'代码全面改成 import guweigang.vjsx。':                                                                           [
				f32(0.99),
				0.01,
			]
			'不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 这种临时软链方案。':                                                      [
				f32(0.97),
				0.03,
			]
			'遵循 V 的安装约定\n代码全面改成 import guweigang.vjsx\n不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 这种临时软链方案': [
				f32(0.985),
				0.015,
			]
		}
	}
	persisted := store.distill_recent_memory_heuristic(mut engine, MemoryDistillOptions{
		recent_sessions: 1
		max_jobs:        1
		neighbor_limit:  2
		min_evidence:    1
		candidate_limit: 5
	}) or { panic(err) }
	assert persisted.len == 1
	assert persisted[0].title.len > 0
	assert persisted[0].summary_md.len > 0
	assert persisted[0].source_refs.len >= 1

	db = storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	reflection_spec := session.table_spec('memory_reflections') or { panic(err) }
	assert reflection_spec.indexes.any(it.name == agentview_memory_reflections_title_fts_index)
	assert reflection_spec.indexes.any(it.name == agentview_memory_reflections_summary_fts_index)
	reflection_rows := session.scan_table(mut db, 'memory_reflections', 0) or { panic(err) }
	link_rows := session.scan_table(mut db, 'memory_links', 0) or { panic(err) }
	assert reflection_rows.len == 1
	assert link_rows.len >= 2
	db.close() or { panic(err) }

	listed := store.list_memory(MemoryListRequest{
		query: 'vjsx'
		limit: 5
	}) or { panic(err) }
	assert listed.total == 1
	assert listed.memories[0].active
	assert listed.memories[0].title.len > 0
	assert listed.memories[0].source_count >= 1
	context := store.memory_context(MemoryContextRequest{
		query:           'vjsx'
		limit:           3
		include_sources: true
	}) or { panic(err) }
	assert context.memories.len == 1
	assert context.markdown.contains('# Agent Memory Context')
	assert context.markdown.contains('source_refs:')
}

fn test_pollydb_store_delete_memory_removes_reflection_and_links() {
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-memory-delete')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	_ = store.ensure_memory_schema() or { panic(err) }
	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	cfg := storage.ChunkConfig.default()
	summary := SessionSummary{
		id:          'session-memory-delete-001'
		title:       'Delete memory'
		updated_at:  '2026-04-01T10:00:09Z'
		started_at:  '2026-04-01T10:00:00Z'
		cwd:         '/tmp/work'
		source:      'codex'
		originator:  'Codex Desktop'
		cli_version: '0.1.0'
		path:        '/tmp/memory-delete-session.jsonl'
		entry_count: 2
		user_turns:  1
	}
	session_spec := sessions_spec() or { panic(err) }
	entry_spec := entries_spec(false) or { panic(err) }
	session_codec := storage.TypedRowCodec.new(session_spec.table)
	entry_codec := storage.TypedRowCodec.new(entry_spec.table)
	session_view := storage.TableView.new(storage.Tree{}, 'sessions')
	entry_view := storage.TableView.new(storage.Tree{}, 'entries')
	mut kvs := []storage.KVPair{}
	kvs << storage.KVPair{
		key:   session_view.row_key(summary.id.bytes())
		value: session_codec.encode(build_session_row(summary)) or { panic(err) }
	}
	for idx, text in ['代码全面改成 import guweigang.vjsx。', '不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 这种临时软链方案。'] {
		entry := SessionEntry{
			seq:       idx
			timestamp: '2026-04-01T10:00:0${idx + 1}Z'
			kind:      .message
			role:      'assistant'
			text:      text
		}
		entry_id, entry_row := build_session_entry_row(summary, entry, ingest_markdown_for_store(mut db,
			text) or { panic(err) })
		kvs << storage.KVPair{
			key:   entry_view.row_key(entry_id.bytes())
			value: entry_codec.encode(entry_row) or { panic(err) }
		}
	}
	mut tree := storage.Tree.build(kvs, cfg) or { panic(err) }
	tree = storage.rebuild_typed_indexes_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	tree = storage.rebuild_typed_aggregates_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', tree, storage.CommitMeta{
		author:  'gwg'
		message: 'seed agentview memory delete'
	}) or { panic(err) }
	db.close() or { panic(err) }

	mut engine := AgentViewTestEmbeddingEngine{
		dims:    2
		vectors: {
			'代码全面改成 import guweigang.vjsx。':                                                                           [
				f32(0.99),
				0.01,
			]
			'不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 这种临时软链方案。':                                                      [
				f32(0.97),
				0.03,
			]
			'代码全面改成 import guweigang.vjsx\n不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 这种临时软链方案': [
				f32(0.985),
				0.015,
			]
		}
	}
	persisted := store.distill_recent_memory_heuristic(mut engine, MemoryDistillOptions{
		recent_sessions: 1
		max_jobs:        1
		neighbor_limit:  2
		min_evidence:    1
		candidate_limit: 5
	}) or { panic(err) }
	assert persisted.len == 1
	result := store.delete_memory([persisted[0].reflection_id, 'missing-memory-id']) or { panic(err) }
	assert result.deleted_reflections == 1
	assert result.deleted_links >= 2
	assert result.missing_ids == ['missing-memory-id']

	db = storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	reflection_rows := session.scan_table(mut db, 'memory_reflections', 0) or { panic(err) }
	link_rows := session.scan_table(mut db, 'memory_links', 0) or { panic(err) }
	assert reflection_rows.len == 0
	assert link_rows.len == 0
}

fn test_should_skip_markdown_index_skips_environment_context_blocks() {
	entry := SessionEntry{
		kind: .message
		text: '<environment_context>\n<cwd>/tmp/demo</cwd>\n<shell>zsh</shell>\n</environment_context>'
	}
	assert should_skip_markdown_index(entry, entry.text)
}

fn test_should_skip_markdown_index_skips_turn_abort_and_git_directives() {
	entry := SessionEntry{
		kind: .message
		text: '<turn_aborted>\nThe user interrupted the previous turn.\n</turn_aborted>\n\n::git-push{cwd="/tmp/demo" branch="main"}'
	}
	assert should_skip_markdown_index(entry, entry.text)
}

fn test_memory_salience_gate_keeps_durable_candidates_and_skips_transient_updates() {
	root_cause := classify_memory_salience(SessionEntry{
		kind: .message
		role: 'assistant'
		text: '我已经定位到直接触发点了：`buffer.js` 不是运行时动态推出来的，而是代码里直接用 `@VMODROOT` 拼路径去读。'
	})
	assert root_cause.memory_worthy
	assert root_cause.candidate_type == 'root_cause'

	constraint := classify_memory_salience(SessionEntry{
		kind: .message
		role: 'assistant'
		text: '不要求用户先手动 export，也兼容现在的安装脚本。'
	})
	assert constraint.memory_worthy
	assert constraint.candidate_type == 'constraint'

	update := classify_memory_salience(SessionEntry{
		kind: .message
		role: 'assistant'
		text: '我准备直接在 vhttpd 里加一个 vjsx_runtime_asset_root(...) 助手，并在创建 NodeRuntimeConfig 时接上。'
	})
	assert !update.memory_worthy
	assert update.skip_reason == 'transient_status'
}

fn test_memory_salience_claim_gate_filters_dialogue_controls_and_keeps_procedures() {
	dialogue := classify_memory_salience(SessionEntry{
		kind: .message
		role: 'user'
		text: '好的，同意，你继续'
	})
	assert !dialogue.memory_worthy
	assert dialogue.skip_reason == 'dialogue_control'

	procedure := classify_memory_salience(SessionEntry{
		kind: .message
		role: 'assistant'
		text: '不能直接当 PHP 脚本跑，改用官方 `run-tests.php` 复核它们，避免误判。'
	})
	assert procedure.memory_worthy
	assert procedure.candidate_type == 'constraint'
	assert procedure.claims.len == 1
	assert procedure.claims[0].text.contains('run-tests.php')
}

fn test_memory_salience_claim_gate_extracts_best_claim_from_mixed_text() {
	decision := classify_memory_salience(SessionEntry{
		kind: .message
		role: 'assistant'
		text: '我这轮主要做了三件事。\n最终做法是返回值从 box 中取出 zval 后再交给 ctx 管理。\n跑一个相关测试把 warning 确认清掉。'
	})
	assert decision.memory_worthy
	assert decision.candidate_type == 'decision'
	assert decision.claims.len == 1
	assert decision.claims[0].text.contains('zval')
	assert !decision.claims[0].text.contains('跑一个相关测试')
}

fn test_memory_card_topic_key_is_derived_from_polished_card_content() {
	input_a := memory.ReflectionPersistInput{
		title:      'V 安装约定'
		summary_md: '# 摘要\n\n- 代码全面改成 import guweigang.vjsx\n\n## 重要约束\n\n- 不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 临时软链方案\n'
	}
	input_b := memory.ReflectionPersistInput{
		title:      'V 安装约定'
		summary_md: '# 摘要\n\n- 代码全面改成 import guweigang.vjsx\n\n## 重要约束\n\n- 不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 临时软链方案\n'
	}
	input_c := memory.ReflectionPersistInput{
		title:      'HTTP 空闲端口'
		summary_md: '# 摘要\n\n- 先向系统申请空闲端口，再启动 HTTP 服务\n'
	}
	assert memory_card_topic_key(input_a) == memory_card_topic_key(input_b)
	assert memory_card_topic_key(input_a) != memory_card_topic_key(input_c)
	assert memory_card_topic_key(input_a).starts_with('agentview-card:')
}

fn test_memory_card_vector_ranking_uses_lexical_guard_as_veto_only() {
	left_title := 'V 安装约定'
	left_summary := '# 摘要\n\n- 代码全面改成 import guweigang.vjsx\n\n## 重要约束\n\n- 不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 临时软链方案\n'
	right_title := '遵循 V 的安装约定'
	right_summary := '# 摘要\n\n- 代码全面改成 import guweigang.vjsx\n\n## 重要约束\n\n- 不要先 clone 到 /tmp/vjsx 再 link\n'
	other_title := 'HTTP 空闲端口'
	other_summary := '# 摘要\n\n- 先向系统申请空闲端口，再启动 HTTP 服务\n'
	similar_vector := cosine_similarity([f32(1.0), 0.0], [f32(0.98), 0.02])
	unrelated_vector := cosine_similarity([f32(1.0), 0.0], [f32(0.0), 1.0])
	similar_guard := memory_card_lexical_guard_score(left_title, left_summary, right_title,
		right_summary)
	unrelated_guard := memory_card_lexical_guard_score(left_title, left_summary, other_title,
		other_summary)
	assert similar_vector > 0.75
	assert similar_guard > 0.18
	assert unrelated_vector < 0.75
	assert unrelated_guard < 0.18
}

fn test_memory_card_write_decision_keeps_durable_cards_and_discards_noise() {
	useful := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      'V 安装约定'
		summary_md: '# 摘要\n\n- 代码全面改成 import guweigang.vjsx\n\n## 重要约束\n\n- 不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 临时软链方案\n'
	})
	assert useful.keep

	boilerplate := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      'entries.content_md 记忆复盘'
		summary_md: '# 摘要\n\n- 当前主题已从 seed 与近邻证据中完成一次可回放蒸馏。\n'
	})
	assert !boilerplate.keep
	assert boilerplate.reason == 'boilerplate_title' || boilerplate.reason == 'no_durable_points'

	short_note := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '调用方式'
		summary_md: '# 摘要\n\n- 每次调用都传一遍\n'
	})
	assert !short_note.keep
	assert short_note.reason == 'no_durable_points'

	transient := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      'workflow 检查'
		summary_md: '# 摘要\n\n- 找到具体 workflow 和脚本链路后，我会直接指出是哪一步造成的\n'
	})
	assert !transient.keep
	assert transient.reason == 'no_durable_points'

	bad_summary := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      'RequestOwnedZBox 返回值'
		summary_md: r'# 摘要

- 这说明锅已经不在 sample 了，是真正的 bridge/runtime 返回值丢失
- WorkspaceContextMiddleware` 里 `$handler->handle($request)` 直接拿回了 `null

## 关键决策

- PHP 暴露的 dispatch_request/dispatch_body/dispatch_envelope/dispatch：返回 RequestOwnedZBox
'
	})
	assert !bad_summary.keep
	assert bad_summary.reason == 'bad_summary_point'

	hypothesis := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '这不是最终一定的答案，但如果它能立刻让这条 PHPT 通过，就说明崩点确实就在对象返回'
		summary_md: '# 摘要\n\n- 类方法返回对象\n- 这不是最终一定的答案，但如果它能立刻让这条 PHPT 通过，就说明崩点确实就在对象返回\n'
	})
	assert !hypothesis.keep
	assert hypothesis.reason == 'hypothesis_validation_title'

	process_title := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '把范围压到 prepared-query 这条链了'
		summary_md: '# 摘要\n\n- 不经过 VSlim Query 包装\n- 确认 query builder 的写接口能直接用，接下来就把 console 页的表单和 controller action 一次性补齐\n'
	})
	assert !process_title.keep
	assert process_title.reason == 'process_title'

	tiny_fix_title := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '这处很小，我直接改掉'
		summary_md: '# 摘要\n\n- 这处很小，我直接改掉：保留原来的时序，但不再绑定没用到的局部变量\n- 跑一个相关测试把 warning 确认清掉\n'
	})
	assert !tiny_fix_title.keep
	assert tiny_fix_title.reason == 'process_title'

	truncated_point := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      'prepared-query 写接口'
		summary_md: '# 摘要\n\n- 确认 query builder 的写接口能直接用，接下来就把 console 页的表单和 controller action 一次性补�...\n'
	})
	assert !truncated_point.keep
	assert truncated_point.reason == 'bad_summary_point'

	question_title := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '是不是同一个 `v_ptr` 被不同 PHP wrapper 重复接管'
		summary_md: '# 摘要\n\n- 是不是同一个 `v_ptr` 被不同 PHP wrapper 重复接管\n'
	})
	assert !question_title.keep
	assert question_title.reason == 'question_title'

	malformed_path := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      r'dispatch_request(new VSlim\Vhttpd\Request(...))` 这条验证路径里，表单 body 没有自动落成 `parsedBody'
		summary_md: r'# 摘要

- dispatch_request(new VSlim\Vhttpd\Request(...))` 这条验证路径里，表单 body 没有自动落成 `parsedBody
'
	})
	assert !malformed_path.keep
	assert malformed_path.reason == 'bad_summary_point'

	token_fragment := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      'vphp` 或 `vslim'
		summary_md: '# 摘要\n\n- 我同意，这里不该打补丁绕过去\n- vphp` 或 `vslim\n'
	})
	assert !token_fragment.keep
	assert token_fragment.reason == 'bad_summary_point'

	first_person_validation := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '我再看一下这轮改动边界和验证结果，确认没有漏掉明显的回归'
		summary_md: '# 摘要\n\n- 我再看一下这轮改动边界和验证结果，确认没有漏掉明显的回归\n'
	})
	assert !first_person_validation.keep
	assert first_person_validation.reason == 'bad_summary_point'

	baseline_validation := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '我回打一遍 baseline 确认不是偶发现象'
		summary_md: '# 摘要\n\n- 如果 baseline 仍炸、而任意去掉一个 middleware 都稳\n- 我回打一遍 baseline 确认不是偶发现象\n'
	})
	assert !baseline_validation.keep
	assert baseline_validation.reason == 'process_title'

	future_step := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      'bridge/runtime 返回值丢失'
		summary_md: '# 摘要\n\n- `WorkspaceContextMiddleware` 里 `$handler->handle($request)` 直接拿回了 `null`\n- 下一步我要去对齐崩溃前最后一批 `vphp_call_method` 日志\n'
	})
	assert !future_step.keep
	assert future_step.reason == 'bad_summary_point'

	regenerate_step := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '我要重新生成 `php_bridge.c`，这一步用 `emit-only` 就够了'
		summary_md: '# 摘要\n\n- 我要重新生成 `php_bridge.c`，这一步用 `emit-only` 就够了\n'
	})
	assert !regenerate_step.keep
	assert regenerate_step.reason == 'process_title'

	conditional_future := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '同一份 `.env`，PDO 能连、VSlim seed 不能连'
		summary_md: '# 摘要\n\n- 如果是，我会把读路径的失败面再收稳一点\n- 同一份 `.env`，PDO 能连、VSlim seed 不能连\n'
	})
	assert !conditional_future.keep
	assert conditional_future.reason == 'bad_summary_point'

	non_target_failure := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '这个失败也有信息量，不过还不是我们要的那个崩溃'
		summary_md: '# 摘要\n\n- 会话没带回去\n- 这个失败也有信息量，不过还不是我们要的那个崩溃\n'
	})
	assert !non_target_failure.keep
	assert non_target_failure.reason == 'hypothesis_validation_title'

	vague_title := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '定位到了'
		summary_md: '# 摘要\n\n- 定位到了：污染源不在 `authUser`，也不在 `resolveContext`，而是在 `dashboard()`\n'
	})
	assert !vague_title.keep
	assert vague_title.reason == 'vague_title'

	vague_signal_title := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '编译这边有新信号了'
		summary_md: '# 摘要\n\n- `Makefile` 这条 `ext` 没带 MySQL 头文件路径\n'
	})
	assert !vague_signal_title.keep
	assert vague_signal_title.reason == 'vague_title'

	raw_schema := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      'updated_at 这一列在旧库上没加成功'
		summary_md: '# 摘要\n\n- 表结构已经说明原因了：`updated_at` 这一列在旧库上没加成功，而 `chunks/status/owner` 加上了\n- ADD COLUMN updated_at datetime not null\n'
	})
	assert !raw_schema.keep
	assert raw_schema.reason == 'bad_summary_point'

	double_dot_truncated := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '第二跳已经进了 `documents.render`，说明 service 和 controller 绑定都没再丢，问题落圮..'
		summary_md: '# 摘要\n\n- 第二跳已经进了 `documents.render`，说明 service 和 controller 绑定都没再丢，问题落圮..\n'
	})
	assert !double_dot_truncated.keep
	assert double_dot_truncated.reason == 'corrupt_title'

	ascii_dot_after_cjk := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      r'`dispatch_request(new VSlim\Vhttpd\Request(...))` 这条验证路径里，表宮.'
		summary_md: r'# 摘要

- `dispatch_request(new VSlim\Vhttpd\Request(...))` 这条验证路径里，表宮.
'
	})
	assert !ascii_dot_after_cjk.keep
	assert ascii_dot_after_cjk.reason == 'corrupt_title'

	truncated_markdown_link := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '现在 [WorkspaceRepository.php](/Users/demo/app/Repositories/WorkspaceRepository.'
		summary_md: '# 摘要\n\n- 现在 [WorkspaceRepository.php](/Users/demo/app/Repositories/WorkspaceRepository.\n'
	})
	assert !truncated_markdown_link.keep
	assert truncated_markdown_link.reason == 'corrupt_title'

	unclosed_markdown_label := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '对应回归我补在了 [test_vslim_psr7_server_request_clone_auth_attribute_chain.'
		summary_md: '# 摘要\n\n- 对应回归我补在了 [test_vslim_psr7_server_request_clone_auth_attribute_chain.\n'
	})
	assert !unclosed_markdown_label.keep
	assert unclosed_markdown_label.reason == 'corrupt_title'

	corrupt_summary_char := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '`knowledge-studio` 崩溃定位'
		summary_md: '# 摘要\n\n- 我也重新编译了 [vslim.so](/Users/demo/vslim.so)，并确认一Ɲ\n'
	})
	assert !corrupt_summary_char.keep
	assert corrupt_summary_char.reason == 'bad_summary_point'

	unbalanced_cjk_quotes := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '2 attrs 不能回退”，一个看“3 attrs 能不能终于过'
		summary_md: '# 摘要\n\n- 2 attrs 不能回退”，一个看“3 attrs 能不能终于过\n'
	})
	assert !unbalanced_cjk_quotes.keep
	assert unbalanced_cjk_quotes.reason == 'corrupt_title'

	ascii_label := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      'session + access'
		summary_md: '# 摘要\n\n- session + access\n'
	})
	assert !ascii_label.keep
	assert ascii_label.reason == 'no_durable_points'

	future_check := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '只有 workspace middleware，没有 access/trace'
		summary_md: '# 摘要\n\n- 我再确认一次“只有 workspace middleware，没有 access/trace”时到底稳不稳\n'
	})
	assert !future_check.keep
	assert future_check.reason == 'bad_summary_point'

	sandbox_validation := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '改用直接 bootstrap app 的方式做请求级验证'
		summary_md: '# 摘要\n\n- 改用直接 bootstrap app 的方式做请求级验证\n- 本地起内置 server 被沙箱拦住了，不过这不影响我们验证逻辑\n'
	})
	assert !sandbox_validation.keep
	assert sandbox_validation.reason == 'process_title'

	phpt_run_process := memory_card_write_decision(memory_card_sanitize_input(memory.ReflectionPersistInput{
		title:      '/opt/homebrew/Cellar/php/8.5.4_1/lib/php/build/run-tests.php'
		summary_md: '# 摘要\n\n- 我现在用这个真跑两条 PHPT\n- /opt/homebrew/Cellar/php/8.5.4_1/lib/php/build/run-tests.php\n'
	}))
	assert !phpt_run_process.keep
	assert phpt_run_process.reason == 'title_replay_only'

	generic_caution := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '不能抢跑下结论'
		summary_md: '# 摘要\n\n- 单例控制器缓存 view\n- 我不想凭感觉猜了\n\n## 重要约束\n\n- 不能抢跑下结论\n'
	})
	assert !generic_caution.keep
	assert generic_caution.reason == 'vague_title'

	build_in_progress := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '构建还在跑，刚才两条 probe 又抢到了旧 `so`/中间态 不能当结论'
		summary_md: '# 摘要\n\n- 构建还在跑，刚才两条 probe 又抢到了旧 `so`/中间态 不能当结论\n\n## 重要约束\n\n- 构建还在跑，刚才两条 probe 又抢到了旧 `so`/中间态 不能当结论\n'
	})
	assert !build_in_progress.keep
	assert build_in_progress.reason == 'hypothesis_validation_title'

	edit_permission_noise := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '加了轻量加载器 [EnvLoader.php](/Users/demo/app/Support/EnvLoader.php)'
		summary_md: '# 摘要\n\n- 你现在可以直接改这两个文件\n- 加了轻量加载器 [EnvLoader.php](/Users/demo/app/Support/EnvLoader.php)\n'
	})
	assert !edit_permission_noise.keep
	assert edit_permission_noise.reason == 'bad_summary_point'

	title_replay := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '污染源不在 `authUser`，也不在 `resolveContext`，而是在 `dashboard()`'
		summary_md: '# 摘要\n\n- 污染源不在 `authUser`，也不在 `resolveContext`，而是在 `dashboard()`\n'
	})
	assert !title_replay.keep
	assert title_replay.reason == 'title_replay_only'

	title_summary_mismatch := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '`clone_psr7_response()` 直接复用 `body_ref`'
		summary_md: '# 摘要\n\n- `clone_psr7_server_request()` 直接复用 `body_ref` 和 `uri_ref`\n- 找到了关键不对劲的地方\n'
	})
	assert !title_summary_mismatch.keep
	assert title_summary_mismatch.reason == 'title_summary_mismatch'

	isolated_artifact := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '`make ext` 编译环境缺少 mysql.h'
		summary_md: '# 摘要\n\n- `make ext` 失败是个已知编译环境问题，不是这次 bug 本身：它少了 `mysql.h` include\n- vslim.so\n'
	})
	assert isolated_artifact.keep
	assert isolated_artifact.score < useful.score + 5

	strong_single_sentence := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '`persistent_assoc_with_value/without_key` 只服务于 `attributes_ref` 这一路，没有别的 payload 复用'
		summary_md: '# 摘要\n\n- `persistent_assoc_with_value/without_key` 只服务于 `attributes_ref` 这一路，没有别的 payload 复用\n'
	})
	assert strong_single_sentence.keep

	run_tests_constraint := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '不能直接当 PHP 脚本跑，改用官方 `run-tests.php` 复核它们，避免误判'
		summary_md: '# 摘要\n\n- 不能直接当 PHP 脚本跑，改用官方 `run-tests.php` 复核它们，避免误判\n'
	})
	assert run_tests_constraint.keep
}

fn test_memory_card_sanitize_input_removes_low_context_points() {
	input := memory.ReflectionPersistInput{
		title:      '不要顺手把 README 的启动说明补成可直接执行的版本'
		summary_md: '# 摘要\n\n- 骨架已经写进去了\n- 不要顺手把 README 的启动说明补成可直接执行的版本\n\n## 重要约束\n\n- 不要顺手把 README 的启动说明补成可直接执行的版本\n'
	}
	sanitized := memory_card_sanitize_input(input)
	assert !sanitized.summary_md.contains('骨架已经写进去了')
	assert sanitized.summary_md.contains('不要顺手把 README 的启动说明补成可直接执行的版本')
	assert memory_card_write_decision(sanitized).keep

	env_input := memory.ReflectionPersistInput{
		title:      '同一份 `.env`，PDO 能连、VSlim seed 不能连'
		summary_md: '# 摘要\n\n- 命令执行环境没有带上你项目里的 `.env`\n- using password: NO\n\n## 关键决策\n\n- 命令执行环境没有带上你项目里的 `.env`\n\n## 重要约束\n\n- 同一份 `.env`，PDO 能连、VSlim seed 不能连\n'
	}
	env_sanitized := memory_card_sanitize_input(env_input)
	assert !env_sanitized.summary_md.contains('using password: NO')
	assert env_sanitized.summary_md.contains('命令执行环境没有带上你项目里的 `.env`')
	assert memory_card_write_decision(env_sanitized).keep

	bridge_input := memory.ReflectionPersistInput{
		title:      '这刀只动了 `vphp` 的 C bridge 不需要重新转译 V，直接重链 `vslim.so` 就能验证'
		summary_md: '# 摘要\n\n- 这刀只动了 `vphp` 的 C bridge 不需要重新转译 V，直接重链 `vslim.so` 就能验证\n'
	}
	bridge_sanitized := memory_card_sanitize_input(bridge_input)
	assert bridge_sanitized.title.starts_with('只动了 `vphp`')
	assert !bridge_sanitized.title.contains('这刀')
	assert !bridge_sanitized.summary_md.contains('这刀')

	commit_boundary := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '不把 `knowledge-studio` 目录和运行产物塞进这笔 commit'
		summary_md: '# 摘要\n\n- 不把 `knowledge-studio` 目录和运行产物塞进这笔 commit\n'
	})
	assert !commit_boundary.keep
	assert commit_boundary.reason == 'process_title'

	closeout_validation := memory_card_write_decision(memory_card_sanitize_input(memory.ReflectionPersistInput{
		title:      '我把迁移/seed 命令也挂上了，避免 `README` 和 CLI 再脱节'
		summary_md: '# 摘要\n\n- 现在做一轮收口验证：语法、CLI 命令、以及 console 读 service/repository 之后是否还正常\n- 我把迁移/seed 命令也挂上了，避免 `README` 和 CLI 再脱节\n'
	}))
	assert !closeout_validation.keep
	assert closeout_validation.reason == 'title_replay_only'

	empty_section_input := memory_card_sanitize_input(memory.ReflectionPersistInput{
		title:      '迁移/seed 命令也挂上了，避免 `README` 和 CLI 再脱节'
		summary_md: '# 摘要\n\n- 迁移/seed 命令也挂上了，避免 `README` 和 CLI 再脱节\n\n## 关键决策\n\n## 重要约束\n\n- 迁移/seed 命令也挂上了，避免 `README` 和 CLI 再脱节\n'
	})
	assert !empty_section_input.summary_md.contains('## 关键决策')
	assert empty_section_input.summary_md.contains('## 重要约束')

	truncated_bold := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '不把结果放进模板，只看“调用本身”会不会污染链路'
		summary_md: '# 摘要\n\n- 这说明不是某一个 repo 结果块，而是**只要把 service 读出来的结果塞进 render payload\n'
	})
	assert !truncated_bold.keep
	assert truncated_bold.reason == 'bad_summary_point'

	vague_side_gap := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '这条失败里还挖出一个顺手的缺口'
		summary_md: '# 摘要\n\n- 这条失败里还挖出一个顺手的缺口：`Testing\\Harness->actingAs()` 在 app 尚未 boot 时走了默认 sessio\n'
	})
	assert !vague_side_gap.keep
	assert vague_side_gap.reason == 'vague_title'

	vague_difference := memory_card_write_decision(memory.ReflectionPersistInput{
		title:      '真实 app 的关键差异已经出来了'
		summary_md: '# 摘要\n\n- 最小复现已经给出硬信号了：`session + access` 这条链一上去，请求就被稳定打回 `302`\n'
	})
	assert !vague_difference.keep
	assert vague_difference.reason == 'vague_title'

	root_cause_rescue := memory_card_sanitize_input(memory.ReflectionPersistInput{
		title:      '改成直接让它跑到 `SIGSEGV`，只抓真实炸栈'
		summary_md: '# 摘要\n\n- 改成直接让它跑到 `SIGSEGV`，只抓真实炸栈\n- 所以根因不在 sample，也不在 Query builder，直接落在底层 V mysql prepared-result 这条实现上\n'
	})
	assert root_cause_rescue.title.contains('根因不在 sample')
	assert !root_cause_rescue.summary_md.contains('SIGSEGV')
	assert root_cause_rescue.summary_md.contains('prepared-result')
	assert memory_card_write_decision(root_cause_rescue).keep
}

fn test_memory_card_write_plan_explains_add_update_and_discard() {
	add_input := memory.ReflectionPersistInput{
		title:      'V 安装约定'
		topic_key:  'agentview:v-install-convention'
		summary_md: '# 摘要\n\n- 代码全面改成 import guweigang.vjsx\n\n## 重要约束\n\n- 不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 临时软链方案\n'
		insight_md: '## 推断\n\n- 这是后续 V 项目导入路径选择的稳定约束。\n'
	}
	add_profile := memory_card_quality_profile(add_input)
	add_decision := memory_card_write_decision_from_profile(add_profile)
	add_plan := memory_card_write_plan(add_input, add_profile, add_decision, 2, '')
	assert add_plan.action == 'add'
	assert add_plan.reason == 'keep'
	assert add_plan.trace.confidence == 'high'
	assert 'multi_evidence' in add_plan.trace.signals
	assert 'score_pass' in add_plan.trace.signals
	assert add_plan.trace.blockers.len == 0

	update_plan := memory_card_write_plan(add_input, add_profile, add_decision, 2,
		'memory-reflection-001')
	assert update_plan.action == 'update'
	assert update_plan.reason == 'similar_existing_memory'
	assert 'matched_existing_memory' in update_plan.trace.signals

	discard_input := memory.ReflectionPersistInput{
		title:      '污染源不在 `authUser`，也不在 `resolveContext`，而是在 `dashboard()`'
		topic_key:  'agentview:weak-title-replay'
		summary_md: '# 摘要\n\n- 污染源不在 `authUser`，也不在 `resolveContext`，而是在 `dashboard()`\n'
	}
	discard_profile := memory_card_quality_profile(discard_input)
	discard_decision := memory_card_write_decision_from_profile(discard_profile)
	discard_plan := memory_card_write_plan(discard_input, discard_profile, discard_decision, 1, '')
	assert discard_plan.action == 'discard'
	assert discard_plan.reason == 'title_replay_only'
	assert discard_plan.trace.inference == 'candidate failed the durable-memory quality gate'
	assert 'title_replay_only' in discard_plan.trace.blockers

	weak_single := memory.ReflectionPersistInput{
		title:      '日志文件这条没留下来，改用直接 stderr 输出去抓最后一段'
		topic_key:  'agentview:weak-debug-process'
		summary_md: '# 摘要\n\n- 日志文件这条没留下来，改用直接 stderr 输出去抓最后一段\n- 现在最重要的是看到崩溃前最后释放的是哪一类对象\n\n## 关键决策\n\n- 日志文件这条没留下来，改用直接 stderr 输出去抓最后一段\n'
	}
	weak_profile := memory_card_quality_profile(weak_single)
	weak_decision := memory_card_write_decision_from_profile(weak_profile)
	weak_plan := memory_card_write_plan(weak_single, weak_profile, weak_decision, 1, '')
	assert weak_plan.action == 'defer'
	assert weak_plan.reason == 'weak_single_evidence'
	assert weak_plan.trace.inference == 'candidate is not stable enough for L1 and should be revisited by scene-level memory'
	assert 'weak_single_evidence' in weak_plan.trace.blockers

	strong_single := memory.ReflectionPersistInput{
		title:      '不能直接当 PHP 脚本跑，改用官方 `run-tests.php` 复核它们，避免误判'
		topic_key:  'agentview:run-tests-constraint'
		summary_md: '# 摘要\n\n- 不能直接当 PHP 脚本跑，改用官方 `run-tests.php` 复核它们，避免误判\n'
	}
	strong_profile := memory_card_quality_profile(strong_single)
	strong_decision := memory_card_write_decision_from_profile(strong_profile)
	strong_plan := memory_card_write_plan(strong_single, strong_profile, strong_decision, 1,
		'')
	assert strong_plan.action == 'add'
	assert strong_plan.reason == 'keep'
}

fn test_pollydb_store_discards_low_value_memory_from_synced_fixture() {
	codex_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-memory-sync-e2e')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	stats := store.sync_codex(codex_root) or { panic(err) }
	assert stats.sessions == 1
	assert stats.entries == 5
	_ = store.ensure_memory_schema() or { panic(err) }

	mut engine := AgentViewTestEmbeddingEngine{
		dims:    2
		vectors: {
			'Review this patch':         [f32(1.0), 0.0]
			'I will inspect the patch.': [f32(0.99), 0.01]
			'Checking changed files':    [f32(0.97), 0.03]
		}
	}
	persisted := store.distill_recent_memory_heuristic(mut engine, MemoryDistillOptions{
		recent_sessions: 1
		max_jobs:        1
		neighbor_limit:  2
		min_evidence:    1
		candidate_limit: 5
	}) or { panic(err) }
	assert persisted.len == 0

	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	if db.has_table('memory_reflections') {
		reflection_rows := session.scan_table(mut db, 'memory_reflections', 0) or { panic(err) }
		assert reflection_rows.len == 0
	} else {
		assert !db.has_table('memory_reflections')
	}
	if db.has_table('memory_links') {
		link_rows := session.scan_table(mut db, 'memory_links', 0) or { panic(err) }
		assert link_rows.len == 0
	} else {
		assert !db.has_table('memory_links')
	}
}

fn test_pollydb_store_previews_memory_without_persisting_reflections() {
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-memory-preview')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	_ = store.ensure_memory_schema() or { panic(err) }
	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	cfg := storage.ChunkConfig.default()
	summary := SessionSummary{
		id:          'session-preview-001'
		title:       'Preview memory'
		updated_at:  '2026-04-01T10:00:09Z'
		started_at:  '2026-04-01T10:00:00Z'
		cwd:         '/tmp/work'
		source:      'codex'
		originator:  'Codex Desktop'
		cli_version: '0.1.0'
		path:        '/tmp/preview-session.jsonl'
		entry_count: 2
		user_turns:  1
	}
	session_spec := sessions_spec() or { panic(err) }
	entry_spec := entries_spec(false) or { panic(err) }
	session_codec := storage.TypedRowCodec.new(session_spec.table)
	entry_codec := storage.TypedRowCodec.new(entry_spec.table)
	session_view := storage.TableView.new(storage.Tree{}, 'sessions')
	entry_view := storage.TableView.new(storage.Tree{}, 'entries')
	mut kvs := []storage.KVPair{}
	kvs << storage.KVPair{
		key:   session_view.row_key(summary.id.bytes())
		value: session_codec.encode(build_session_row(summary)) or { panic(err) }
	}
	entry_a := SessionEntry{
		seq:       0
		timestamp: '2026-04-01T10:00:05Z'
		kind:      .message
		role:      'assistant'
		text:      '代码全面改成 import guweigang.vjsx。'
	}
	entry_b := SessionEntry{
		seq:       1
		timestamp: '2026-04-01T10:00:06Z'
		kind:      .message
		role:      'assistant'
		text:      '不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 这种临时软链方案。'
	}
	entry_a_id, entry_a_row := build_session_entry_row(summary, entry_a, ingest_markdown_for_store(mut db,
		entry_a.text) or { panic(err) })
	kvs << storage.KVPair{
		key:   entry_view.row_key(entry_a_id.bytes())
		value: entry_codec.encode(entry_a_row) or { panic(err) }
	}
	entry_b_id, entry_b_row := build_session_entry_row(summary, entry_b, ingest_markdown_for_store(mut db,
		entry_b.text) or { panic(err) })
	kvs << storage.KVPair{
		key:   entry_view.row_key(entry_b_id.bytes())
		value: entry_codec.encode(entry_b_row) or { panic(err) }
	}
	mut tree := storage.Tree.build(kvs, cfg) or { panic(err) }
	tree = storage.rebuild_typed_indexes_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	tree = storage.rebuild_typed_aggregates_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'gwg'
		message:   'seed agentview memory preview'
		timestamp: 1
	}) or { panic(err) }
	db.close() or { panic(err) }

	mut engine := AgentViewTestEmbeddingEngine{
		dims:    2
		vectors: {
			entry_a.text:                                                                                  [
				f32(1.0),
				0.0,
			]
			entry_b.text:                                                                                  [
				f32(0.98),
				0.02,
			]
			'代码全面改成 import guweigang.vjsx\n不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 这种临时软链方案': [
				f32(0.99),
				0.01,
			]
		}
	}
	previews := store.preview_recent_memory_heuristic(mut engine, MemoryDistillOptions{
		recent_sessions: 1
		max_jobs:        1
		neighbor_limit:  2
		min_evidence:    1
		candidate_limit: 5
	}) or { panic(err) }
	assert previews.len == 1
	assert previews[0].decision.keep || previews[0].decision.reason.len > 0
	assert previews[0].write_plan.action in ['add', 'update', 'discard']
	assert previews[0].write_plan.trace.evidence_count > 0
	assert previews[0].write_plan.trace.candidate_title.len > 0

	db = storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	if db.has_table('memory_reflections') {
		reflection_rows := session.scan_table(mut db, 'memory_reflections', 0) or { panic(err) }
		assert reflection_rows.len == 0
	} else {
		assert !db.has_table('memory_reflections')
	}
	if db.has_table('memory_links') {
		link_rows := session.scan_table(mut db, 'memory_links', 0) or { panic(err) }
		assert link_rows.len == 0
	} else {
		assert !db.has_table('memory_links')
	}
}

fn test_build_memory_segment_anchors_splits_topics_streamingly() {
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-memory-segments')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	_ = store.ensure_memory_schema() or { panic(err) }
	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	cfg := storage.ChunkConfig.default()
	summary := SessionSummary{
		id:          'session-segment-001'
		title:       'Segment memory'
		updated_at:  '2026-04-01T10:00:09Z'
		started_at:  '2026-04-01T10:00:00Z'
		cwd:         '/tmp/work'
		source:      'codex'
		originator:  'Codex Desktop'
		cli_version: '0.1.0'
		path:        '/tmp/segment-session.jsonl'
		entry_count: 4
		user_turns:  2
	}
	session_spec := sessions_spec() or { panic(err) }
	entry_spec := entries_spec(false) or { panic(err) }
	session_codec := storage.TypedRowCodec.new(session_spec.table)
	entry_codec := storage.TypedRowCodec.new(entry_spec.table)
	session_view := storage.TableView.new(storage.Tree{}, 'sessions')
	entry_view := storage.TableView.new(storage.Tree{}, 'entries')
	mut kvs := []storage.KVPair{}
	kvs << storage.KVPair{
		key:   session_view.row_key(summary.id.bytes())
		value: session_codec.encode(build_session_row(summary)) or {
			panic('encode session row: ${err}')
		}
	}
	entries := [
		SessionEntry{
			seq:       0
			timestamp: '2026-04-01T10:00:05Z'
			kind:      .message
			role:      'user'
			text:      '决定遵循 V 的安装约定'
		},
		SessionEntry{
			seq:       1
			timestamp: '2026-04-01T10:00:06Z'
			kind:      .message
			role:      'assistant'
			text:      '代码全面改成 import guweigang.vjsx。'
		},
		SessionEntry{
			seq:       2
			timestamp: '2026-04-01T10:00:07Z'
			kind:      .message
			role:      'user'
			text:      '确认 runtime asset root 方案'
		},
		SessionEntry{
			seq:       3
			timestamp: '2026-04-01T10:00:08Z'
			kind:      .message
			role:      'assistant'
			text:      'README 的安装说明：默认会自动找包内 runtime/vjsx，也支持 VJSX_ASSET_ROOT 覆盖'
		},
	]
	for entry in entries {
		entry_id, entry_row := build_session_entry_row(summary, entry, ingest_markdown_for_store(mut db,
			entry.text) or { panic(err) })
		kvs << storage.KVPair{
			key:   entry_view.row_key(entry_id.bytes())
			value: entry_codec.encode(entry_row) or { panic('encode entry row: ${err}') }
		}
	}
	mut tree := storage.Tree.build(kvs, cfg) or { panic('build tree: ${err}') }
	tree = storage.rebuild_typed_indexes_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or {
		panic('rebuild indexes: ${err}')
	}
	tree = storage.rebuild_typed_aggregates_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or {
		panic('rebuild aggregates: ${err}')
	}
	_ = db.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'gwg'
		message:   'seed agentview memory segments'
		timestamp: 1
	}) or { panic('commit tree: ${err}') }

	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	rows := recent_entry_rows(mut db, session, 1) or { panic(err) }
	mut engine := AgentViewTestEmbeddingEngine{
		dims:    2
		vectors: {
			'决定遵循 V 的安装约定':                                                         [
				f32(1.0),
				0.0,
			]
			'代码全面改成 import guweigang.vjsx。':                                          [
				f32(0.98),
				0.02,
			]
			'确认 runtime asset root 方案':                                                  [
				f32(0.0),
				1.0,
			]
			'README 的安装说明：默认会自动找包内 runtime/vjsx，也支持 VJSX_ASSET_ROOT 覆盖': [
				f32(0.02),
				0.98,
			]
		}
	}
	candidates, report := memory_candidates_for_embedding(mut db, session, rows, 0, 0) or {
		panic(err)
	}
	assert report.embedding_candidate_entries == 4
	anchors := build_memory_segment_anchors(candidates, mut engine, 0) or { panic(err) }
	assert anchors.len == 2
	assert anchors[0].primary_key.bytestr() == 'session-segment-001:3'
	assert anchors[1].primary_key.bytestr() == 'session-segment-001:1'
	assert anchors[0].entry_count == 2
	assert anchors[1].entry_count == 2
}

fn test_memory_candidates_for_embedding_supports_offset_sampling() {
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-memory-candidate-offset')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	_ = store.ensure_memory_schema() or { panic(err) }
	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	cfg := storage.ChunkConfig.default()
	summary := SessionSummary{
		id:          'session-offset-001'
		title:       'Offset memory'
		updated_at:  '2026-04-01T10:00:09Z'
		started_at:  '2026-04-01T10:00:00Z'
		cwd:         '/tmp/work'
		source:      'codex'
		originator:  'Codex Desktop'
		cli_version: '0.1.0'
		path:        '/tmp/offset-session.jsonl'
		entry_count: 3
		user_turns:  1
	}
	session_spec := sessions_spec() or { panic(err) }
	entry_spec := entries_spec(false) or { panic(err) }
	session_codec := storage.TypedRowCodec.new(session_spec.table)
	entry_codec := storage.TypedRowCodec.new(entry_spec.table)
	session_view := storage.TableView.new(storage.Tree{}, 'sessions')
	entry_view := storage.TableView.new(storage.Tree{}, 'entries')
	mut kvs := []storage.KVPair{}
	kvs << storage.KVPair{
		key:   session_view.row_key(summary.id.bytes())
		value: session_codec.encode(build_session_row(summary)) or { panic(err) }
	}
	for idx, text in ['新增 alpha durable API。', '新增 beta durable API。',
		'新增 gamma durable API。'] {
		entry := SessionEntry{
			seq:       idx
			timestamp: '2026-04-01T10:00:0${idx + 1}Z'
			kind:      .message
			role:      'assistant'
			text:      text
		}
		entry_id, entry_row := build_session_entry_row(summary, entry, ingest_markdown_for_store(mut db, text) or {
			panic(err)
		})
		kvs << storage.KVPair{
			key:   entry_view.row_key(entry_id.bytes())
			value: entry_codec.encode(entry_row) or { panic(err) }
		}
	}
	mut tree := storage.Tree.build(kvs, cfg) or { panic(err) }
	tree = storage.rebuild_typed_indexes_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	tree = storage.rebuild_typed_aggregates_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', tree, storage.CommitMeta{
		author:  'gwg'
		message: 'seed candidate offset'
	}) or { panic(err) }
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	rows := recent_entry_rows(mut db, session, 1) or { panic(err) }
	first, _ := memory_candidates_for_embedding(mut db, session, rows, 1, 0) or { panic(err) }
	second, _ := memory_candidates_for_embedding(mut db, session, rows, 1, 1) or { panic(err) }
	assert first.len == 1
	assert second.len == 1
	assert first[0].primary_key() != second[0].primary_key()
}

fn test_memory_candidates_for_embedding_limit_skips_undistillable_noise_before_window() {
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-memory-candidate-outline-filter')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	_ = store.ensure_memory_schema() or { panic(err) }
	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	cfg := storage.ChunkConfig.default()
	summary := SessionSummary{
		id:          'session-outline-filter-001'
		title:       'Outline filter memory'
		updated_at:  '2026-04-01T10:00:09Z'
		started_at:  '2026-04-01T10:00:00Z'
		cwd:         '/tmp/work'
		source:      'codex'
		originator:  'Codex Desktop'
		cli_version: '0.1.0'
		path:        '/tmp/outline-filter-session.jsonl'
		entry_count: 4
		user_turns:  1
	}
	session_spec := sessions_spec() or { panic(err) }
	entry_spec := entries_spec(false) or { panic(err) }
	session_codec := storage.TypedRowCodec.new(session_spec.table)
	entry_codec := storage.TypedRowCodec.new(entry_spec.table)
	session_view := storage.TableView.new(storage.Tree{}, 'sessions')
	entry_view := storage.TableView.new(storage.Tree{}, 'entries')
	mut kvs := []storage.KVPair{}
	kvs << storage.KVPair{
		key:   session_view.row_key(summary.id.bytes())
		value: session_codec.encode(build_session_row(summary)) or { panic(err) }
	}
	for idx, text in ['builtin__DenseArray_has_index', 'knowledge-studio',
		'同意，你继续，一定要挖出 vslim 或 vphp 的 bug。',
		'新增 AgentView 记忆预览 write plan，并输出 signals 与 blockers。'] {
		entry := SessionEntry{
			seq:       idx
			timestamp: '2026-04-01T10:00:0${idx + 1}Z'
			kind:      .message
			role:      'assistant'
			text:      text
		}
		entry_id, entry_row := build_session_entry_row(summary, entry, ingest_markdown_for_store(mut db, text) or {
			panic(err)
		})
		kvs << storage.KVPair{
			key:   entry_view.row_key(entry_id.bytes())
			value: entry_codec.encode(entry_row) or { panic(err) }
		}
	}
	mut tree := storage.Tree.build(kvs, cfg) or { panic(err) }
	tree = storage.rebuild_typed_indexes_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	tree = storage.rebuild_typed_aggregates_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', tree, storage.CommitMeta{
		author:  'gwg'
		message: 'seed candidate outline filter'
	}) or { panic(err) }
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	rows := recent_entry_rows(mut db, session, 1) or { panic(err) }
	candidates, report := memory_candidates_for_embedding(mut db, session, rows, 1, 0) or {
		panic(err)
	}
	assert candidates.len == 1
	assert candidates[0].entry.text.contains('write plan')
	assert report.skipped_by_reason['dialogue_control'] == 1
	assert report.discarded_before_embedding['undistillable_outline_before_embedding'] >= 1
}

fn test_build_memory_segment_anchors_prefers_technical_over_workflow_status() {
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-memory-segment-priority')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	_ = store.ensure_memory_schema() or { panic(err) }
	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	cfg := storage.ChunkConfig.default()
	summary := SessionSummary{
		id:          'session-segment-002'
		title:       'Segment priority'
		updated_at:  '2026-04-01T10:00:09Z'
		started_at:  '2026-04-01T10:00:00Z'
		cwd:         '/tmp/work'
		source:      'codex'
		originator:  'Codex Desktop'
		cli_version: '0.1.0'
		path:        '/tmp/segment-priority-session.jsonl'
		entry_count: 4
		user_turns:  2
	}
	session_spec := sessions_spec() or { panic(err) }
	entry_spec := entries_spec(false) or { panic(err) }
	session_codec := storage.TypedRowCodec.new(session_spec.table)
	entry_codec := storage.TypedRowCodec.new(entry_spec.table)
	session_view := storage.TableView.new(storage.Tree{}, 'sessions')
	entry_view := storage.TableView.new(storage.Tree{}, 'entries')
	mut kvs := []storage.KVPair{}
	kvs << storage.KVPair{
		key:   session_view.row_key(summary.id.bytes())
		value: session_codec.encode(build_session_row(summary)) or { panic(err) }
	}
	entries := [
		SessionEntry{
			seq:       0
			timestamp: '2026-04-01T10:00:05Z'
			kind:      .message
			role:      'assistant'
			text:      '验证通过了，我现在把这批文件按同一组功能改动一起提交。随后会把当前 main 上的两条本地提交一并推到远端。'
		},
		SessionEntry{
			seq:       1
			timestamp: '2026-04-01T10:00:06Z'
			kind:      .message
			role:      'assistant'
			text:      '测试已经启动，我在等目标用例跑完。'
		},
		SessionEntry{
			seq:       2
			timestamp: '2026-04-01T10:00:07Z'
			kind:      .message
			role:      'assistant'
			text:      '我已经定位到直接触发点了：`buffer.js` 不是运行时动态推出来的，而是代码里直接用 `@VMODROOT` 拼路径去读。'
		},
		SessionEntry{
			seq:       3
			timestamp: '2026-04-01T10:00:08Z'
			kind:      .message
			role:      'assistant'
			text:      '这样就能解释为什么你的进程会去找 `/tmp/vjsx/...`，也说明运行时资源路径解析依赖 `@VMODROOT`。'
		},
	]
	for entry in entries {
		entry_id, entry_row := build_session_entry_row(summary, entry, ingest_markdown_for_store(mut db,
			entry.text) or { panic(err) })
		kvs << storage.KVPair{
			key:   entry_view.row_key(entry_id.bytes())
			value: entry_codec.encode(entry_row) or { panic(err) }
		}
	}
	mut tree := storage.Tree.build(kvs, cfg) or { panic(err) }
	tree = storage.rebuild_typed_indexes_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	tree = storage.rebuild_typed_aggregates_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'gwg'
		message:   'seed agentview memory segment priority'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	rows := recent_entry_rows(mut db, session, 1) or { panic(err) }
	mut engine := AgentViewTestEmbeddingEngine{
		dims:    2
		vectors: {
			'我已经定位到直接触发点了：`buffer.js` 不是运行时动态推出来的，而是代码里直接用 `@VMODROOT` 拼路径去读。': [
				f32(0.0),
				1.0,
			]
			'这样就能解释为什么你的进程会去找 `/tmp/vjsx/...`，也说明运行时资源路径解析依赖 `@VMODROOT`。':            [
				f32(0.02),
				0.98,
			]
		}
	}
	candidates, report := memory_candidates_for_embedding(mut db, session, rows, 0, 0) or {
		panic(err)
	}
	assert report.skipped_by_reason['transient_status'] == 2
	assert report.embedding_candidate_entries >= 1
	anchors := build_memory_segment_anchors(candidates, mut engine, 0) or { panic(err) }
	assert anchors.len == 1
	assert anchors[0].segment_kind == 'root_cause'
	assert anchors[0].segment_horizon == 'durable'
	assert anchors[0].primary_key.bytestr() == 'session-segment-002:2'
}

fn test_build_memory_segment_anchors_defers_execution_context_segments() {
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-memory-segment-execution-context')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	_ = store.ensure_memory_schema() or { panic(err) }
	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	cfg := storage.ChunkConfig.default()
	summary := SessionSummary{
		id:          'session-segment-003'
		title:       'Execution context priority'
		updated_at:  '2026-04-01T10:00:09Z'
		started_at:  '2026-04-01T10:00:00Z'
		cwd:         '/tmp/work'
		source:      'codex'
		originator:  'Codex Desktop'
		cli_version: '0.1.0'
		path:        '/tmp/segment-execution-context-session.jsonl'
		entry_count: 4
		user_turns:  2
	}
	session_spec := sessions_spec() or { panic(err) }
	entry_spec := entries_spec(false) or { panic(err) }
	session_codec := storage.TypedRowCodec.new(session_spec.table)
	entry_codec := storage.TypedRowCodec.new(entry_spec.table)
	session_view := storage.TableView.new(storage.Tree{}, 'sessions')
	entry_view := storage.TableView.new(storage.Tree{}, 'entries')
	mut kvs := []storage.KVPair{}
	kvs << storage.KVPair{
		key:   session_view.row_key(summary.id.bytes())
		value: session_codec.encode(build_session_row(summary)) or { panic(err) }
	}
	entries := [
		SessionEntry{
			seq:       0
			timestamp: '2026-04-01T10:00:05Z'
			kind:      .message
			role:      'assistant'
			text:      '现在是在受限沙箱里。git push 这一步需要提权才能访问远端，我先申请权限并顺手确认当前分支状态。'
		},
		SessionEntry{
			seq:       1
			timestamp: '2026-04-01T10:00:06Z'
			kind:      .message
			role:      'assistant'
			text:      '当前在 main，而且本地还有 1 个尚未推送的提交。'
		},
		SessionEntry{
			seq:       2
			timestamp: '2026-04-01T10:00:07Z'
			kind:      .message
			role:      'assistant'
			text:      '我已经定位到直接触发点了：`buffer.js` 不是运行时动态推出来的，而是代码里直接用 `@VMODROOT` 拼路径去读。'
		},
		SessionEntry{
			seq:       3
			timestamp: '2026-04-01T10:00:08Z'
			kind:      .message
			role:      'assistant'
			text:      '这样就能解释为什么你的进程会去找 `/tmp/vjsx/...`，也说明运行时资源路径解析依赖 `@VMODROOT`。'
		},
	]
	for entry in entries {
		entry_id, entry_row := build_session_entry_row(summary, entry, ingest_markdown_for_store(mut db,
			entry.text) or { panic(err) })
		kvs << storage.KVPair{
			key:   entry_view.row_key(entry_id.bytes())
			value: entry_codec.encode(entry_row) or { panic(err) }
		}
	}
	mut tree := storage.Tree.build(kvs, cfg) or { panic(err) }
	tree = storage.rebuild_typed_indexes_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	tree = storage.rebuild_typed_aggregates_for_specs(tree, [session_spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entry_spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'gwg'
		message:   'seed agentview memory execution context priority'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	rows := recent_entry_rows(mut db, session, 1) or { panic(err) }
	mut engine := AgentViewTestEmbeddingEngine{
		dims:    2
		vectors: {
			'我已经定位到直接触发点了：`buffer.js` 不是运行时动态推出来的，而是代码里直接用 `@VMODROOT` 拼路径去读。': [
				f32(0.0),
				1.0,
			]
			'这样就能解释为什么你的进程会去找 `/tmp/vjsx/...`，也说明运行时资源路径解析依赖 `@VMODROOT`。':            [
				f32(0.02),
				0.98,
			]
		}
	}
	candidates, report := memory_candidates_for_embedding(mut db, session, rows, 0, 0) or {
		panic(err)
	}
	assert report.discarded_before_embedding['transient_before_embedding'] == 2
	assert report.embedding_candidate_entries >= 1
	anchors := build_memory_segment_anchors(candidates, mut engine, 0) or { panic(err) }
	assert anchors.len == 1
	assert anchors[0].segment_kind == 'root_cause'
	assert anchors[0].segment_horizon == 'durable'
	assert anchors[0].primary_key.bytestr() == 'session-segment-003:2'
}

fn test_memory_segment_evidence_filters_mixed_topic_neighbors() {
	seed := MemorySegmentEntry{
		primary_key: 'seed'.bytes()
		session_id:  'session-purity-001'
		timestamp:   '2026-04-01T10:00:01Z'
		score:       80
		entry:       SessionEntry{
			seq:  0
			role: 'assistant'
			kind: .message
			text: '`borrowed` 这条线更可疑，因为 `NextHandler` 是 `memdup` 出来的裸 V 内存。'
		}
		vector:      [f32(1.0), 0.0]
	}
	same_topic := MemorySegmentEntry{
		primary_key: 'same'.bytes()
		session_id:  'session-purity-001'
		timestamp:   '2026-04-01T10:00:02Z'
		score:       70
		entry:       SessionEntry{
			seq:  1
			role: 'assistant'
			kind: .message
			text: '`NextHandler` wrapper 不能重复接管 `borrowed` 指针。'
		}
		vector:      [f32(0.98), 0.02]
	}
	mixed_topic := MemorySegmentEntry{
		primary_key: 'mixed'.bytes()
		session_id:  'session-purity-001'
		timestamp:   '2026-04-01T10:00:03Z'
		score:       70
		entry:       SessionEntry{
			seq:  2
			role: 'assistant'
			kind: .message
			text: '`make ext` 失败是已知编译环境问题，它少了 `mysql.h` include。'
		}
		vector:      [f32(0.62), 0.78]
	}
	anchor := MemorySegmentAnchor{
		primary_key: seed.primary_key.clone()
		session_id:  seed.session_id
		timestamp:   mixed_topic.timestamp
		score:       seed.score
		entries:     [seed, same_topic, mixed_topic]
	}
	evidence := memory_segment_evidence(anchor, seed, 8)
	assert evidence.len == 1
	assert evidence[0].primary_key.bytestr() == 'same'
	assert !evidence[0].text.contains('mysql.h')
}

fn test_pollydb_store_sync_updates_only_changed_entries() {
	fixture_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	codex_root := os.join_path(os.vtmp_dir(), 'agentview-codex-entry-state')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-entry-state')
	os.rmdir_all(codex_root) or {}
	os.rmdir_all(store_root) or {}
	os.cp_all(fixture_root, codex_root, true) or { panic(err) }
	store := PollyDbStore.open(store_root) or { panic(err) }
	first := store.sync_codex(codex_root) or { panic(err) }
	assert first.sessions == 1
	assert first.entries == 5

	session_path := os.join_path(codex_root, 'sessions', '2026', '04', '01',
		'rollout-2026-04-01T10-00-00-session-001.jsonl')
	mut content := os.read_file(session_path) or { panic(err) }
	content = content.replace('I will inspect the patch.', 'I inspected the patch carefully.')
	os.write_file(session_path, content) or { panic(err) }

	second := store.sync_codex(codex_root) or { panic(err) }
	assert second.sessions == 1
	assert second.entries == 1
	assert second.skipped == 0

	transcript := store.load_session('session-001') or { panic(err) }
	assert transcript.entries.len == 5
	assert transcript.entries[1].text == 'I inspected the patch carefully.'

	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	entry_rows := session.scan_table(mut db, 'entries', 0) or { panic(err) }
	entry_state_rows := session.scan_table(mut db, 'entry_ingest_state', 0) or { panic(err) }
	entry_search_rows := session.scan_table(mut db, 'entry_search_state', 0) or { panic(err) }
	assert entry_rows.len == 5
	assert entry_state_rows.len == 5
	assert entry_search_rows.len == 0
}

fn test_pollydb_store_sync_codex_checkpoints_small_batches() {
	codex_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-batched-sync')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	stats := store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{
		batch_sessions: 1
	}, no_sync_progress, storage.ChunkConfig.default()) or { panic(err) }
	assert stats.sessions == 1
	assert stats.entries == 5

	sessions := store.list_sessions(10) or { panic(err) }
	assert sessions.len == 1
	assert sessions[0].id == 'session-001'

	transcript := store.load_session('session-001') or { panic(err) }
	assert transcript.entries.len == 5
	assert transcript.entries[0].seq == 0
}

fn test_pollydb_store_sync_codex_resume_state_across_batches() {
	codex_root := os.join_path(os.vtmp_dir(), 'agentview-codex-resume-fixture')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-resume-state')
	make_multi_session_codex_fixture(codex_root)
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }

	first := store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{
		batch_sessions: 1
	}, no_sync_progress, storage.ChunkConfig.default()) or { panic(err) }
	assert first.sessions == 1
	assert first.entries == 5
	assert first.skipped == 0
	assert first.paused_for_resume
	assert first.processed_sessions == 1
	assert first.total_sessions == 2
	assert first.resume_session_id == 'session-002'

	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	mut resume := load_sync_resume_state(mut db, 'codex_sync') or { panic(err) }
	db.close() or { panic(err) }
	assert resume.last_completed_session_id == 'session-002'
	assert resume.last_completed_path.contains('session-002')

	sessions_after_first := store.list_sessions(10) or { panic(err) }
	assert sessions_after_first.len == 1
	assert sessions_after_first[0].id == 'session-002'

	second := store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{
		batch_sessions: 1
	}, no_sync_progress, storage.ChunkConfig.default()) or { panic(err) }
	assert second.sessions == 1
	assert second.entries == 5
	assert second.paused_for_resume
	assert second.processed_sessions == 2
	assert second.total_sessions == 2
	assert second.resume_session_id == 'session-001'
	db = storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	resume = load_sync_resume_state(mut db, 'codex_sync') or { panic(err) }
	db.close() or { panic(err) }
	assert resume.last_completed_session_id == 'session-001'
	assert resume.last_completed_path.contains('session-001')

	sessions_after_second := store.list_sessions(10) or { panic(err) }
	assert sessions_after_second.len == 2
	assert sessions_after_second[0].id == 'session-002'
	assert sessions_after_second[1].id == 'session-001'

	third := store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{
		batch_sessions: 1
	}, no_sync_progress, storage.ChunkConfig.default()) or { panic(err) }
	assert third.sessions == 0
	assert third.entries == 0
	assert third.skipped == 2
	assert !third.paused_for_resume
	assert third.processed_sessions == 2
	assert third.total_sessions == 2
	db = storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	resume = load_sync_resume_state(mut db, 'codex_sync') or { panic(err) }
	db.close() or { panic(err) }
	assert resume.name == ''
}

fn test_hierarchical_memory_context() {
	println("=== [DEBUG] Start test_hierarchical_memory_context")
	codex_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-hierarchical-memory-context')
	os.rmdir_all(store_root) or {}
	println("=== [DEBUG] store open")
	store := PollyDbStore.open(store_root) or { panic(err) }
	println("=== [DEBUG] sync_codex")
	_ = store.sync_codex(codex_root) or { panic(err) }
	println("=== [DEBUG] ensure_memory_schema")
	_ = store.ensure_memory_schema() or { panic(err) }

	// 1. 测试 L3 Persona 偏好管理
	println("=== [DEBUG] list_personas 1")
	mut list := store.list_personas() or { panic(err) }
	assert list.len == 0

	println("=== [DEBUG] add_persona 1")
	p1 := store.add_persona('Prefer KISS style code') or { panic(err) }
	println("=== [DEBUG] add_persona 2")
	p2 := store.add_persona('Do not use Tailwind CSS') or { panic(err) }
	println("=== [DEBUG] list_personas 2")
	list = store.list_personas() or { panic(err) }
	assert list.len == 2
	
	mut has_p1 := false
	mut has_tailwind_pref := false
	for p in list {
		if p.persona_id == p1.persona_id {
			has_p1 = true
		}
		if p.content == 'Do not use Tailwind CSS' {
			has_tailwind_pref = true
		}
	}
	assert has_p1
	assert has_tailwind_pref

	println("=== [DEBUG] delete_persona")
	store.delete_persona(p2.persona_id) or { panic(err) }
	println("=== [DEBUG] list_personas 3")
	list = store.list_personas() or { panic(err) }
	assert list.len == 1
	assert list[0].persona_id == p1.persona_id

	// 2. 测试 L1/L2 保存与匹配
	// 写入一个 L1 Memory Card
	println("=== [DEBUG] save_memory")
	store.save_memory(memory.PersistedReflection{
		reflection_id: 'ref_001'
		reflection_kind: 'fact'
		title: 'Use vjsx import'
		summary_md: 'We decided to use import guweigang.vjsx'
		insight_md: 'Some evidence text'
		topic_key: 'vjsx'
		supersedes_reflection_id: ''
		created_at: storage.current_datetime_string()
	}) or { panic(err) }

	// 保存一个 L2 Scene Block
	println("=== [DEBUG] save_scene")
	store.save_scene(memory.SceneBlock{
		scene_id: 'scene_001'
		repo: 'pollytree'
		cwd: '/users/work/pollytree'
		topic: 'vjsx_development'
		workflow: 'refactoring'
		time_start: storage.current_datetime_string()
		time_end: storage.current_datetime_string()
		atomic_memory_ids: ['ref_001']
		metadata_json: ''
		created_at: storage.current_datetime_string()
		updated_at: storage.current_datetime_string()
	}) or { panic(err) }

	// 3. 测试三阶段 Context 装配 (MemoryContextRequest)
	// 用已匹配 CWD 访问
	println("=== [DEBUG] memory_context 1")
	context1 := store.memory_context(MemoryContextRequest{
		query: 'vjsx'
		cwd: '/users/work/pollytree'
		repo: 'pollytree'
		limit: 5
	}) or { panic(err) }
	
	// 期望 markdown 里包含 CWD/Repo 场景标题、L1 卡片信息、L3 Persona 习惯
	assert context1.markdown.contains('pollytree')
	assert context1.markdown.contains('We decided to use import guweigang.vjsx')
	assert context1.markdown.contains('Prefer KISS style code')

	// 用未匹配的 CWD/Repo 访问，不匹配 L2，但叠加 L3 Persona
	context2 := store.memory_context(MemoryContextRequest{
		query: 'unrelated'
		cwd: '/users/work/other'
		repo: 'other'
		limit: 5
	}) or { panic(err) }
	assert !context2.markdown.contains('pollytree')
	assert context2.markdown.contains('Prefer KISS style code')
}
