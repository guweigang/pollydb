module agentview

import crypto.sha256
import encoding.base64
import math
import memory
import os
import query as queryapi
import storage
import time

const store_branch = 'main'
const session_list_min_updated_at = '0001-01-01T00:00:00.000000Z'
const session_list_max_updated_at = '9999-12-31T23:59:59.999999Z'
const search_index_version = 'search-v7-content-text-fts'
const agentview_memory_capability_table = 'entries'
const agentview_memory_capability_column = 'content_md'
const agentview_memory_path_index = 'entries_content_path_vec_idx'
const agentview_memory_reflections_title_fts_index = 'memory_reflections_title_fts_idx'
const agentview_memory_reflections_summary_fts_index = 'memory_reflections_summary_fts_idx'
const agentview_general_fts_indexes = ['entries_content_text_fts_idx']
const session_summary_select_columns = ['id', 'title', 'updated_at', 'started_at', 'cwd', 'source',
	'originator', 'cli_version', 'path', 'archived', 'entry_count', 'user_turns', 'tool_calls']
const transcript_entry_select_columns = ['seq', 'timestamp', 'role', 'kind', 'tool_name', 'call_id',
	'title', 'content_text', 'content_md', 'raw_type', 'phase']

pub struct PollyDbStore {
pub:
	root_dir string
}

fn memory_distill_progress_enabled() bool {
	return os.getenv('POLLYDB_MEMORY_PROGRESS') == '1'
}

fn memory_distill_progress(message string) {
	if memory_distill_progress_enabled() {
		eprintln('agentview memory: ${message}')
	}
}

pub struct BrowserStoreSession {
mut:
	db      storage.PersistentDatabase
	session storage.DatabaseSession
}

pub struct MemoryDistillOptions {
pub:
	recent_sessions  int = 12
	max_jobs         int = 4
	neighbor_limit   int = 8
	min_evidence     int = 1
	candidate_limit  int
	candidate_offset int
}

pub struct MemoryDistillPreviewCard {
pub:
	source_key     string
	title          string
	topic_key      string
	summary_md     string
	insight_md     string
	decision       MemoryCardWriteDecision
	write_plan     MemoryWritePlan
	evidence_count int
	supersedes_id  string
}

pub struct MemoryReasoningTrace {
pub:
	evidence_count           int
	candidate_title          string
	candidate_summary_points []string
	durable_points           int
	signals                  []string
	blockers                 []string
	inference                string
	confidence               string
}

pub struct MemoryWritePlan {
pub:
	action        string
	reason        string
	score         int
	topic_key     string
	supersedes_id string
	trace         MemoryReasoningTrace
}

pub struct MemorySalienceReport {
pub mut:
	raw_entries                 int
	candidate_entries           int
	embedding_candidate_entries int
	skipped_by_reason           map[string]int
	discarded_before_embedding  map[string]int
	candidates_by_type          map[string]int
}

pub struct MemoryListRequest {
pub:
	query              string
	limit              int = 20
	offset             int
	include_superseded bool
}

pub struct MemoryCard {
pub:
	reflection_id            string
	reflection_kind          string
	title                    string
	summary_md               string
	insight_md               string
	topic_key                string
	derived_from_root_hash   string
	supersedes_reflection_id string
	created_at               string
	source_count             int
	active                   bool
	score                    int
}

pub struct MemoryListResult {
pub:
	total    int
	memories []MemoryCard
	strategy string
}

pub struct MemoryContextRequest {
pub:
	query           string
	limit           int = 6
	include_sources bool
}

pub struct MemoryContextResult {
pub:
	query    string
	memories []MemoryCard
	markdown string
}

pub struct MemoryDeleteResult {
pub:
	requested_ids        []string
	deleted_reflections  int
	deleted_links        int
	missing_ids          []string
}

struct MemorySalienceDecision {
	memory_worthy  bool
	candidate_type string
	skip_reason    string
	score          int
	claims         []MemoryClaim
}

struct MemoryClaim {
	text       string
	claim_type string
	score      int
}

struct MemoryCandidate {
	row        storage.TypedSchemaRow
	entry      SessionEntry
	decision   MemorySalienceDecision
	session_id string
}

struct MemoryCardWriteDecision {
pub:
	keep   bool
	reason string
	score  int
}

struct MemoryCardQualityProfile {
	title          string
	summary_points []string
mut:
	durable_points  int
	score           int
	overlap_score   int
	blocking_reason string
	title_reason    string
}

pub fn PollyDbStore.open(root_dir string) !PollyDbStore {
	mut store := PollyDbStore{
		root_dir: normalize_root_dir(root_dir)
	}
	store.init_schema()!
	return store
}

pub fn PollyDbStore.open_existing(root_dir string) PollyDbStore {
	return PollyDbStore{
		root_dir: normalize_root_dir(root_dir)
	}
}

pub fn (store PollyDbStore) begin_browser_session() !BrowserStoreSession {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	return BrowserStoreSession{
		db:      db
		session: session
	}
}

pub fn (mut session BrowserStoreSession) close() ! {
	session.db.close()!
}

fn normalize_root_dir(path string) string {
	if path.len == 0 {
		return path
	}
	return if os.exists(path) { os.real_path(path) } else { os.norm_path(path) }
}

fn (store PollyDbStore) init_schema() ! {
	if !os.exists(store.root_dir) {
		os.mkdir_all(store.root_dir)!
	}
	status := storage.PersistentDatabase.inspect(store.root_dir, store_branch) or {
		storage.PersistentDatabaseStatusReport{}
	}
	mut db := if status.repository_exists || status.catalog_exists {
		storage.PersistentDatabase.open(store.root_dir, store_branch)!
	} else {
		storage.PersistentDatabase.init(store.root_dir, store_branch)!
	}
	defer {
		db.close() or {}
	}
	mut changed_tables := []string{}
	if db.register_or_update_table(sessions_spec()!)! {
		changed_tables << 'sessions'
	}
	if db.register_or_update_table(ingest_state_spec()!)! {
		changed_tables << 'ingest_state'
	}
	if db.register_or_update_table(search_state_spec()!)! {
		changed_tables << 'search_state'
	}
	if db.register_or_update_table(search_meta_state_spec()!)! {
		changed_tables << 'search_meta_state'
	}
	if db.register_or_update_table(sync_resume_state_spec()!)! {
		changed_tables << 'sync_resume_state'
	}
	if db.register_or_update_table(entry_ingest_state_spec()!)! {
		changed_tables << 'entry_ingest_state'
	}
	if db.register_or_update_table(entry_search_state_spec()!)! {
		changed_tables << 'entry_search_state'
	}
	if db.register_or_update_table(entries_spec(false)!)! {
		changed_tables << 'entries'
	}
	if changed_tables.len > 0 && store_branch in db.branch_names() {
		_ = db.rebuild_indexes_at_branch(store_branch, changed_tables,
			storage.ChunkConfig.default())!
	}
	db.checkpoint()!
}

pub fn (store PollyDbStore) ensure_memory_schema() !bool {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	mut changed := db.register_or_update_table(entries_memory_spec(false)!)!
	changed = ensure_agentview_memory_capability(mut db)! || changed
	if changed {
		db.checkpoint()!
	}
	return changed
}

pub fn (store PollyDbStore) distill_recent_memory(mut embedding_engine memory.EmbeddingEngine, mut generator memory.ReflectionTextGenerator, options MemoryDistillOptions) ![]memory.PersistedReflection {
	return store.distill_recent_memory_with_mode(mut embedding_engine, mut generator, options,
		false)
}

pub fn (store PollyDbStore) distill_recent_memory_heuristic(mut embedding_engine memory.EmbeddingEngine, options MemoryDistillOptions) ![]memory.PersistedReflection {
	mut noop := AgentViewNoopReflectionGenerator{}
	return store.distill_recent_memory_with_mode(mut embedding_engine, mut noop, options, true)
}

pub fn (store PollyDbStore) preview_recent_memory_heuristic(mut embedding_engine memory.EmbeddingEngine, options MemoryDistillOptions) ![]MemoryDistillPreviewCard {
	mut noop := AgentViewNoopReflectionGenerator{}
	return store.preview_recent_memory_with_mode(mut embedding_engine, mut noop, options, true)
}

pub fn (store PollyDbStore) preview_recent_memory(mut embedding_engine memory.EmbeddingEngine, mut generator memory.ReflectionTextGenerator, options MemoryDistillOptions) ![]MemoryDistillPreviewCard {
	return store.preview_recent_memory_with_mode(mut embedding_engine, mut generator, options,
		false)
}

pub fn (store PollyDbStore) list_memory(request MemoryListRequest) !MemoryListResult {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	if !db.has_table('memory_reflections') {
		return MemoryListResult{
			strategy: 'no_memory_table'
		}
	}
	all_rows := session.scan_table(mut db, 'memory_reflections', 0)!
	superseded := superseded_memory_reflection_ids(all_rows)
	mut candidate_rows :=
		memory_list_candidate_rows(mut db, session, all_rows, superseded, request)!
	terms := normalized_search_terms(request.query)
	mut cards := []MemoryCard{cap: candidate_rows.len}
	for row in candidate_rows {
		card := memory_card_from_row(mut db, row, superseded, terms)!
		if request.query.len > 0 && card.score <= 0 {
			continue
		}
		if !request.include_superseded && !card.active {
			continue
		}
		if terms.len > 0 && request.query.len > 0 && card.score <= 0 {
			continue
		}
		cards << card
	}
	if request.query.len > 0 {
		cards.sort_with_compare(fn (a &MemoryCard, b &MemoryCard) int {
			if a.score > b.score {
				return -1
			}
			if a.score < b.score {
				return 1
			}
			if a.created_at > b.created_at {
				return -1
			}
			if a.created_at < b.created_at {
				return 1
			}
			return 0
		})
	} else {
		cards.sort_with_compare(fn (a &MemoryCard, b &MemoryCard) int {
			if a.created_at > b.created_at {
				return -1
			}
			if a.created_at < b.created_at {
				return 1
			}
			return 0
		})
	}
	total := cards.len
	start := clamp_offset(request.offset, total)
	limit := if request.limit > 0 { request.limit } else { 20 }
	end := min_int(start + limit, total)
	return MemoryListResult{
		total:    total
		memories: if start < end { cards[start..end].clone() } else { []MemoryCard{} }
		strategy: if request.query.len > 0 { 'memory_fts_or_scan' } else { 'memory_recent' }
	}
}

pub fn (store PollyDbStore) memory_context(request MemoryContextRequest) !MemoryContextResult {
	result := store.list_memory(MemoryListRequest{
		query:  request.query
		limit:  if request.limit > 0 { request.limit } else { 6 }
		offset: 0
	})!
	markdown := render_memory_context_markdown(request, result.memories)
	return MemoryContextResult{
		query:    request.query
		memories: result.memories
		markdown: markdown
	}
}

pub fn (store PollyDbStore) delete_memory(reflection_ids []string) !MemoryDeleteResult {
	mut normalized_ids := []string{}
	mut seen := map[string]bool{}
	for id in reflection_ids {
		trimmed := id.trim_space()
		if trimmed.len == 0 || trimmed in seen {
			continue
		}
		seen[trimmed] = true
		normalized_ids << trimmed
	}
	if normalized_ids.len == 0 {
		return error('memory delete requires at least one reflection id')
	}
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	if !db.has_table('memory_reflections') {
		return MemoryDeleteResult{
			requested_ids: normalized_ids
			missing_ids:   normalized_ids
		}
	}
	mut existing_ids := map[string]bool{}
	for id in normalized_ids {
		if _ := session.get_row(mut db, 'memory_reflections', id.bytes()) {
			existing_ids[id] = true
		}
	}
	mut reflection_keys := [][]u8{}
	mut missing := []string{}
	for id in normalized_ids {
		if id in existing_ids {
			reflection_keys << id.bytes()
		} else {
			missing << id
		}
	}
	mut link_keys := [][]u8{}
	if reflection_keys.len > 0 && db.has_table('memory_links') {
		link_rows := session.scan_table(mut db, 'memory_links', 0) or { []storage.TypedSchemaRow{} }
		for row in link_rows {
			from_table := agentview_optional_row_string(row, 'from_table_name')
			from_key_b64 := agentview_optional_row_string(row, 'from_primary_key_b64')
			if from_table == 'memory_reflections' && base64_key_matches_any_id(from_key_b64,
				existing_ids) {
				link_keys << row.primary_key.clone()
				continue
			}
			derived_from_root := agentview_optional_row_string(row, 'derived_from_root_hash')
			if derived_from_root.len > 0
				&& memory_link_root_matches_deleted_reflection(link_rows, derived_from_root,
				existing_ids)
				&& !memory_link_root_has_remaining_reflection(link_rows, derived_from_root,
				existing_ids) {
				link_keys << row.primary_key.clone()
			}
		}
	}
	if reflection_keys.len == 0 && link_keys.len == 0 {
		return MemoryDeleteResult{
			requested_ids: normalized_ids
			missing_ids:   missing
		}
	}
	mut writes := storage.TypedWriteSet.new()
	if reflection_keys.len > 0 {
		writes.delete_many('memory_reflections', reflection_keys)
	}
	if link_keys.len > 0 {
		writes.delete_many('memory_links', link_keys)
	}
	_ = session.apply_write_set(mut db, writes, storage.ChunkConfig.default(), storage.CommitMeta{
		author:  'agentview'
		message: 'delete agentview memory'
	})!
	return MemoryDeleteResult{
		requested_ids:       normalized_ids
		deleted_reflections: reflection_keys.len
		deleted_links:       link_keys.len
		missing_ids:         missing
	}
}

fn base64_key_matches_any_id(encoded string, ids map[string]bool) bool {
	if encoded.len == 0 {
		return false
	}
	key := base64.decode(encoded).bytestr()
	return key in ids
}

fn memory_link_root_matches_deleted_reflection(rows []storage.TypedSchemaRow, root string, ids map[string]bool) bool {
	for row in rows {
		if agentview_optional_row_string(row, 'derived_from_root_hash') != root {
			continue
		}
		if agentview_optional_row_string(row, 'from_table_name') != 'memory_reflections' {
			continue
		}
		if base64_key_matches_any_id(agentview_optional_row_string(row, 'from_primary_key_b64'),
			ids) {
			return true
		}
	}
	return false
}

fn memory_link_root_has_remaining_reflection(rows []storage.TypedSchemaRow, root string, ids map[string]bool) bool {
	for row in rows {
		if agentview_optional_row_string(row, 'derived_from_root_hash') != root {
			continue
		}
		if agentview_optional_row_string(row, 'from_table_name') != 'memory_reflections' {
			continue
		}
		if !base64_key_matches_any_id(agentview_optional_row_string(row, 'from_primary_key_b64'),
			ids) {
			return true
		}
	}
	return false
}

fn (store PollyDbStore) distill_recent_memory_with_mode(mut embedding_engine memory.EmbeddingEngine, mut generator memory.ReflectionTextGenerator, options MemoryDistillOptions, use_heuristic bool) ![]memory.PersistedReflection {
	_ = store.ensure_memory_schema()!
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	recent_sessions := if options.recent_sessions > 0 { options.recent_sessions } else { 12 }
	mut entry_rows := recent_entry_rows(mut db, session, recent_sessions)!
	memory_distill_progress('loaded recent sessions=${recent_sessions} entries=${entry_rows.len}')
	if entry_rows.len == 0 {
		return []memory.PersistedReflection{}
	}
	candidates, _ := memory_candidates_for_embedding(mut db, session, entry_rows,
		options.candidate_limit, options.candidate_offset)!
	memory_distill_progress('embedding candidates=${candidates.len}')
	if candidates.len == 0 {
		return []memory.PersistedReflection{}
	}
	mut segment_anchors := build_memory_segment_anchors(candidates, mut embedding_engine,
		options.candidate_limit) or { []MemorySegmentAnchor{} }
	memory_distill_progress('segment anchors=${segment_anchors.len}')
	if segment_anchors.len == 0 {
		return []memory.PersistedReflection{}
	}
	mut reflected_sources := db.reflected_source_keys(store_branch) or {
		map[string]bool{}
	}
	max_jobs := if options.max_jobs > 0 { options.max_jobs } else { 4 }
	neighbor_limit := if options.neighbor_limit > 0 { options.neighbor_limit } else { 8 }
	min_evidence := if options.min_evidence > 0 { options.min_evidence } else { 1 }
	mut persisted := []memory.PersistedReflection{}
	for anchor_idx, anchor in segment_anchors {
		primary_key := anchor.primary_key.clone()
		source_key := memory.reflection_source_key('entries', primary_key, 'content_md')
		if source_key in reflected_sources {
			memory_distill_progress('skip reflected anchor ${anchor_idx + 1}/${segment_anchors.len} key=${primary_key.bytestr()}')
			continue
		}
		memory_distill_progress('build reflection ${anchor_idx + 1}/${segment_anchors.len} key=${primary_key.bytestr()} persisted=${persisted.len}/${max_jobs}')
		job := build_in_memory_agentview_reflection_job(anchor, neighbor_limit)
		if job.evidence.len < min_evidence {
			memory_distill_progress('skip weak evidence key=${primary_key.bytestr()} evidence=${job.evidence.len}/${min_evidence}')
			continue
		}
		distill_options := memory.ReflectionDistillOptions{
			max_evidence: neighbor_limit
		}
		if !memory.reflection_job_has_distillable_outline(job, distill_options) {
			memory_distill_progress('skip empty reflection outline key=${primary_key.bytestr()}')
			reflected_sources[source_key] = true
			continue
		}
		memory_distill_progress('distill reflection card key=${primary_key.bytestr()} evidence=${job.evidence.len}')
		raw_input := if use_heuristic {
			memory.heuristic_reflection_persist_input(job, distill_options)
		} else {
			memory.generate_reflection_persist_input(job, mut generator, distill_options)!
		}
		card_topic_key := memory_card_topic_key(raw_input)
		mut input := memory.ReflectionPersistInput{
			...raw_input
			topic_key: card_topic_key
		}
		memory_distill_progress('quality gate key=${primary_key.bytestr()} title=${input.title}')
		write_decision := memory_card_write_decision(input)
		if !write_decision.keep {
			eprintln('agentview memory: discard reflection card for ${primary_key.bytestr()}: ${write_decision.reason}')
			reflected_sources[source_key] = true
			continue
		}
		memory_distill_progress('dedupe reflection key=${primary_key.bytestr()} topic=${input.topic_key}')
		if existing_reflection_id := find_existing_reflection_for_memory_card(mut db, session,
			input, mut embedding_engine)
		{
			input = memory.ReflectionPersistInput{
				...input
				supersedes_reflection_id: existing_reflection_id
			}
		}
		memory_distill_progress('persist reflection key=${primary_key.bytestr()} sources=${job.evidence.len}')
		reflection := db.persist_prebuilt_reflection_job(job, input, storage.ChunkConfig.default(), storage.CommitMeta{
			author:  'pollydb-cli'
			message: 'distill agentview memory'
		}) or {
			eprintln('agentview memory: skip persisting reflection for ${primary_key.bytestr()}: ${err}')
			continue
		}
		persisted << reflection
		memory_distill_progress('persisted reflection ${persisted.len}/${max_jobs} id=${reflection.reflection_id} title=${reflection.title}')
		reflected_sources[source_key] = true
		if persisted.len >= max_jobs {
			break
		}
	}
	return persisted
}

fn (store PollyDbStore) preview_recent_memory_with_mode(mut embedding_engine memory.EmbeddingEngine, mut generator memory.ReflectionTextGenerator, options MemoryDistillOptions, use_heuristic bool) ![]MemoryDistillPreviewCard {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	recent_sessions := if options.recent_sessions > 0 { options.recent_sessions } else { 12 }
	mut entry_rows := recent_entry_rows(mut db, session, recent_sessions)!
	memory_distill_progress('loaded recent sessions=${recent_sessions} entries=${entry_rows.len}')
	if entry_rows.len == 0 {
		return []MemoryDistillPreviewCard{}
	}
	candidates, _ := memory_candidates_for_embedding(mut db, session, entry_rows,
		options.candidate_limit, options.candidate_offset)!
	memory_distill_progress('embedding candidates=${candidates.len}')
	if candidates.len == 0 {
		return []MemoryDistillPreviewCard{}
	}
	mut segment_anchors := build_memory_segment_anchors(candidates, mut embedding_engine,
		options.candidate_limit) or { []MemorySegmentAnchor{} }
	memory_distill_progress('segment anchors=${segment_anchors.len}')
	if segment_anchors.len == 0 {
		return []MemoryDistillPreviewCard{}
	}
	reflected_sources := db.reflected_source_keys(store_branch) or {
		map[string]bool{}
	}
	max_jobs := if options.max_jobs > 0 { options.max_jobs } else { 4 }
	neighbor_limit := if options.neighbor_limit > 0 { options.neighbor_limit } else { 8 }
	min_evidence := if options.min_evidence > 0 { options.min_evidence } else { 1 }
	mut previews := []MemoryDistillPreviewCard{}
	for anchor_idx, anchor in segment_anchors {
		primary_key := anchor.primary_key.clone()
		source_key := memory.reflection_source_key('entries', primary_key, 'content_md')
		if source_key in reflected_sources {
			memory_distill_progress('skip reflected anchor ${anchor_idx + 1}/${segment_anchors.len} key=${primary_key.bytestr()}')
			continue
		}
		memory_distill_progress('preview reflection ${anchor_idx + 1}/${segment_anchors.len} key=${primary_key.bytestr()} cards=${previews.len}/${max_jobs}')
		job := build_in_memory_agentview_reflection_job(anchor, neighbor_limit)
		if job.evidence.len < min_evidence {
			continue
		}
		distill_options := memory.ReflectionDistillOptions{
			max_evidence: neighbor_limit
		}
		if !memory.reflection_job_has_distillable_outline(job, distill_options) {
			memory_distill_progress('skip empty preview outline key=${primary_key.bytestr()}')
			continue
		}
		raw_input := if use_heuristic {
			memory.heuristic_reflection_persist_input(job, distill_options)
		} else {
			memory.generate_reflection_persist_input(job, mut generator, distill_options)!
		}
		card_topic_key := memory_card_topic_key(raw_input)
		mut input := memory.ReflectionPersistInput{
			...raw_input
			topic_key: card_topic_key
		}
		profile := memory_card_quality_profile(input)
		decision := memory_card_write_decision_from_profile(profile)
		mut supersedes_id := ''
		if decision.keep {
			if existing_reflection_id := find_existing_reflection_for_memory_card(mut db, session,
				input, mut embedding_engine)
			{
				supersedes_id = existing_reflection_id
			}
		}
		write_plan := memory_card_write_plan(input, profile, decision, job.evidence.len,
			supersedes_id)
		previews << MemoryDistillPreviewCard{
			source_key:     source_key
			title:          input.title
			topic_key:      input.topic_key
			summary_md:     input.summary_md
			insight_md:     input.insight_md
			decision:       decision
			write_plan:     write_plan
			evidence_count: job.evidence.len
			supersedes_id:  supersedes_id
		}
		if previews.len >= max_jobs {
			break
		}
	}
	return previews
}

struct MemoryCardMatch {
	reflection_id string
	vector_score  f64
	lexical_score f64
}

fn find_existing_reflection_for_memory_card(mut db storage.PersistentDatabase, session storage.DatabaseSession, input memory.ReflectionPersistInput, mut embedding_engine memory.EmbeddingEngine) ?string {
	if !db.has_table('memory_reflections') {
		return none
	}
	if input.topic_key.len > 0 {
		rows := session.lookup_index_projected(mut db, 'memory_reflections', 'topic_key_idx',
			input.topic_key, 1, ['reflection_id']) or { []storage.TypedSchemaRow{} }
		if rows.len > 0 {
			reflection_id := agentview_optional_row_string(rows[0], 'reflection_id')
			if reflection_id.len > 0 {
				return reflection_id
			}
		}
	}
	if best := best_existing_reflection_match(mut db, session, input, mut embedding_engine) {
		if best.vector_score >= 0.75 && best.lexical_score >= 0.18 {
			return best.reflection_id
		}
	}
	return none
}

fn best_existing_reflection_match(mut db storage.PersistentDatabase, session storage.DatabaseSession, input memory.ReflectionPersistInput, mut embedding_engine memory.EmbeddingEngine) ?MemoryCardMatch {
	rows := memory_reflection_match_candidate_rows(mut db, session, input) or { return none }
	if rows.len == 0 {
		return none
	}
	new_text := memory_card_match_text(input.title, input.summary_md)
	if new_text.len == 0 {
		return none
	}
	new_vec := embedding_engine.embed(new_text) or { []f32{} }
	mut best := MemoryCardMatch{}
	for row in rows {
		reflection_id := agentview_optional_row_string(row, 'reflection_id')
		if reflection_id.len == 0 {
			continue
		}
		title := agentview_optional_row_string(row, 'title')
		summary_md := load_memory_reflection_summary(mut db, row) or { '' }
		old_text := memory_card_match_text(title, summary_md)
		if old_text.len == 0 {
			continue
		}
		old_vec := if new_vec.len > 0 {
			embedding_engine.embed(old_text) or { []f32{} }
		} else {
			[]f32{}
		}
		vector_score := cosine_similarity(new_vec, old_vec)
		lexical_score := memory_card_lexical_guard_score(input.title, input.summary_md, title,
			summary_md)
		if vector_score > best.vector_score {
			best = MemoryCardMatch{
				reflection_id: reflection_id
				vector_score:  vector_score
				lexical_score: lexical_score
			}
		}
	}
	return if best.reflection_id.len > 0 { best } else { none }
}

fn memory_reflection_match_candidate_rows(mut db storage.PersistentDatabase, session storage.DatabaseSession, input memory.ReflectionPersistInput) ![]storage.TypedSchemaRow {
	all_rows := session.scan_table(mut db, 'memory_reflections', 0)!
	if all_rows.len == 0 {
		return []storage.TypedSchemaRow{}
	}
	active_rows := active_memory_reflection_rows(all_rows)
	mut active_by_id := map[string]storage.TypedSchemaRow{}
	for row in active_rows {
		reflection_id := agentview_optional_row_string(row, 'reflection_id')
		if reflection_id.len > 0 {
			active_by_id[reflection_id] = row
		}
	}
	mut candidates := map[string]storage.TypedSchemaRow{}
	spec := session.table_spec('memory_reflections') or { storage.TypedTableSpec{} }
	if table_has_index(spec, agentview_memory_reflections_title_fts_index)
		|| table_has_index(spec, agentview_memory_reflections_summary_fts_index) {
		for term in memory_card_match_terms(input.title, input.summary_md) {
			for index_name in [agentview_memory_reflections_title_fts_index,
				agentview_memory_reflections_summary_fts_index] {
				if !table_has_index(spec, index_name) {
					continue
				}
				rows := session.lookup_index_prefix_projected(mut db, 'memory_reflections',
					index_name, term, 12, ['reflection_id', 'title', 'summary_md',
					'supersedes_reflection_id']) or { []storage.TypedSchemaRow{} }
				for row in rows {
					reflection_id := agentview_optional_row_string(row, 'reflection_id')
					if reflection_id.len == 0 || reflection_id !in active_by_id {
						continue
					}
					candidates[reflection_id] = active_by_id[reflection_id]
				}
			}
		}
	}
	if candidates.len == 0 {
		return active_rows
	}
	mut out := []storage.TypedSchemaRow{}
	for _, row in candidates {
		out << row
	}
	return out
}

fn active_memory_reflection_rows(rows []storage.TypedSchemaRow) []storage.TypedSchemaRow {
	mut superseded := map[string]bool{}
	for row in rows {
		old_id := agentview_optional_row_string(row, 'supersedes_reflection_id')
		if old_id.len > 0 {
			superseded[old_id] = true
		}
	}
	mut active := []storage.TypedSchemaRow{}
	for row in rows {
		reflection_id := agentview_optional_row_string(row, 'reflection_id')
		if reflection_id.len == 0 || reflection_id in superseded {
			continue
		}
		active << row
	}
	return active
}

fn superseded_memory_reflection_ids(rows []storage.TypedSchemaRow) map[string]bool {
	mut superseded := map[string]bool{}
	for row in rows {
		old_id := agentview_optional_row_string(row, 'supersedes_reflection_id')
		if old_id.len > 0 {
			superseded[old_id] = true
		}
	}
	return superseded
}

fn memory_list_candidate_rows(mut db storage.PersistentDatabase, session storage.DatabaseSession, all_rows []storage.TypedSchemaRow, superseded map[string]bool, request MemoryListRequest) ![]storage.TypedSchemaRow {
	if request.query.trim_space().len == 0 {
		return all_rows
	}
	spec := session.table_spec('memory_reflections') or { storage.TypedTableSpec{} }
	mut candidates := map[string]storage.TypedSchemaRow{}
	if table_has_index(spec, agentview_memory_reflections_title_fts_index)
		|| table_has_index(spec, agentview_memory_reflections_summary_fts_index) {
		for term in normalized_search_terms(request.query) {
			for index_name in [agentview_memory_reflections_title_fts_index,
				agentview_memory_reflections_summary_fts_index] {
				if !table_has_index(spec, index_name) {
					continue
				}
				rows := session.lookup_index_prefix_projected(mut db, 'memory_reflections',
					index_name, term, 32, ['reflection_id', 'reflection_kind', 'title', 'summary_md',
					'insight_md', 'source_refs', 'parent_ref', 'topic_key', 'derived_from_root_hash',
					'supersedes_reflection_id', 'created_at']) or { []storage.TypedSchemaRow{} }
				for row in rows {
					reflection_id := agentview_optional_row_string(row, 'reflection_id')
					if reflection_id.len == 0 {
						continue
					}
					if !request.include_superseded && reflection_id in superseded {
						continue
					}
					candidates[reflection_id] = row
				}
			}
		}
	}
	if candidates.len == 0 {
		return all_rows
	}
	mut out := []storage.TypedSchemaRow{cap: candidates.len}
	for _, row in candidates {
		out << row
	}
	return out
}

fn memory_card_from_row(mut db storage.PersistentDatabase, row storage.TypedSchemaRow, superseded map[string]bool, terms []string) !MemoryCard {
	reflection_id := agentview_optional_row_string(row, 'reflection_id')
	summary_md := load_memory_reflection_summary(mut db, row) or { '' }
	insight_md := load_memory_reflection_markdown(mut db, row, 'insight_md') or { '' }
	title := agentview_optional_row_string(row, 'title')
	source_refs_raw := agentview_optional_row_string(row, 'source_refs')
	source_refs := memory.decode_reflection_source_refs(source_refs_raw) or {
		[]memory.ReflectionSourceRef{}
	}
	active := reflection_id.len > 0 && reflection_id !in superseded
	score := score_memory_card(title, summary_md, terms)
	return MemoryCard{
		reflection_id:            reflection_id
		reflection_kind:          agentview_optional_row_string(row, 'reflection_kind')
		title:                    title
		summary_md:               summary_md
		insight_md:               insight_md
		topic_key:                agentview_optional_row_string(row, 'topic_key')
		derived_from_root_hash:   agentview_optional_row_string(row, 'derived_from_root_hash')
		supersedes_reflection_id: agentview_optional_row_string(row, 'supersedes_reflection_id')
		created_at:               agentview_optional_row_string(row, 'created_at')
		source_count:             source_refs.len
		active:                   active
		score:                    score
	}
}

fn load_memory_reflection_summary(mut db storage.PersistentDatabase, row storage.TypedSchemaRow) !string {
	value := row.data.get('summary_md') or { return '' }
	return match value {
		storage.MarkdownRef { db.load_markdown(value)! }
		else { '' }
	}
}

fn load_memory_reflection_markdown(mut db storage.PersistentDatabase, row storage.TypedSchemaRow, column string) !string {
	value := row.data.get(column) or { return '' }
	return match value {
		storage.MarkdownRef { db.load_markdown(value)! }
		else { '' }
	}
}

fn score_memory_card(title string, summary_md string, terms []string) int {
	if terms.len == 0 {
		return 0
	}
	haystack := '${title}\n${summary_md}'.to_lower()
	mut score := 0
	for term in terms {
		lower := term.to_lower()
		if lower.len == 0 {
			continue
		}
		if title.to_lower().contains(lower) {
			score += 8
		}
		if haystack.contains(lower) {
			score += 3
		}
	}
	return score
}

fn render_memory_context_markdown(request MemoryContextRequest, memories []MemoryCard) string {
	mut lines := []string{}
	lines << '# Agent Memory Context'
	if request.query.len > 0 {
		lines << ''
		lines << 'Query: ${request.query}'
	}
	if memories.len == 0 {
		lines << ''
		lines << 'No matching distilled memory was found.'
		return lines.join('\n') + '\n'
	}
	for idx, card in memories {
		lines << ''
		lines << '## ${idx + 1}. ${card.title}'
		if card.summary_md.trim_space().len > 0 {
			lines << ''
			lines << card.summary_md.trim_space()
		}
		if request.include_sources {
			lines << ''
			lines << '- memory_id: `${card.reflection_id}`'
			if card.topic_key.len > 0 {
				lines << '- topic_key: `${card.topic_key}`'
			}
			lines << '- source_refs: ${card.source_count}'
			if card.derived_from_root_hash.len > 0 {
				lines << '- source_root: `${card.derived_from_root_hash}`'
			}
		}
	}
	return lines.join('\n') + '\n'
}

fn memory_card_write_decision(input memory.ReflectionPersistInput) MemoryCardWriteDecision {
	profile := memory_card_quality_profile(input)
	return memory_card_write_decision_from_profile(profile)
}

fn memory_card_write_decision_from_profile(profile MemoryCardQualityProfile) MemoryCardWriteDecision {
	if profile.title.len == 0 {
		return memory_card_discard_decision('empty_title', 0)
	}
	if profile.summary_points.len == 0 {
		return memory_card_discard_decision('empty_summary', 0)
	}
	if profile.title_reason.len > 0 {
		return memory_card_discard_decision(profile.title_reason, profile.score)
	}
	if profile.blocking_reason.len > 0 {
		return memory_card_discard_decision(profile.blocking_reason, profile.score)
	}
	if memory_card_title_code_terms_mismatch(profile) {
		return memory_card_discard_decision('title_summary_mismatch', profile.score)
	}
	if memory_card_requires_title_summary_overlap(profile) && profile.overlap_score == 0 {
		return memory_card_discard_decision('title_summary_mismatch', profile.score)
	}
	if profile.durable_points == 0 {
		return memory_card_discard_decision('no_durable_points', profile.score)
	}
	if memory_card_is_title_replay_only(profile) {
		return memory_card_discard_decision('title_replay_only', profile.score)
	}
	if profile.score < 3 {
		return memory_card_discard_decision('low_card_value', profile.score)
	}
	return MemoryCardWriteDecision{
		keep:   true
		reason: 'keep'
		score:  profile.score
	}
}

fn memory_card_write_plan(input memory.ReflectionPersistInput, profile MemoryCardQualityProfile, decision MemoryCardWriteDecision, evidence_count int, supersedes_id string) MemoryWritePlan {
	mut action := 'discard'
	mut reason := decision.reason
	evidence_decision := memory_card_evidence_decision(profile, evidence_count, decision)
	if evidence_decision.keep {
		if supersedes_id.len > 0 {
			action = 'update'
			reason = 'similar_existing_memory'
		} else {
			action = 'add'
		}
	} else {
		reason = evidence_decision.reason
	}
	trace := memory_card_reasoning_trace(input, profile, evidence_decision, evidence_count,
		supersedes_id, action)
	return MemoryWritePlan{
		action:        action
		reason:        reason
		score:         evidence_decision.score
		topic_key:     input.topic_key
		supersedes_id: supersedes_id
		trace:         trace
	}
}

fn memory_card_evidence_decision(profile MemoryCardQualityProfile, evidence_count int, decision MemoryCardWriteDecision) MemoryCardWriteDecision {
	if evidence_count <= 1 && memory_card_is_weak_single_evidence(profile) {
		if decision.keep || decision.reason in ['process_title', 'bad_summary_point', 'low_card_value'] {
			return memory_card_discard_decision('weak_single_evidence', profile.score)
		}
	}
	if !decision.keep {
		return decision
	}
	return decision
}

fn memory_card_reasoning_trace(input memory.ReflectionPersistInput, profile MemoryCardQualityProfile, decision MemoryCardWriteDecision, evidence_count int, supersedes_id string, action string) MemoryReasoningTrace {
	mut signals := []string{}
	if evidence_count > 1 {
		signals << 'multi_evidence'
	} else if evidence_count == 1 {
		signals << 'single_evidence'
	}
	if profile.durable_points > 0 {
		signals << 'durable_points:${profile.durable_points}'
	}
	if profile.score >= 3 {
		signals << 'score_pass'
	}
	if input.topic_key.len > 0 {
		signals << 'topic_key'
	}
	if input.insight_md.trim_space().len > 0 {
		signals << 'has_insight'
	}
	if supersedes_id.len > 0 {
		signals << 'matched_existing_memory'
	}

	mut blockers := []string{}
	if profile.title.len == 0 {
		blockers << 'empty_title'
	}
	if profile.summary_points.len == 0 {
		blockers << 'empty_summary'
	}
	if profile.title_reason.len > 0 {
		blockers << profile.title_reason
	}
	if profile.blocking_reason.len > 0 {
		blockers << profile.blocking_reason
	}
	if profile.durable_points == 0 && profile.summary_points.len > 0 {
		blockers << 'no_durable_points'
	}
	if memory_card_is_title_replay_only(profile) {
		blockers << 'title_replay_only'
	}
	if memory_card_requires_title_summary_overlap(profile) && profile.overlap_score == 0 {
		blockers << 'title_summary_mismatch'
	}
	if memory_card_title_code_terms_mismatch(profile) {
		blockers << 'title_summary_mismatch'
	}
	if evidence_count <= 1 && memory_card_is_weak_single_evidence(profile) {
		blockers << 'weak_single_evidence'
	}
	if profile.score < 3 && decision.keep == false && decision.reason == 'low_card_value' {
		blockers << 'low_card_value'
	}

	inference := memory_card_plan_inference(action)
	confidence := memory_card_plan_confidence(profile.score, evidence_count, blockers.len)
	return MemoryReasoningTrace{
		evidence_count:           evidence_count
		candidate_title:          profile.title
		candidate_summary_points: profile.summary_points.clone()
		durable_points:           profile.durable_points
		signals:                  signals
		blockers:                 blockers
		inference:                inference
		confidence:               confidence
	}
}

fn memory_card_plan_inference(action string) string {
	if action == 'discard' {
		return 'candidate failed the durable-memory quality gate'
	}
	if action == 'update' {
		return 'candidate is durable and should revise a matching existing memory'
	}
	return 'candidate is durable and should become a new memory'
}

fn memory_card_plan_confidence(score int, evidence_count int, blocker_count int) string {
	if blocker_count > 0 {
		return 'high'
	}
	if score >= 5 && evidence_count > 1 {
		return 'high'
	}
	if score >= 3 {
		return 'medium'
	}
	return 'low'
}

fn memory_card_discard_decision(reason string, score int) MemoryCardWriteDecision {
	return MemoryCardWriteDecision{
		keep:   false
		reason: reason
		score:  score
	}
}

fn memory_card_quality_profile(input memory.ReflectionPersistInput) MemoryCardQualityProfile {
	title := input.title.trim_space()
	summary_points := memory_card_summary_points(input.summary_md)
	mut profile := MemoryCardQualityProfile{
		title:          title
		summary_points: summary_points
	}
	profile.title_reason = memory_card_title_blocking_reason(title)
	profile.overlap_score = memory_card_title_summary_overlap(title, summary_points)
	for point in summary_points {
		if reason := memory_card_point_blocking_reason(point) {
			profile.blocking_reason = reason
			return profile
		}
		if memory_card_point_is_discardable(point) {
			continue
		}
		profile.durable_points++
		profile.score += memory_card_point_score(point)
	}
	return profile
}

fn memory_card_title_blocking_reason(title string) string {
	if title.len == 0 {
		return ''
	}
	if memory_card_title_is_boilerplate(title) {
		return 'boilerplate_title'
	}
	if memory_looks_like_hypothesis_validation_for_card(title) {
		return 'hypothesis_validation_title'
	}
	if memory_looks_like_vague_resolution_title_for_card(title) {
		return 'vague_title'
	}
	if memory_looks_like_context_dependent_short_note_for_card(title) {
		return 'vague_title'
	}
	if memory_looks_like_process_or_debug_card_title(title) {
		return 'process_title'
	}
	if memory_looks_like_unresolved_question_for_card(title) {
		return 'question_title'
	}
	if memory_looks_like_future_action_process_for_card(title) {
		return 'process_title'
	}
	if memory_looks_like_corrupt_or_truncated_fragment_for_card(title) {
		return 'corrupt_title'
	}
	return ''
}

fn memory_card_point_blocking_reason(point string) ?string {
	cleaned := point.trim_space()
	if memory_card_point_has_blocking_noise(cleaned) {
		return 'bad_summary_point'
	}
	return none
}

fn memory_card_is_title_replay_only(profile MemoryCardQualityProfile) bool {
	if profile.durable_points != 1 {
		return false
	}
	title_key := memory_card_canonical_text(profile.title)
	for point in profile.summary_points {
		if memory_card_point_is_discardable(point) {
			continue
		}
		if memory_card_single_replay_is_strong(profile, point) {
			return false
		}
		return memory_card_canonical_text(point) == title_key
	}
	return false
}

fn memory_card_single_replay_is_strong(profile MemoryCardQualityProfile, point string) bool {
	if profile.score < 6 {
		return false
	}
	return reflection_like_durable_artifact(point)
		&& (memory_looks_like_decision_text(point) || memory_looks_like_unresolved_issue_text(point)
		|| memory_looks_like_constraint_text(point))
}

fn memory_card_is_weak_single_evidence(profile MemoryCardQualityProfile) bool {
	if memory_card_has_explicit_constraint(profile) && profile.overlap_score > 0 {
		return false
	}
	if profile.score >= 14 && profile.durable_points >= 2 && profile.overlap_score > 0 {
		return false
	}
	if profile.durable_points < 2 {
		return true
	}
	if memory_looks_like_process_or_debug_card_title(profile.title) {
		return true
	}
	for point in profile.summary_points {
		if memory_looks_like_process_or_debug_card_point(point) {
			return true
		}
	}
	return profile.score < 10
}

fn memory_card_has_explicit_constraint(profile MemoryCardQualityProfile) bool {
	if memory_looks_like_constraint_text(profile.title) {
		return true
	}
	for point in profile.summary_points {
		if memory_looks_like_constraint_text(point) {
			return true
		}
	}
	return false
}

fn memory_card_title_summary_overlap(title string, points []string) int {
	title_terms := memory_card_salient_terms(title)
	if title_terms.len == 0 {
		return 0
	}
	mut point_terms := map[string]bool{}
	for point in points {
		for term in memory_card_salient_terms(point) {
			point_terms[term] = true
		}
	}
	mut overlap := 0
	for term in title_terms {
		if term in point_terms {
			overlap++
		}
	}
	return overlap
}

fn memory_card_title_code_terms_mismatch(profile MemoryCardQualityProfile) bool {
	title_terms := memory_card_inline_code_terms(profile.title)
	if title_terms.len == 0 {
		return false
	}
	mut summary_terms := map[string]bool{}
	for point in profile.summary_points {
		for term in memory_card_inline_code_terms(point) {
			summary_terms[term] = true
		}
	}
	for term in title_terms {
		if memory_card_code_term_requires_exact_overlap(term) && term !in summary_terms {
			return true
		}
	}
	return false
}

fn memory_card_code_term_requires_exact_overlap(term string) bool {
	return term.contains('()') || term.contains('fn') || term.contains('method')
		|| term.runes().len >= 12
}

fn memory_card_requires_title_summary_overlap(profile MemoryCardQualityProfile) bool {
	if reflection_like_durable_artifact(profile.title) {
		return true
	}
	if profile.title.contains('`') || profile.title.contains('/') || profile.title.contains('(')
		|| profile.title.contains(')') {
		return true
	}
	return false
}

fn memory_card_salient_terms(text string) []string {
	mut out := []string{}
	mut seen := map[string]bool{}
	for token in memory_card_inline_code_terms(text) {
		seen[token] = true
		out << token
	}
	mut normalized := text.replace('`', ' ').replace('[', ' ').replace(']', ' ')
	normalized = normalized.replace('(', ' ').replace(')', ' ').replace('/', ' ')
	normalized = normalized.replace('：', ' ').replace(':', ' ').replace('，', ' ')
	normalized = normalized.replace('。', ' ').replace(',', ' ').replace('.', ' ')
	normalized = normalized.replace('-', ' ').replace('_', ' ')
	for raw in normalized.split(' ') {
		term := memory_card_canonical_text(raw)
		if term.runes().len < 3 {
			continue
		}
		if term in ['摘要', '关键决策', '重要约束', '后续关注', '当前主题'] {
			continue
		}
		if term !in seen {
			seen[term] = true
			out << term
		}
	}
	return out
}

fn memory_card_inline_code_terms(text string) []string {
	parts := text.split('`')
	if parts.len < 3 {
		return []string{}
	}
	mut out := []string{}
	mut idx := 1
	for idx < parts.len {
		term := memory_card_canonical_text(parts[idx])
		if term.runes().len >= 3 {
			out << term
		}
		idx += 2
	}
	return out
}

fn memory_card_summary_points(summary_md string) []string {
	mut points := []string{}
	for line in summary_md.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('- ') || trimmed.starts_with('* ') {
			points << trimmed[2..].trim_space()
		}
	}
	return points
}

fn memory_card_title_is_boilerplate(title string) bool {
	key := memory_card_canonical_text(title)
	if key.len == 0 {
		return true
	}
	for marker in ['未命名记忆复盘', '记忆复盘',
		'当前主题已从seed与近邻证据中完成一次可回放蒸馏',
		'后续查询应优先命中这条主题标题'] {
		if key.contains(memory_card_canonical_text(marker)) {
			return true
		}
	}
	return false
}

fn memory_card_point_is_discardable(point string) bool {
	cleaned := point.trim_space()
	if cleaned.len == 0 {
		return true
	}
	key := memory_card_canonical_text(cleaned)
	for marker in [
		'当前主题已从seed与近邻证据中完成一次可回放蒸馏',
		'后续查询应优先命中这条主题标题',
		'保留这次复盘的证据链',
		'回到原始证据',
		'适合先累计更多同类entry',
		'这条反思必须保留source_refs',
	] {
		if key.contains(memory_card_canonical_text(marker)) {
			return true
		}
	}
	return memory_looks_like_shell_prompt(cleaned) || memory_looks_like_raw_log(cleaned)
		|| memory_looks_like_context_dependent_short_note_for_card(cleaned)
		|| memory_looks_like_ascii_label_for_card(cleaned)
		|| memory_looks_like_isolated_artifact_for_card(cleaned)
		|| memory_looks_like_transient_card_point(cleaned)
}

fn memory_card_point_has_blocking_noise(point string) bool {
	cleaned := point.trim_space()
	return memory_looks_like_malformed_inline_code_for_card(cleaned)
		|| memory_looks_like_command_line_for_card(cleaned)
		|| memory_looks_like_regression_confirmation_for_card(cleaned)
		|| memory_looks_like_hypothesis_validation_for_card(cleaned)
		|| memory_looks_like_unresolved_question_for_card(cleaned)
		|| memory_looks_like_future_action_process_for_card(cleaned)
		|| memory_looks_like_process_or_debug_card_point(cleaned)
		|| memory_looks_like_raw_schema_fragment_for_card(cleaned)
		|| memory_looks_like_corrupt_or_truncated_fragment_for_card(cleaned)
}

fn memory_card_point_score(point string) int {
	mut score := 0
	if memory_looks_like_decision_text(point) {
		score += 3
	}
	if memory_looks_like_unresolved_issue_text(point) || point.contains('根因')
		|| point.contains('原因') || point.contains('触发点') || point.contains('说明') {
		score += 2
	}
	if point.contains('不要') || point.contains('不能') || point.contains('必须')
		|| point.contains('不要求') || point.contains('约束') || point.contains('限制')
		|| memory_looks_like_constraint_text(point) {
		score += 3
	}
	if reflection_like_durable_artifact(point) {
		score += 2
	}
	if point.runes().len >= 18 {
		score += 1
	}
	return score
}

fn reflection_like_durable_artifact(text string) bool {
	return text.contains('`') || text.contains('/') || text.contains('.v') || text.contains('.js')
		|| text.contains('.ts') || text.contains('.json') || text.contains('.md')
		|| text.contains('_ROOT') || text.contains('_PATH') || text.contains('@')
}

fn memory_looks_like_isolated_artifact_for_card(text string) bool {
	cleaned := text.trim_space().trim('- *`，。:： ')
	if cleaned.runes().len > 32 {
		return false
	}
	if cleaned.contains(' ') || cleaned.contains('/') {
		return false
	}
	if memory_looks_like_decision_text(cleaned) || memory_looks_like_unresolved_issue_text(cleaned) {
		return false
	}
	return cleaned.contains('.') || cleaned.contains('_') || cleaned.contains('-')
}

fn memory_looks_like_ascii_label_for_card(text string) bool {
	cleaned := text.trim_space().trim('- *`，。:： ')
	if cleaned.len == 0 || cleaned.runes().len > 40 {
		return false
	}
	if memory_looks_like_decision_text(cleaned) || memory_looks_like_unresolved_issue_text(cleaned)
		|| memory_looks_like_constraint_text(cleaned) {
		return false
	}
	mut has_ascii_word := false
	mut has_separator := false
	for ch in cleaned.bytes() {
		if ch > 127 {
			return false
		}
		if (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) {
			has_ascii_word = true
		}
		if ch == `+` || ch == `/` || ch == `,` {
			has_separator = true
		}
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| (ch >= `0` && ch <= `9`) || ch == `_` || ch == `-` || ch == `+`
			|| ch == `/` || ch == `,` || ch == ` `) {
			return false
		}
	}
	return has_ascii_word && has_separator
}

fn memory_looks_like_context_dependent_short_note_for_card(text string) bool {
	cleaned := text.trim_space().trim('- *，。:： ')
	if cleaned.runes().len > 24 {
		return false
	}
	if reflection_like_durable_artifact(cleaned) || memory_looks_like_decision_text(cleaned) {
		return false
	}
	lower := cleaned.to_lower()
	for marker in ['传一遍', '走一遍', '做一遍', '调一下', '看一下', '这一块',
		'这个点', '那一块', '这种方式', '没带回去', '没带回来'] {
		if lower.contains(marker) {
			return true
		}
	}
	return false
}

fn memory_looks_like_malformed_inline_code_for_card(text string) bool {
	first_tick := text.index('`') or { return false }
	if first_tick == 0 {
		return false
	}
	before := text[..first_tick].trim_space()
	if before.len == 0 {
		return false
	}
	parts := before.split(' ')
	token := parts[parts.len - 1].trim_space()
	if token.len == 0 {
		return false
	}
	if token.contains('_') || token.contains('.') || token.contains('__') || token.contains('(')
		|| token.contains(')') || token.contains('\\') {
		return true
	}
	mut ascii_word := token.len > 1 && token.len <= 32
	for ch in token.bytes() {
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| (ch >= `0` && ch <= `9`) || ch == `_` || ch == `-`) {
			ascii_word = false
		}
		if ch >= `A` && ch <= `Z` {
			return true
		}
	}
	return ascii_word
}

fn memory_looks_like_command_line_for_card(text string) bool {
	lower := text.to_lower().trim_space()
	for prefix in ['php ', 'make ', 'npm ', 'cargo ', 'v test ', 'v run ', './', '../', 'sudo ',
		'cd '] {
		if lower.starts_with(prefix) {
			return true
		}
	}
	return false
}

fn memory_looks_like_regression_confirmation_for_card(text string) bool {
	lower := text.to_lower()
	return lower.contains('确认这个') || lower.contains('确认回归')
		|| lower.contains('正式跑法') || lower.contains('确认没有漏掉')
		|| lower.contains('你现在可以直接改') || lower.contains('你可以直接改')
		|| lower.contains('现在可以直接改')
}

fn memory_looks_like_hypothesis_validation_for_card(text string) bool {
	lower := text.to_lower()
	return lower.contains('不是最终') || lower.contains('不一定是最终')
		|| lower.contains('如果它能') || lower.contains('如果能立刻')
		|| lower.contains('说明崩点') || lower.contains('碰到正确层')
		|| lower.contains('刚才那条改动') || lower.contains('如果成立')
		|| lower.contains('如果真是') || lower.contains('不是我们要的')
		|| lower.contains('还不是我们要的') || lower.contains('有信息量')
}

fn memory_looks_like_vague_resolution_title_for_card(text string) bool {
	lower := text.to_lower().trim_space().trim('，。:： ')
	for marker in ['定位到了', '已经定位到', '定位到原因了', '原因清楚了',
		'这下原因清楚了', '表结构已经说明原因了', '已经说明原因了',
		'又抓到一条很像根因', '有新信号', '编译这边有新信号',
		'编译已经起了'] {
		if lower == marker || lower.contains(marker) {
			return true
		}
	}
	return false
}

fn memory_looks_like_process_or_debug_card_title(text string) bool {
	lower := text.to_lower()
	for marker in ['日志', 'stderr', '抓最后', '不对劲', '不需要再飘', '根因基本对上',
		'不能完整返回', '这回栈', '看最后一段'] {
		if lower.contains(marker) {
			return true
		}
	}
	return false
}

fn memory_looks_like_process_or_debug_card_point(text string) bool {
	lower := text.to_lower()
	for marker in ['不能完整返回', '日志文件', 'stderr 输出', '看到崩溃前最后', '我现在修的就是',
		'不需要再飘', '根因基本对上', '空 body', 'controller not bound'] {
		if lower.contains(marker) {
			return true
		}
	}
	return false
}

fn memory_looks_like_raw_schema_fragment_for_card(text string) bool {
	lower := text.to_lower().trim_space()
	for prefix in ['add column ', 'alter table ', 'create table ', 'drop table ', 'create index ',
		'drop index '] {
		if lower.starts_with(prefix) {
			return true
		}
	}
	return false
}

fn memory_looks_like_unresolved_question_for_card(text string) bool {
	cleaned := text.trim_space().trim('- *，。:： ')
	lower := cleaned.to_lower()
	for prefix in ['是不是', '是否', '为什么', '怎么', '哪里', '哪一层'] {
		if lower.starts_with(prefix) {
			return true
		}
	}
	return cleaned.ends_with('?') || cleaned.ends_with('？')
}

fn memory_looks_like_future_action_process_for_card(text string) bool {
	lower := text.to_lower()
	if lower.contains('接下来就把') || lower.contains('接下来我会')
		|| lower.contains('接下来再') || lower.contains('然后再')
		|| lower.contains('下一步我要') || lower.contains('下一步我会')
		|| lower.contains('这轮要等') || lower.contains('我再确认一次')
		|| lower.contains('如果是，我会') || lower.contains('如果是我会')
		|| lower.contains('我直接改掉') || lower.contains('直接改掉')
		|| lower.contains('这处很小') || lower.contains('跑一个相关测试') {
		return true
	}
	if lower.starts_with('我要去') || lower.starts_with('我去把')
		|| lower.starts_with('我会把') || lower.starts_with('我准备把')
		|| lower.starts_with('我要先') || lower.starts_with('我要重新')
		|| lower.starts_with('我就直接') || lower.starts_with('我准备直接') {
		return true
	}
	if lower.contains('一次性补') || lower.contains('后面再补') {
		return true
	}
	if (lower.contains('确认') || lower.contains('验证'))
		&& (lower.contains('能直接用') || lower.contains('可以直接用')) {
		return true
	}
	if lower.contains('把范围压到') && lower.contains('这条链') {
		return true
	}
	return false
}

fn memory_looks_like_corrupt_or_truncated_fragment_for_card(text string) bool {
	cleaned := text.trim_space()
	if cleaned.contains('�') {
		return true
	}
	if cleaned.contains('Ɲ') {
		return true
	}
	if cleaned.contains('[') && !cleaned.contains(']') {
		return true
	}
	if cleaned.contains('](') && !cleaned.contains(')') {
		return true
	}
	if memory_has_unbalanced_cjk_quotes(cleaned) {
		return true
	}
	if cleaned.ends_with('...') || cleaned.ends_with('..') || cleaned.ends_with('……') {
		return true
	}
	if cleaned.ends_with('.') && cleaned.len >= 2 {
		prev := cleaned.bytes()[cleaned.len - 2]
		return prev > 127
	}
	return false
}

fn memory_has_unbalanced_cjk_quotes(text string) bool {
	if text.count('“') != text.count('”') {
		return true
	}
	close_idx := text.index('”') or { return false }
	open_idx := text.index('“') or { return false }
	return close_idx < open_idx
}

fn memory_looks_like_transient_card_point(text string) bool {
	lower := text.to_lower()
	for marker in ['我先', '我会先', '我准备', '我去看', '我要开始', '我要动',
		'我再看一下', '我顺手', '我同意', '随后会', '现在把', '我在等',
		'会直接指出', '找到具体 workflow', '我再确认一次'] {
		if lower.contains(marker) {
			return true
		}
	}
	return false
}

fn memory_card_topic_key(input memory.ReflectionPersistInput) string {
	material := memory_card_match_text(input.title, input.summary_md)
	if material.len == 0 {
		return ''
	}
	return 'agentview-card:' + sha256.sum(memory_card_canonical_text(material).bytes()).hex()[..16]
}

fn memory_card_match_text(title string, summary_md string) string {
	return '${title}\n${memory_card_summary_points_text(summary_md)}'.trim_space()
}

fn memory_card_summary_points_text(summary_md string) string {
	return memory_card_summary_points(summary_md).join('\n')
}

fn memory_card_match_terms(title string, summary_md string) []string {
	text := memory_card_match_text(title, summary_md)
	mut terms := []string{}
	mut current := ''
	for r in text.runes() {
		ch := r.str()
		if ch.len == 1 && ((ch[0] >= `a` && ch[0] <= `z`)
			|| (ch[0] >= `A` && ch[0] <= `Z`) || (ch[0] >= `0` && ch[0] <= `9`)
			|| ch[0] == `_` || ch[0] == `-`) {
			current += ch.to_lower()
			continue
		}
		if current.len >= 2 {
			terms << current
		}
		current = ''
	}
	if current.len >= 2 {
		terms << current
	}
	mut scored := []string{}
	mut seen := map[string]bool{}
	for term in terms {
		cleaned := term.trim('-_')
		if cleaned.len < 2 || cleaned in seen || cleaned in ['the', 'and', 'with'] {
			continue
		}
		seen[cleaned] = true
		scored << cleaned
	}
	scored.sort_with_compare(fn (a &string, b &string) int {
		if a.len > b.len {
			return -1
		}
		if a.len < b.len {
			return 1
		}
		if *a < *b {
			return -1
		}
		if *a > *b {
			return 1
		}
		return 0
	})
	return if scored.len > 8 { scored[..8] } else { scored }
}

fn memory_card_canonical_text(text string) string {
	mut out :=
		text.to_lower().replace('\r', '').replace('\n', '').replace('\t', '').replace(' ', '')
	for marker in ['-', '*', '#', '`', '"', "'", '“', '”', '，', '。', ':', '：', '(', ')',
		'[', ']'] {
		out = out.replace(marker, '')
	}
	return out
}

fn memory_card_lexical_guard_score(new_title string, new_summary string, old_title string, old_summary string) f64 {
	title_score := memory_card_text_similarity(new_title, old_title)
	summary_score := memory_card_text_similarity(memory_card_summary_points_text(new_summary),
		memory_card_summary_points_text(old_summary))
	return title_score * 0.45 + summary_score * 0.55
}

fn memory_card_text_similarity(left string, right string) f64 {
	left_key := memory_card_canonical_text(left)
	right_key := memory_card_canonical_text(right)
	if left_key.len == 0 || right_key.len == 0 {
		return 0.0
	}
	if left_key == right_key {
		return 1.0
	}
	if left_key.contains(right_key) || right_key.contains(left_key) {
		return 0.82
	}
	return memory_card_ngram_jaccard(left_key, right_key)
}

fn memory_card_ngram_jaccard(left string, right string) f64 {
	left_grams := memory_card_char_ngrams(left, 2)
	right_grams := memory_card_char_ngrams(right, 2)
	if left_grams.len == 0 || right_grams.len == 0 {
		return 0.0
	}
	mut left_set := map[string]bool{}
	for gram in left_grams {
		left_set[gram] = true
	}
	mut right_set := map[string]bool{}
	for gram in right_grams {
		right_set[gram] = true
	}
	mut intersection := 0
	for gram, _ in left_set {
		if gram in right_set {
			intersection++
		}
	}
	union_count := left_set.len + right_set.len - intersection
	return if union_count > 0 { f64(intersection) / f64(union_count) } else { 0.0 }
}

fn memory_card_char_ngrams(text string, n int) []string {
	chars := text.runes()
	if chars.len == 0 {
		return []string{}
	}
	if chars.len <= n {
		return [text]
	}
	mut out := []string{}
	for idx := 0; idx <= chars.len - n; idx++ {
		mut gram := ''
		for offset := 0; offset < n; offset++ {
			gram += chars[idx + offset].str()
		}
		out << gram
	}
	return out
}

fn cosine_similarity(left []f32, right []f32) f64 {
	if left.len == 0 || right.len == 0 || left.len != right.len {
		return 0.0
	}
	mut dot := f64(0)
	mut left_norm := f64(0)
	mut right_norm := f64(0)
	for idx, value in left {
		l := f64(value)
		r := f64(right[idx])
		dot += l * r
		left_norm += l * l
		right_norm += r * r
	}
	if left_norm == 0 || right_norm == 0 {
		return 0.0
	}
	return dot / (math.sqrt(left_norm) * math.sqrt(right_norm))
}

pub fn (store PollyDbStore) inspect_recent_memory_salience(recent_sessions int) !MemorySalienceReport {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	session_limit := if recent_sessions > 0 { recent_sessions } else { 12 }
	entry_rows := recent_entry_rows(mut db, session, session_limit)!
	_, report := memory_candidates_for_embedding(mut db, session, entry_rows, 0, 0)!
	return report
}

struct MemorySegmentEntry {
	primary_key []u8
	session_id  string
	timestamp   string
	score       int
	entry       SessionEntry
	vector      []f32
}

struct MemorySegmentAnchor {
	primary_key     []u8
	session_id      string
	timestamp       string
	score           int
	segment_score   int
	entry_count     int
	segment_kind    string
	segment_horizon string
	entries         []MemorySegmentEntry
}

struct MemorySegmentState {
mut:
	entries  []MemorySegmentEntry
	centroid []f32
}

fn build_memory_segment_anchors(candidates []MemoryCandidate, mut engine memory.EmbeddingEngine, candidate_limit int) ![]MemorySegmentAnchor {
	mut entries_by_session := map[string][]MemorySegmentEntry{}
	for idx, candidate in candidates {
		full_row := candidate.row
		entry := candidate.entry
		if should_skip_markdown_index(entry, entry.text) {
			continue
		}
		text := memory_segment_text(entry)
		if text.len == 0 {
			continue
		}
		memory_distill_progress('embed segment candidate ${idx + 1}/${candidates.len} key=${full_row.primary_key.bytestr()}')
		vector := engine.embed(text) or { continue }
		session_id := candidate.session_id
		entries_by_session[session_id] << MemorySegmentEntry{
			primary_key: full_row.primary_key.clone()
			session_id:  session_id
			timestamp:   entry.timestamp
			score:       memory_seed_entry_score(entry)
			entry:       entry
			vector:      vector
		}
	}
	mut anchors := []MemorySegmentAnchor{}
	for _, mut session_entries in entries_by_session {
		if session_entries.len == 0 {
			continue
		}
		session_entries.sort_with_compare(fn (a &MemorySegmentEntry, b &MemorySegmentEntry) int {
			if a.timestamp < b.timestamp {
				return -1
			}
			if a.timestamp > b.timestamp {
				return 1
			}
			a_key := a.primary_key.bytestr()
			b_key := b.primary_key.bytestr()
			if a_key < b_key {
				return -1
			}
			if a_key > b_key {
				return 1
			}
			return 0
		})
		mut current := MemorySegmentState{}
		for entry in session_entries {
			if current.entries.len == 0 {
				current = start_memory_segment(entry)
				continue
			}
			if memory_segment_accepts(current, entry) {
				append_memory_segment(mut current, entry)
				continue
			}
			anchors << current.anchor()
			current = start_memory_segment(entry)
		}
		if current.entries.len > 0 {
			anchors << current.anchor()
		}
	}
	mut preferred := []MemorySegmentAnchor{}
	mut deferred := []MemorySegmentAnchor{}
	for anchor in anchors {
		if anchor.segment_horizon == 'transient' {
			deferred << anchor
		} else {
			preferred << anchor
		}
	}
	if preferred.len > 0 {
		anchors = preferred.clone()
		anchors << deferred
	}
	anchors.sort_with_compare(fn (a &MemorySegmentAnchor, b &MemorySegmentAnchor) int {
		a_horizon := memory_segment_horizon_rank(a.segment_horizon)
		b_horizon := memory_segment_horizon_rank(b.segment_horizon)
		if a_horizon > b_horizon {
			return -1
		}
		if a_horizon < b_horizon {
			return 1
		}
		a_rank := memory_segment_kind_rank(a.segment_kind)
		b_rank := memory_segment_kind_rank(b.segment_kind)
		if a_rank > b_rank {
			return -1
		}
		if a_rank < b_rank {
			return 1
		}
		if a.segment_score > b.segment_score {
			return -1
		}
		if a.segment_score < b.segment_score {
			return 1
		}
		if a.timestamp > b.timestamp {
			return -1
		}
		if a.timestamp < b.timestamp {
			return 1
		}
		a_key := a.primary_key.bytestr()
		b_key := b.primary_key.bytestr()
		if a_key < b_key {
			return -1
		}
		if a_key > b_key {
			return 1
		}
		return 0
	})
	limit := if candidate_limit > 0 { candidate_limit } else { 0 }
	if limit > 0 && anchors.len > limit {
		return anchors[..limit].clone()
	}
	return anchors
}

fn build_in_memory_agentview_reflection_job(anchor MemorySegmentAnchor, neighbor_limit int) memory.ReflectionJob {
	limit := if neighbor_limit > 0 { neighbor_limit } else { 8 }
	seed := memory_segment_seed_entry(anchor)
	mut evidence := memory_segment_evidence(anchor, seed, limit)
	return memory.ReflectionJob{
		branch_name:     store_branch
		table_name:      agentview_memory_capability_table
		primary_key:     anchor.primary_key.clone()
		column_name:     agentview_memory_capability_column
		reflection_kind: 'summary'
		seed_scope:      .block
		seed_anchor:     memory_segment_anchor(seed)
		seed_text:       memory_segment_text(seed.entry)
		evidence:        evidence
	}
}

fn memory_segment_seed_entry(anchor MemorySegmentAnchor) MemorySegmentEntry {
	for entry in anchor.entries {
		if entry.primary_key == anchor.primary_key {
			return entry
		}
	}
	if anchor.entries.len > 0 {
		return anchor.entries[0]
	}
	return MemorySegmentEntry{}
}

fn memory_segment_evidence(anchor MemorySegmentAnchor, seed MemorySegmentEntry, limit int) []memory.ReflectionEvidence {
	mut evidence := []memory.ReflectionEvidence{}
	for entry in anchor.entries {
		if entry.primary_key == seed.primary_key {
			continue
		}
		if !memory_entries_same_pure_topic(seed, entry) {
			continue
		}
		text := memory_segment_text(entry.entry)
		if text.len == 0 {
			continue
		}
		evidence << memory.ReflectionEvidence{
			table_name:  agentview_memory_capability_table
			primary_key: entry.primary_key.clone()
			column_name: agentview_memory_capability_column
			target_id:   memory_segment_target_id(entry)
			score:       storage.vector_cosine_similarity(seed.vector, entry.vector)
			scope:       .block
			kind:        entry.entry.kind.str()
			anchor:      memory_segment_anchor(entry)
			path_hint:   'session=${entry.session_id} seq=${entry.entry.seq}'
			text:        text
		}
	}
	evidence.sort_with_compare(fn (a &memory.ReflectionEvidence, b &memory.ReflectionEvidence) int {
		if a.score > b.score {
			return -1
		}
		if a.score < b.score {
			return 1
		}
		a_key := a.primary_key.bytestr()
		b_key := b.primary_key.bytestr()
		if a_key < b_key {
			return -1
		}
		if a_key > b_key {
			return 1
		}
		return 0
	})
	if limit > 0 && evidence.len > limit {
		return evidence[..limit].clone()
	}
	return evidence
}

fn memory_segment_target_id(entry MemorySegmentEntry) string {
	return '${entry.session_id}:${entry.entry.seq}:content_md'
}

fn memory_segment_anchor(entry MemorySegmentEntry) string {
	return 'entry:${entry.entry.seq}'
}

fn memory_candidates_for_embedding(mut db storage.PersistentDatabase, session storage.DatabaseSession, entry_rows []storage.TypedSchemaRow, candidate_limit int, candidate_offset int) !([]MemoryCandidate, MemorySalienceReport) {
	mut report := MemorySalienceReport{
		skipped_by_reason:          map[string]int{}
		discarded_before_embedding: map[string]int{}
		candidates_by_type:         map[string]int{}
	}
	mut candidates := []MemoryCandidate{}
	for row in entry_rows {
		report.raw_entries++
		entry_id := agentview_required_row_string(row, 'id') or {
			memory_salience_count(mut report.skipped_by_reason, 'missing_id')
			continue
		}
		full_row := session.get_row(mut db, 'entries', entry_id.bytes()) or {
			memory_salience_count(mut report.skipped_by_reason, 'missing_row')
			continue
		}
		entry := decode_session_entry(full_row) or {
			memory_salience_count(mut report.skipped_by_reason, 'decode_error')
			continue
		}
		decision := classify_memory_salience(entry)
		if !decision.memory_worthy {
			memory_salience_count(mut report.skipped_by_reason, decision.skip_reason)
			continue
		}
		session_id := entry_session_id(full_row) or {
			memory_salience_count(mut report.skipped_by_reason, 'missing_session')
			continue
		}
		candidates << MemoryCandidate{
			row:        full_row
			entry:      entry
			decision:   decision
			session_id: session_id
		}
		report.candidate_entries++
		memory_salience_count(mut report.candidates_by_type, decision.candidate_type)
	}
	selected := memory_select_embedding_candidates(candidates, candidate_limit, candidate_offset, mut
		report)
	report.embedding_candidate_entries = selected.len
	return selected, report
}

fn memory_salience_count(mut counts map[string]int, key string) {
	label := if key.len > 0 { key } else { 'unknown' }
	counts[label] = counts[label] + 1
}

fn memory_select_embedding_candidates(candidates []MemoryCandidate, candidate_limit int, candidate_offset int, mut report MemorySalienceReport) []MemoryCandidate {
	mut selected := []MemoryCandidate{}
	mut deferred := []MemoryCandidate{}
	for candidate in candidates {
		if candidate.horizon() == 'transient' {
			memory_salience_count(mut report.discarded_before_embedding,
				candidate.embedding_discard_reason())
			continue
		}
		if !candidate.has_distillable_seed_outline() {
			memory_salience_count(mut report.discarded_before_embedding,
				'undistillable_outline_before_embedding')
			continue
		}
		if candidate.should_embed_directly() {
			selected << candidate
			continue
		}
		if candidate.can_be_rescued_later() {
			deferred << candidate
			continue
		}
		memory_salience_count(mut report.discarded_before_embedding,
			candidate.embedding_discard_reason())
	}
	for candidate in deferred {
		if candidate.has_durable_neighbor(candidates) {
			selected << candidate
		} else {
			memory_salience_count(mut report.discarded_before_embedding,
				candidate.embedding_discard_reason())
		}
	}
	selected.sort_with_compare(fn (a &MemoryCandidate, b &MemoryCandidate) int {
		a_rank := a.embedding_rank()
		b_rank := b.embedding_rank()
		if a_rank > b_rank {
			return -1
		}
		if a_rank < b_rank {
			return 1
		}
		if a.decision.score > b.decision.score {
			return -1
		}
		if a.decision.score < b.decision.score {
			return 1
		}
		if a.entry.timestamp > b.entry.timestamp {
			return -1
		}
		if a.entry.timestamp < b.entry.timestamp {
			return 1
		}
		a_key := a.primary_key().bytestr()
		b_key := b.primary_key().bytestr()
		if a_key < b_key {
			return -1
		}
		if a_key > b_key {
			return 1
		}
		return 0
	})
	offset := if candidate_offset > 0 { candidate_offset } else { 0 }
	if offset >= selected.len {
		return []MemoryCandidate{}
	}
	mut window := selected[offset..].clone()
	if candidate_limit > 0 && window.len > candidate_limit {
		window = window[..candidate_limit].clone()
	}
	return window
}

fn (candidate MemoryCandidate) has_distillable_seed_outline() bool {
	return memory.reflection_job_has_distillable_outline(memory.ReflectionJob{
		branch_name:     store_branch
		table_name:      agentview_memory_capability_table
		primary_key:     candidate.primary_key()
		column_name:     agentview_memory_capability_column
		reflection_kind: 'summary'
		seed_scope:      .block
		seed_anchor:     'entry:${candidate.entry.seq}'
		seed_text:       candidate.entry.text
	}, memory.ReflectionDistillOptions{})
}

fn (candidate MemoryCandidate) primary_key() []u8 {
	return candidate.row.primary_key.clone()
}

fn (candidate MemoryCandidate) horizon() string {
	match candidate.decision.candidate_type {
		'decision', 'root_cause', 'constraint', 'procedure', 'preference', 'unresolved_issue' {
			return 'durable'
		}
		'artifact', 'fact' {
			return 'situational'
		}
		'execution_context' {
			return 'transient'
		}
		else {
			return 'situational'
		}
	}
}

fn (candidate MemoryCandidate) should_embed_directly() bool {
	horizon := candidate.horizon()
	if horizon == 'durable' {
		return true
	}
	if horizon == 'situational' {
		return candidate.decision.score >= 24
	}
	return false
}

fn (candidate MemoryCandidate) can_be_rescued_later() bool {
	if candidate.horizon() == 'transient' {
		return false
	}
	return candidate.decision.score >= 12
}

fn (candidate MemoryCandidate) has_durable_neighbor(candidates []MemoryCandidate) bool {
	for other in candidates {
		if other.primary_key() == candidate.primary_key() {
			continue
		}
		if other.session_id != candidate.session_id {
			continue
		}
		if other.horizon() != 'durable' {
			continue
		}
		if memory_topic_hint_overlap(candidate.entry.text, other.entry.text) {
			return true
		}
	}
	return false
}

fn (candidate MemoryCandidate) embedding_discard_reason() string {
	horizon := candidate.horizon()
	if horizon == 'transient' {
		return 'transient_before_embedding'
	}
	if horizon == 'situational' {
		return 'weak_situational_before_embedding'
	}
	return 'low_priority_before_embedding'
}

fn (candidate MemoryCandidate) embedding_rank() int {
	match candidate.decision.candidate_type {
		'decision' { return 60 }
		'root_cause' { return 58 }
		'constraint' { return 56 }
		'procedure' { return 54 }
		'preference' { return 52 }
		'unresolved_issue' { return 50 }
		'artifact' { return 40 }
		'fact' { return 36 }
		else { return 10 }
	}
}

fn classify_memory_salience(entry SessionEntry) MemorySalienceDecision {
	text := entry.text.trim_space()
	if text.len == 0 {
		return memory_skip_decision('empty', -1000)
	}
	if should_skip_markdown_index(entry, text) {
		return memory_skip_decision('non_memory_markup', -900)
	}
	if entry.kind in [.tool_call, .tool_result, .meta] {
		return memory_skip_decision('tool_or_meta', -800)
	}
	if text.len > 32768 {
		return memory_skip_decision('large_output', -700)
	}
	if memory_looks_like_shell_prompt(text) {
		return memory_skip_decision('shell_prompt', -650)
	}
	if memory_looks_like_raw_log(text) {
		return memory_skip_decision('raw_log', -620)
	}
	if memory_looks_like_dialogue_control_text(text) {
		return memory_skip_decision('dialogue_control', -610)
	}
	claims := memory_extract_salient_claims(entry)
	if claims.len > 0 {
		best := memory_best_claim(claims)
		return memory_claim_decision(best, claims)
	}
	if reflection_like_execution_context_text(text) {
		return memory_candidate_decision('execution_context', memory_seed_entry_score(entry))
	}
	if reflection_like_root_cause_text(text) {
		return memory_candidate_decision('root_cause', memory_seed_entry_score(entry))
	}
	if reflection_like_constraint_text(text) {
		return memory_candidate_decision('constraint', memory_seed_entry_score(entry))
	}
	if memory_looks_like_decision_text(text) {
		return memory_candidate_decision('decision', memory_seed_entry_score(entry))
	}
	if memory_looks_like_unresolved_issue_text(text) {
		return memory_candidate_decision('unresolved_issue', memory_seed_entry_score(entry))
	}
	if reflection_like_process_status_text(text) || reflection_like_execution_update_text(text) {
		return memory_skip_decision('transient_status', memory_seed_entry_score(entry))
	}
	if reflection_like_artifact_text(text) {
		return memory_candidate_decision('artifact', memory_seed_entry_score(entry))
	}
	score := memory_seed_entry_score(entry)
	if score >= 30 {
		return memory_candidate_decision('fact', score)
	}
	if text.len < 24 {
		return memory_skip_decision('low_information', score)
	}
	return memory_skip_decision('low_salience', score)
}

fn memory_candidate_decision(candidate_type string, score int) MemorySalienceDecision {
	return MemorySalienceDecision{
		memory_worthy:  true
		candidate_type: candidate_type
		score:          score
	}
}

fn memory_claim_decision(claim MemoryClaim, claims []MemoryClaim) MemorySalienceDecision {
	return MemorySalienceDecision{
		memory_worthy:  true
		candidate_type: claim.claim_type
		score:          claim.score
		claims:         claims
	}
}

fn memory_skip_decision(reason string, score int) MemorySalienceDecision {
	return MemorySalienceDecision{
		skip_reason: reason
		score:       score
	}
}

fn memory_extract_salient_claims(entry SessionEntry) []MemoryClaim {
	base_score := memory_seed_entry_score(entry)
	mut claims := []MemoryClaim{}
	for piece in memory_candidate_claim_texts(entry.text) {
		claim := memory_claim_from_text(piece, base_score) or { continue }
		claims << claim
	}
	return claims
}

fn memory_candidate_claim_texts(text string) []string {
	mut out := []string{}
	for line in text.split_into_lines() {
		trimmed := line.trim_space().trim_left('-*0123456789.、) ')
		if trimmed.len == 0 {
			continue
		}
		if trimmed.len <= 220 {
			out << trimmed
			continue
		}
		for sentence in memory_split_claim_sentences(trimmed) {
			if sentence.len > 0 {
				out << sentence
			}
		}
	}
	if out.len == 0 {
		for sentence in memory_split_claim_sentences(text) {
			if sentence.len > 0 {
				out << sentence
			}
		}
	}
	return out
}

fn memory_split_claim_sentences(text string) []string {
	mut normalized := text.replace('。', '\n').replace('；', '\n').replace(';', '\n')
	normalized = normalized.replace('！', '\n').replace('？', '\n')
	mut out := []string{}
	for part in normalized.split_into_lines() {
		cleaned := part.trim_space()
		if cleaned.len > 0 {
			out << cleaned
		}
	}
	return out
}

fn memory_claim_from_text(text string, base_score int) ?MemoryClaim {
	claim_text := memory_normalize_claim_text(text)
	if !memory_claim_has_evidence_shape(claim_text) {
		return none
	}
	if memory_claim_looks_like_noise(claim_text) {
		return none
	}
	claim_type := memory_claim_type(claim_text) or { return none }
	return MemoryClaim{
		text:       claim_text
		claim_type: claim_type
		score:      base_score + memory_claim_type_bonus(claim_type)
	}
}

fn memory_normalize_claim_text(text string) string {
	mut cleaned := text.trim_space()
	for cleaned.starts_with('我确认了：') || cleaned.starts_with('确认了：')
		|| cleaned.starts_with('定位到了：') || cleaned.starts_with('结论是：') {
		cleaned = cleaned.all_after('：').trim_space()
	}
	return cleaned
}

fn memory_claim_has_evidence_shape(text string) bool {
	if text.len < 18 {
		return false
	}
	if text.contains('`') || text.contains('/') || text.contains('.') || text.contains('_')
		|| text.contains('-') {
		return true
	}
	lower := text.to_lower()
	return lower.contains('因为') || lower.contains('原因') || lower.contains('根因')
		|| lower.contains('决定') || lower.contains('采用') || lower.contains('改用')
		|| lower.contains('不能') || lower.contains('不要') || lower.contains('必须')
		|| lower.contains('只服务于') || lower.contains('最终') || lower.contains('约束')
}

fn memory_claim_looks_like_noise(text string) bool {
	lower := text.to_lower()
	if reflection_like_process_status_text(text) || reflection_like_execution_update_text(text) {
		return true
	}
	if lower.contains('你继续') || lower.contains('好的') || lower.contains('同意，你')
		|| lower.contains('开始吧') || lower.contains('继续吧') {
		return true
	}
	if lower.contains('我直接改掉') || lower.contains('跑一个相关测试')
		|| lower.contains('你现在可以直接改') {
		return true
	}
	return false
}

fn memory_claim_type(text string) ?string {
	lower := text.to_lower()
	if reflection_like_root_cause_text(text) {
		return 'root_cause'
	}
	if reflection_like_constraint_text(text) || memory_looks_like_constraint_text(text) {
		return 'constraint'
	}
	if lower.contains('偏好') || lower.contains('更喜欢') || lower.contains('倾向于') {
		return 'preference'
	}
	if lower.contains('流程') || lower.contains('步骤') || lower.contains('命令')
		|| lower.contains('run-tests.php') || lower.contains('复核') {
		return 'procedure'
	}
	if memory_looks_like_decision_text(text) {
		return 'decision'
	}
	if memory_looks_like_unresolved_issue_text(text) {
		return 'unresolved_issue'
	}
	if reflection_like_artifact_text(text) {
		return 'artifact'
	}
	if memory_seed_like_stable_fact(text) {
		return 'fact'
	}
	return none
}

fn memory_seed_like_stable_fact(text string) bool {
	lower := text.to_lower()
	return lower.contains('是') || lower.contains('需要') || lower.contains('使用')
		|| lower.contains('依赖') || lower.contains('来自') || lower.contains('支持')
}

fn memory_claim_type_bonus(claim_type string) int {
	return match claim_type {
		'decision' { 18 }
		'root_cause' { 16 }
		'constraint' { 14 }
		'procedure' { 12 }
		'preference' { 12 }
		'unresolved_issue' { 10 }
		'artifact' { 6 }
		'fact' { 4 }
		else { 0 }
	}
}

fn memory_best_claim(claims []MemoryClaim) MemoryClaim {
	mut best := claims[0]
	for claim in claims[1..] {
		if claim.score > best.score {
			best = claim
			continue
		}
		if claim.score == best.score
			&& memory_claim_rank(claim.claim_type) > memory_claim_rank(best.claim_type) {
			best = claim
		}
	}
	return best
}

fn memory_claim_rank(claim_type string) int {
	return match claim_type {
		'decision' { 8 }
		'root_cause' { 7 }
		'constraint' { 6 }
		'procedure' { 5 }
		'preference' { 4 }
		'unresolved_issue' { 3 }
		'artifact' { 2 }
		'fact' { 1 }
		else { 0 }
	}
}

fn memory_looks_like_decision_text(text string) bool {
	lower := text.to_lower()
	return lower.contains('决定') || lower.contains('确认') || lower.contains('同意')
		|| lower.contains('采用') || lower.contains('改用') || lower.contains('选择')
		|| lower.contains('最终') || lower.contains('定下来') || lower.contains('范围确认')
}

fn memory_looks_like_unresolved_issue_text(text string) bool {
	lower := text.to_lower()
	return lower.contains('待解决') || lower.contains('还需要') || lower.contains('风险')
		|| lower.contains('阻塞') || lower.contains('失败') || lower.contains('不通过')
}

fn memory_looks_like_dialogue_control_text(text string) bool {
	lower := text.to_lower().trim_space()
	if lower in ['好的', '好', '同意', '继续', '好的，同意', '好的，继续'] {
		return true
	}
	return lower.contains('同意，你继续') || lower.contains('好的，同意，你继续')
		|| lower.contains('你继续') || lower.contains('开始吧') || lower.contains('继续吧')
}

fn memory_looks_like_constraint_text(text string) bool {
	lower := text.to_lower()
	return lower.contains('不要') || lower.contains('不能') || lower.contains('不得')
		|| lower.contains('必须') || lower.contains('不要求') || lower.contains('只服务于')
		|| lower.contains('只用于') || lower.contains('仅用于') || lower.contains('不复用')
		|| lower.contains('没有别的') || lower.contains('约束') || lower.contains('限制')
}

fn memory_looks_like_shell_prompt(text string) bool {
	trimmed := text.trim_space()
	return trimmed.starts_with('$ ') || trimmed.starts_with('% ') || trimmed.starts_with('> ')
		|| trimmed.starts_with('# ') || trimmed.contains('\n$ ') || trimmed.contains('\n% ')
}

fn memory_looks_like_raw_log(text string) bool {
	trimmed := text.trim_space()
	if trimmed.count('\n') < 8 {
		return false
	}
	lower := trimmed.to_lower()
	if lower.contains('error:') || lower.contains('warning:') || lower.contains('stack trace') {
		return true
	}
	mut log_like_lines := 0
	for line in trimmed.split_into_lines() {
		t := line.trim_space()
		if t.starts_with('at ') || t.starts_with('[') || t.starts_with('INFO ')
			|| t.starts_with('WARN ') || t.starts_with('ERROR ') || t.starts_with('+ ')
			|| t.starts_with('- ') {
			log_like_lines++
		}
	}
	return log_like_lines >= 5
}

fn memory_segment_horizon_rank(horizon string) int {
	return match horizon {
		'durable' { 2 }
		'situational' { 1 }
		'transient' { 0 }
		else { 1 }
	}
}

fn memory_segment_kind_rank(kind string) int {
	return match kind {
		'root_cause' { 5 }
		'technical_decision' { 4 }
		'constraint' { 3 }
		'technical_status' { 2 }
		'execution_update' { 1 }
		'workflow_status' { 0 }
		'execution_context' { -1 }
		else { 2 }
	}
}

fn start_memory_segment(entry MemorySegmentEntry) MemorySegmentState {
	return MemorySegmentState{
		entries:  [entry]
		centroid: entry.vector.clone()
	}
}

fn append_memory_segment(mut segment MemorySegmentState, entry MemorySegmentEntry) {
	prev_count := segment.entries.len
	segment.entries << entry
	if segment.centroid.len == 0 {
		segment.centroid = entry.vector.clone()
		return
	}
	for idx, value in entry.vector {
		segment.centroid[idx] = f32((f64(segment.centroid[idx]) * prev_count + value) / f64(
			prev_count + 1))
	}
}

fn memory_segment_accepts(segment MemorySegmentState, entry MemorySegmentEntry) bool {
	if segment.entries.len == 0 {
		return true
	}
	last := segment.entries[segment.entries.len - 1]
	if last.session_id != entry.session_id {
		return false
	}
	sim_last := storage.vector_cosine_similarity(last.vector, entry.vector)
	sim_centroid := storage.vector_cosine_similarity(segment.centroid, entry.vector)
	mut threshold := 0.72
	if last.entry.role == 'user' && entry.entry.role == 'assistant' {
		threshold = 0.55
	}
	if last.entry.kind == .reasoning || entry.entry.kind == .reasoning {
		threshold -= 0.05
	}
	if last.entry.role == 'user' && entry.entry.role == 'assistant' {
		return sim_last >= threshold || memory_topic_hint_overlap(last.entry.text, entry.entry.text)
	}
	if memory_topic_hint_overlap(last.entry.text, entry.entry.text) {
		return true
	}
	return sim_last >= threshold || sim_centroid >= threshold
}

fn memory_entries_same_pure_topic(left MemorySegmentEntry, right MemorySegmentEntry) bool {
	if left.session_id != right.session_id {
		return false
	}
	if memory_topic_hint_overlap(left.entry.text, right.entry.text) {
		return true
	}
	similarity := storage.vector_cosine_similarity(left.vector, right.vector)
	return similarity >= 0.86
}

fn (segment MemorySegmentState) anchor() MemorySegmentAnchor {
	mut best := segment.entries[0]
	for entry in segment.entries[1..] {
		if entry.score > best.score {
			best = entry
			continue
		}
		if entry.score == best.score && entry.timestamp > best.timestamp {
			best = entry
		}
	}
	return MemorySegmentAnchor{
		primary_key:     best.primary_key.clone()
		session_id:      best.session_id
		timestamp:       segment.entries[segment.entries.len - 1].timestamp
		score:           best.score
		segment_score:   best.score + (segment.entries.len - 1) * 8
		entry_count:     segment.entries.len
		segment_kind:    segment.kind()
		segment_horizon: segment.horizon()
		entries:         segment.entries.clone()
	}
}

fn (segment MemorySegmentState) kind() string {
	mut artifact_hits := 0
	mut constraint_hits := 0
	mut root_cause_hits := 0
	mut workflow_hits := 0
	mut update_hits := 0
	mut execution_context_hits := 0
	for entry in segment.entries {
		text := entry.entry.text
		if reflection_like_artifact_text(text) {
			artifact_hits++
		}
		if reflection_like_constraint_text(text) {
			constraint_hits++
		}
		if reflection_like_root_cause_text(text) {
			root_cause_hits++
		}
		if reflection_like_process_status_text(text) {
			workflow_hits++
		}
		if reflection_like_execution_update_text(text) {
			update_hits++
		}
		if reflection_like_execution_context_text(text) {
			execution_context_hits++
		}
	}
	if root_cause_hits > 0 {
		return 'root_cause'
	}
	if execution_context_hits >= segment.entries.len / 2 + 1 {
		return 'execution_context'
	}
	if artifact_hits > 0 && constraint_hits > 0 {
		return 'technical_decision'
	}
	if artifact_hits > 0 {
		return 'technical_status'
	}
	if constraint_hits > 0 {
		return 'constraint'
	}
	if workflow_hits >= segment.entries.len / 2 + 1 {
		return 'workflow_status'
	}
	if update_hits > 0 {
		return 'execution_update'
	}
	return 'technical_status'
}

fn (segment MemorySegmentState) horizon() string {
	mut artifact_hits := 0
	mut constraint_hits := 0
	mut root_cause_hits := 0
	mut workflow_hits := 0
	mut update_hits := 0
	mut execution_context_hits := 0
	for entry in segment.entries {
		text := entry.entry.text
		if reflection_like_artifact_text(text) {
			artifact_hits++
		}
		if reflection_like_constraint_text(text) {
			constraint_hits++
		}
		if reflection_like_root_cause_text(text) {
			root_cause_hits++
		}
		if reflection_like_process_status_text(text) {
			workflow_hits++
		}
		if reflection_like_execution_update_text(text) {
			update_hits++
		}
		if reflection_like_execution_context_text(text) {
			execution_context_hits++
		}
	}
	if execution_context_hits >= segment.entries.len / 2 + 1 {
		return 'transient'
	}
	if root_cause_hits > 0 || (artifact_hits > 0 && constraint_hits > 0) {
		return 'durable'
	}
	if artifact_hits > 0 && workflow_hits == 0 && update_hits == 0 {
		return 'durable'
	}
	if workflow_hits > 0 || update_hits > 0 {
		return 'situational'
	}
	return 'situational'
}

fn memory_segment_text(entry SessionEntry) string {
	text := entry.text.trim_space()
	if text.len <= 800 {
		return text
	}
	return text[..800]
}

fn memory_topic_hint_overlap(left string, right string) bool {
	left_hints := memory_topic_hints(left)
	if left_hints.len == 0 {
		return false
	}
	right_hints := memory_topic_hints(right)
	for hint in left_hints {
		if hint in right_hints {
			return true
		}
	}
	return false
}

fn memory_topic_hints(text string) []string {
	mut hints := []string{}
	mut seen := map[string]bool{}
	for raw in text.replace('`', ' ').replace('\n', ' ').replace('\t', ' ').replace('(', ' ').replace(')',
		' ').replace('[', ' ').replace(']', ' ').replace('{', ' ').replace('}', ' ').replace(',',
		' ').replace('，', ' ').replace('。', ' ').replace(':', ' ').replace('：', ' ').replace(';',
		' ').replace('；', ' ').replace('"', ' ').replace("'", ' ').split(' ') {
		token := raw.trim_space().to_lower()
		if token.len < 4 {
			continue
		}
		if !token.bytes().all(it.is_letter() || it.is_digit() || it == `_` || it == `-` || it == `/`
			|| it == `.`) {
			continue
		}
		if token !in seen {
			seen[token] = true
			hints << token
		}
	}
	return hints
}

fn memory_seed_row_score(row storage.TypedSchemaRow) int {
	entry := decode_session_entry(row) or { return -1000 }
	return memory_seed_entry_score(entry)
}

fn memory_seed_entry_score(entry SessionEntry) int {
	mut score := 0
	text := entry.text.trim_space()
	if text.len == 0 {
		return -1000
	}
	if likely_skip_memory_markdown_content(text) {
		return -900
	}
	if entry.kind in [.tool_call, .tool_result, .meta] {
		return -800
	}
	match entry.role {
		'assistant' { score += 24 }
		'user' { score += 4 }
		else { score += 8 }
	}

	match entry.kind {
		.reasoning { score += 14 }
		.message { score += 10 }
		else {}
	}

	content_len := text.len
	if content_len >= 40 {
		score += 10
	}
	if content_len >= 120 {
		score += 10
	}
	if content_len > 1200 {
		score -= 6
	}
	if content_len < 12 {
		score -= 18
	} else if content_len < 24 {
		score -= 8
	}
	if entry.role == 'user' && content_len < 24 {
		score -= 20
	}
	if reflection_like_instruction(text) {
		score -= 18
	}
	if reflection_like_result(text) {
		score += 18
	}
	if reflection_like_constraint_text(text) {
		score += 12
	}
	if reflection_like_artifact_text(text) {
		score += 12
	}
	if reflection_like_process_status_text(text) {
		score -= 22
	}
	if reflection_like_execution_context_text(text) {
		score -= 36
	}
	if text.contains('```') || text.contains('diff --git') {
		score -= 10
	}
	if text.count('\n') >= 3 {
		score += 6
	}
	return score
}

fn reflection_like_instruction(text string) bool {
	lower := text.to_lower()
	return lower.starts_with('提交') || lower.starts_with('修复') || lower.starts_with('增加')
		|| lower.starts_with('更新') || lower.starts_with('实现') || lower.starts_with('帮我')
		|| lower.starts_with('请') || lower.starts_with('继续') || lower.starts_with('先')
		|| lower.starts_with('把') || lower.ends_with('吧')
}

fn reflection_like_result(text string) bool {
	lower := text.to_lower()
	return lower.contains('已经') || lower.contains('改成') || lower.contains('改为')
		|| lower.contains('修复了') || lower.contains('支持') || lower.contains('通过')
		|| lower.contains('现在') || lower.contains('不再') || lower.contains('同步到')
		|| lower.contains('增加了') || lower.contains('更新了')
}

fn reflection_like_constraint_text(text string) bool {
	lower := text.to_lower()
	return lower.contains('不要') || lower.contains('不能') || lower.contains('不把')
		|| lower.contains('不得') || lower.contains('必须') || lower.contains('不需要')
}

fn reflection_like_artifact_text(text string) bool {
	return text.contains('`') || text.contains('@VMODROOT') || text.contains('::')
		|| text.contains('/') || text.contains('.v') || text.contains('.js') || text.contains('.ts')
		|| text.contains('.json') || text.contains('.md') || text.contains('_ROOT')
		|| text.contains('_PATH') || text.contains('VJSX_')
}

fn reflection_like_process_status_text(text string) bool {
	lower := text.to_lower()
	return lower.contains('验证通过') || lower.contains('测试已经启动')
		|| lower.contains('继续整理提交') || lower.contains('开始分支')
		|| lower.contains('推到远端') || lower.contains('提交并推')
		|| lower.contains('等待目标用例') || lower.contains('当前在 main')
		|| lower.contains('尚未推送的提交')
}

fn reflection_like_execution_update_text(text string) bool {
	lower := text.to_lower()
	return lower.contains('我会先') || lower.contains('我准备') || lower.contains('我先')
		|| lower.contains('接下来我会') || lower.contains('随后会')
		|| lower.contains('现在把') || lower.contains('我在等')
		|| lower.contains('我要开始') || lower.contains('准备直接')
		|| lower.contains('先把')
}

fn reflection_like_root_cause_text(text string) bool {
	lower := text.to_lower()
	return lower.contains('原因') || lower.contains('触发点')
		|| lower.contains('解释为什么') || lower.contains('说明这台机器')
		|| lower.contains('为什么你的') || lower.contains('定位到')
}

fn reflection_like_execution_context_text(text string) bool {
	lower := text.to_lower()
	return lower.contains('受限沙箱') || lower.contains('提权') || lower.contains('sandbox')
		|| lower.contains('git push 这一步需要提权') || lower.contains('申请权限')
		|| lower.contains('访问远端') || lower.contains('当前分支状态')
		|| lower.contains('当前在 main') || lower.contains('尚未推送的提交')
		|| lower.contains('git push') || lower.contains('push 到远端')
}

struct AgentViewNoopReflectionGenerator {}

fn (mut generator AgentViewNoopReflectionGenerator) generate(prompt string) !string {
	return prompt
}

pub fn (store PollyDbStore) ensure_search_schema() !bool {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	changed := db.register_or_update_table(entries_spec(true)!)!
	if changed {
		db.checkpoint()!
	}
	return changed
}

pub fn desired_search_index_names() ![]string {
	spec := entries_spec(true)!
	return spec.indexes.map(it.name)
}

pub fn desired_entries_search_spec() !storage.TypedTableSpec {
	return entries_spec(true)!
}

pub fn (store PollyDbStore) ensure_search_indexes() !bool {
	stats := store.ensure_search_indexes_with_progress_and_config(no_search_index_progress,
		storage.ChunkConfig.default())!
	return stats.changed
}

pub fn (store PollyDbStore) ensure_search_indexes_with_progress(reporter SearchIndexProgressReporter) !SearchIndexStats {
	return store.ensure_search_indexes_with_progress_and_config(reporter,
		storage.ChunkConfig.default())
}

pub fn (store PollyDbStore) ensure_search_indexes_with_progress_and_config(reporter SearchIndexProgressReporter, cfg storage.ChunkConfig) !SearchIndexStats {
	mut total_sw := time.new_stopwatch()
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	search_spec := entries_spec(true)!
	needs_markdown_backfill := spec_has_markdown_fts_index(search_spec)
	use_split_backed := cfg.enable_split_backed_working_set
		&& !search_spec.indexes.any(it.is_field_selector())
	effective_cfg := if use_split_backed {
		cfg
	} else {
		cfg.with_split_backed_working_set(false)
	}
	reporter(SearchIndexProgress{
		phase: 'start'
	})
	ingest_states := load_existing_ingest_states_by_path(mut db) or {
		map[string]IngestState{}
	}
	entry_ingest_states := load_all_entry_ingest_states(mut db) or {
		map[string]EntryIngestState{}
	}
	entry_search_states := load_all_entry_search_states(mut db) or {
		map[string]EntrySearchState{}
	}
	mut target_entry_ids := []string{}
	mut stale_entry_search_ids := []string{}
	mut session_ids := []string{}
	mut seen_session_ids := map[string]bool{}
	for _, ingest in ingest_states {
		if !seen_session_ids[ingest.session_id] {
			seen_session_ids[ingest.session_id] = true
			session_ids << ingest.session_id
		}
	}
	current_index_version := load_search_meta_value(mut db, 'index_version') or { '' }
	mut rebuild_ms := i64(0)
	changed := db.register_or_update_table(search_spec)!
	if changed {
		db.checkpoint()!
	}
	force_rebuild := current_index_version != search_index_version
	for entry_id, ingest in entry_ingest_states {
		search := entry_search_states[entry_id] or { EntrySearchState{} }
		if search.id.len > 0 && search.entry_hash == ingest.entry_hash {
			continue
		}
		target_entry_ids << entry_id
	}
	if force_rebuild {
		target_entry_ids = load_meta_markup_entry_ids(mut db) or { []string{} }
	}
	if !needs_markdown_backfill {
		target_entry_ids = []string{}
	}
	for entry_id in entry_search_states.keys() {
		if entry_id !in entry_ingest_states {
			stale_entry_search_ids << entry_id
		}
	}
	mut backfill_sw := time.new_stopwatch()
	backfill := if needs_markdown_backfill {
		backfill_search_markdown_for_entries_with_config(mut db, target_entry_ids, effective_cfg,
			force_rebuild)!
	} else {
		SearchBackfillResult{}
	}
	backfill_ms := backfill_sw.elapsed().milliseconds()
	reporter(SearchIndexProgress{
		phase:           'backfill'
		rows_scanned:    backfill.rows_scanned
		rows_backfilled: backfill.rows_backfilled
		backfill_ms:     backfill_ms
	})
	if (changed || force_rebuild) && store_branch in db.branch_names() {
		mut rebuild_sw := time.new_stopwatch()
		db.rebuild_fts_indexes_at_branch(store_branch, ['entries'])!
		rebuild_ms = rebuild_sw.elapsed().milliseconds()
		reporter(SearchIndexProgress{
			phase:           'rebuild'
			rows_scanned:    backfill.rows_scanned
			rows_backfilled: backfill.rows_backfilled
			backfill_ms:     backfill_ms
			rebuild_ms:      rebuild_ms
		})
	}
	if target_entry_ids.len > 0 || stale_entry_search_ids.len > 0 {
		write_entry_search_states(mut db, entry_ingest_states, target_entry_ids,
			stale_entry_search_ids, effective_cfg)!
	}
	if changed || force_rebuild || backfill.rows_backfilled > 0 || target_entry_ids.len > 0
		|| stale_entry_search_ids.len > 0 {
		write_search_states(mut db, ingest_states, session_ids)!
		write_search_meta_value(mut db, 'index_version', search_index_version)!
		db.checkpoint()!
	}
	stats := SearchIndexStats{
		rows_scanned:    backfill.rows_scanned
		rows_backfilled: backfill.rows_backfilled
		backfill_ms:     backfill_ms
		rebuild_ms:      rebuild_ms
		total_ms:        total_sw.elapsed().milliseconds()
		changed:         changed || force_rebuild || backfill.rows_scanned > 0
			|| stale_entry_search_ids.len > 0
	}
	reporter(SearchIndexProgress{
		phase:           'done'
		rows_scanned:    stats.rows_scanned
		rows_backfilled: stats.rows_backfilled
		backfill_ms:     stats.backfill_ms
		rebuild_ms:      stats.rebuild_ms
		total_ms:        stats.total_ms
	})
	return stats
}

fn spec_has_markdown_fts_index(spec storage.TypedTableSpec) bool {
	for index in spec.indexes {
		if !index.is_fts() {
			continue
		}
		column := spec.table.column(index.column) or { continue }
		if column.typ == .markdown_ {
			return true
		}
	}
	return false
}

pub fn (store PollyDbStore) sync_codex(codex_root string) !SyncStats {
	return store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{},
		no_sync_progress, storage.ChunkConfig.default())
}

pub fn (store PollyDbStore) sync_codex_with_progress(codex_root string, reporter SyncProgressReporter) !SyncStats {
	return store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{},
		reporter, storage.ChunkConfig.default())
}

pub fn (store PollyDbStore) sync_codex_with_progress_and_config(codex_root string, reporter SyncProgressReporter, cfg storage.ChunkConfig) !SyncStats {
	return store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{},
		reporter, cfg)
}

pub fn (store PollyDbStore) sync_codex_with_options_and_progress_and_config(codex_root string, options SyncOptions, reporter SyncProgressReporter, cfg storage.ChunkConfig) !SyncStats {
	return store.sync_codex_single_pass_with_options_and_progress_and_config(codex_root, options,
		reporter, cfg)
}

fn (store PollyDbStore) sync_codex_single_pass_with_options_and_progress_and_config(codex_root string, options SyncOptions, reporter SyncProgressReporter, cfg storage.ChunkConfig) !SyncStats {
	mut total_sw := time.new_stopwatch()
	mut paths := discover_codex_session_paths(codex_root)!
	paths.sort()
	paths.reverse_in_place()
	if paths.len == 0 {
		return SyncStats{}
	}
	mut title_by_id := load_codex_session_titles(codex_root)!
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	mut existing := map[string]SessionSummary{}
	mut existing_ingest := map[string]IngestState{}
	existing_resume := load_sync_resume_state(mut db, 'codex_sync') or { SyncResumeState{} }
	resume_anchor_present := existing_resume.last_completed_path.len > 0
		&& existing_resume.last_completed_path in paths
	if store_branch_exists(mut db) {
		existing = load_existing_sessions_by_id(mut db) or {
			map[string]SessionSummary{}
		}
		existing_ingest = load_existing_ingest_states_by_path(mut db) or {
			map[string]IngestState{}
		}
	}
	mut skipped := 0
	batch_sessions := if options.batch_sessions > 0 { options.batch_sessions } else { 0 }
	mut checkpoint_count := 0
	empty_markdown := ingest_markdown_for_store(mut db, '')!
	reporter(SyncProgress{
		total_sessions:    paths.len
		imported_sessions: 0
		imported_entries:  0
		skipped_sessions:  skipped
		checkpoint_count:  checkpoint_count
		batch_sessions:    batch_sessions
		phase:             'start'
	})
	mut entry_count := 0
	mut processed := 0
	mut imported := 0
	mut total_read_ms := i64(0)
	mut total_build_ms := i64(0)
	mut total_apply_ms := i64(0)
	mut total_tx_ms := i64(0)
	mut total_aggregate_ms := i64(0)
	mut total_fast_update_ms := i64(0)
	mut total_fast_update_can_ms := i64(0)
	mut total_fast_update_path_ms := i64(0)
	mut total_fast_update_encode_ms := i64(0)
	mut total_fast_update_replace_ms := i64(0)
	mut total_fallback_ms := i64(0)
	mut total_fallback_items_ms := i64(0)
	mut total_fallback_items_key_ms := i64(0)
	mut total_fallback_items_fill_ms := i64(0)
	mut total_fallback_ops_ms := i64(0)
	mut total_fallback_ops_key_ms := i64(0)
	mut total_fallback_ops_lookup_ms := i64(0)
	mut total_fallback_ops_encode_ms := i64(0)
	mut total_fallback_ops_state_ms := i64(0)
	mut total_fallback_ops_state_new_key_ms := i64(0)
	mut total_fallback_ops_state_item_ms := i64(0)
	mut total_fallback_ops_state_cache_ms := i64(0)
	mut total_fallback_ops_index_ms := i64(0)
	mut total_fallback_build_ms := i64(0)
	mut total_fallback_build_prepare_ms := i64(0)
	mut total_fallback_build_prepare_keys_ms := i64(0)
	mut total_fallback_build_prepare_keys_sort_ms := i64(0)
	mut total_fallback_build_prepare_keys_merge_ms := i64(0)
	mut total_fallback_build_prepare_rows_ms := i64(0)
	mut total_fallback_build_prepare_rows_key_ms := i64(0)
	mut total_fallback_build_prepare_rows_value_ms := i64(0)
	mut total_fallback_build_leaf_ms := i64(0)
	mut total_fallback_build_leaf_chunk_ms := i64(0)
	mut total_fallback_build_leaf_node_ms := i64(0)
	mut total_fallback_build_leaf_node_serialize_ms := i64(0)
	mut total_fallback_build_leaf_node_cid_ms := i64(0)
	mut total_fallback_build_leaf_node_add_ms := i64(0)
	mut total_fallback_build_internal_ms := i64(0)
	mut total_commit_ms := i64(0)
	mut total_checkpoint_ms := i64(0)
	mut total_flush_ms := i64(0)
	mut batch_imported := 0
	mut last_completed_path := existing_resume.last_completed_path
	mut last_completed_session_id := existing_resume.last_completed_session_id
	mut waiting_for_resume_anchor := resume_anchor_present
	mut stopped_after_batch := false
	use_split_group_commit := cfg.enable_split_backed_working_set && existing_ingest.len > 0
	mut seeded := store_branch_exists(mut db)
	mut active_group_commit := false
	mut session := storage.GroupCommitSession{}
	mut split_session := storage.SplitGroupCommitSession{}
	mut ingest_rows := map[string]storage.TypedRowData{}
	if seeded {
		if use_split_group_commit {
			split_session = db.begin_split_group_commit_session(storage.SessionOptions.for_branch(store_branch),
				storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512), cfg)!
		} else {
			session = db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
				storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
		}
		active_group_commit = true
	}
	for path in paths {
		if waiting_for_resume_anchor {
			skipped++
			processed++
			reached_anchor := path == existing_resume.last_completed_path
			reporter(SyncProgress{
				total_sessions:     paths.len
				processed_sessions: processed
				imported_sessions:  imported
				imported_entries:   entry_count
				skipped_sessions:   skipped
				checkpoint_count:   checkpoint_count
				batch_sessions:     batch_sessions
				session_id:         if reached_anchor {
					existing_resume.last_completed_session_id
				} else {
					''
				}
				phase:              'resume_skip'
			})
			if reached_anchor {
				waiting_for_resume_anchor = false
			}
			continue
		}
		fingerprint := current_source_fingerprint(path)
		mut summary := SessionSummary{}
		mut needs_import := true
		mut current := SessionSummary{}
		mut found_existing := false
		state := existing_ingest[path] or { IngestState{} }
		if state.path.len > 0 && state.source_mtime_unix == fingerprint.source_mtime_unix
			&& state.source_size_bytes == fingerprint.source_size_bytes {
			if candidate := existing[state.session_id] {
				skipped++
				processed++
				reporter(SyncProgress{
					total_sessions:     paths.len
					processed_sessions: processed
					imported_sessions:  imported
					imported_entries:   entry_count
					skipped_sessions:   skipped
					checkpoint_count:   checkpoint_count
					batch_sessions:     batch_sessions
					session_id:         candidate.id
					session_title:      candidate.title
					phase:              'skip'
				})
				continue
			}
		}
		candidate_id := if state.session_id.len > 0 {
			state.session_id
		} else {
			session_id_from_path(path)
		}
		if candidate := existing[candidate_id] {
			current = candidate
			found_existing = true
		} else if existing.len > 0 {
			summary = read_codex_session_summary(path, mut title_by_id)!
			if candidate := existing[summary.id] {
				current = candidate
				found_existing = true
			}
		}
		source_changed := !(state.path.len > 0
			&& state.source_mtime_unix == fingerprint.source_mtime_unix
			&& state.source_size_bytes == fingerprint.source_size_bytes)
		if found_existing && !source_changed {
			if summary.id.len == 0 {
				summary = read_codex_session_summary(path, mut title_by_id)!
			}
			if same_session_summary(current, summary) {
				needs_import = false
			}
		}
		if !needs_import {
			if summary.id.len > 0 {
				ingest_rows[path] = build_ingest_state_row(path, summary.id, fingerprint)
				existing_ingest[path] = IngestState{
					path:              path
					session_id:        summary.id
					source_mtime_unix: fingerprint.source_mtime_unix
					source_size_bytes: fingerprint.source_size_bytes
				}
			}
			skipped++
			processed++
			reporter(SyncProgress{
				total_sessions:     paths.len
				processed_sessions: processed
				imported_sessions:  imported
				imported_entries:   entry_count
				skipped_sessions:   skipped
				checkpoint_count:   checkpoint_count
				batch_sessions:     batch_sessions
				session_id:         summary.id
				session_title:      summary.title
				phase:              'skip'
			})
			continue
		}
		mut read_sw := time.new_stopwatch()
		transcript := read_codex_transcript(path, mut title_by_id)!
		read_ms := read_sw.elapsed().milliseconds()
		total_read_ms += read_ms
		summary = transcript.summary
		if !seeded {
			seed_store_branch(mut db, summary)!
			seeded = true
		}
		if !active_group_commit {
			if use_split_group_commit {
				split_session = db.begin_split_group_commit_session(storage.SessionOptions.for_branch(store_branch),
					storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512), cfg)!
			} else {
				session = db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
					storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
			}
			active_group_commit = true
		}
		reporter(SyncProgress{
			total_sessions:     paths.len
			processed_sessions: processed
			imported_sessions:  imported
			imported_entries:   entry_count
			skipped_sessions:   skipped
			session_id:         summary.id
			session_title:      summary.title
			phase:              'import'
			read_ms:            read_ms
		})
		mut build_sw := time.new_stopwatch()
		existing_entry_states := load_existing_entry_ingest_states_by_session(mut db, summary.id) or {
			map[string]EntryIngestState{}
		}
		mut session_rows := map[string]storage.TypedRowData{}
		session_rows[summary.id] = build_session_row(transcript.summary)
		mut entry_rows := map[string]storage.TypedRowData{}
		mut entry_state_rows := map[string]storage.TypedRowData{}
		mut seen_entry_ids := map[string]bool{}
		for entry in transcript.entries {
			entry_markdown := build_session_entry_markdown(mut db, entry, empty_markdown) or {
				empty_markdown
			}
			entry_id, row := build_session_entry_row(transcript.summary, entry, entry_markdown)
			entry_hash := fingerprint_session_entry_row(row)
			seen_entry_ids[entry_id] = true
			existing_entry_state := existing_entry_states[entry_id] or { EntryIngestState{} }
			if existing_entry_state.id.len > 0 && existing_entry_state.entry_hash == entry_hash {
				continue
			}
			entry_rows[entry_id] = row
			entry_state_rows[entry_id] = build_entry_ingest_state_row(entry_id, summary.id,
				entry_hash)
			entry_count++
		}
		mut stale_entry_ids := [][]u8{}
		for entry_id in existing_entry_states.keys() {
			if entry_id in seen_entry_ids {
				continue
			}
			stale_entry_ids << entry_id.bytes()
		}
		build_ms := build_sw.elapsed().milliseconds()
		total_build_ms += build_ms
		mut apply_sw := time.new_stopwatch()
		mut tx_ms := i64(0)
		mut aggregate_ms := i64(0)
		mut fast_update_ms := i64(0)
		mut fast_update_can_ms := i64(0)
		mut fast_update_path_ms := i64(0)
		mut fast_update_encode_ms := i64(0)
		mut fast_update_replace_ms := i64(0)
		mut fallback_ms := i64(0)
		mut fallback_items_ms := i64(0)
		mut fallback_items_key_ms := i64(0)
		mut fallback_items_fill_ms := i64(0)
		mut fallback_ops_ms := i64(0)
		mut fallback_ops_key_ms := i64(0)
		mut fallback_ops_lookup_ms := i64(0)
		mut fallback_ops_encode_ms := i64(0)
		mut fallback_ops_state_ms := i64(0)
		mut fallback_ops_state_new_key_ms := i64(0)
		mut fallback_ops_state_item_ms := i64(0)
		mut fallback_ops_state_cache_ms := i64(0)
		mut fallback_ops_index_ms := i64(0)
		mut fallback_build_ms := i64(0)
		mut fallback_build_prepare_ms := i64(0)
		mut fallback_build_prepare_keys_ms := i64(0)
		mut fallback_build_prepare_keys_sort_ms := i64(0)
		mut fallback_build_prepare_keys_merge_ms := i64(0)
		mut fallback_build_prepare_rows_ms := i64(0)
		mut fallback_build_prepare_rows_key_ms := i64(0)
		mut fallback_build_prepare_rows_value_ms := i64(0)
		mut fallback_build_leaf_ms := i64(0)
		mut fallback_build_leaf_chunk_ms := i64(0)
		mut fallback_build_leaf_node_ms := i64(0)
		mut fallback_build_leaf_node_serialize_ms := i64(0)
		mut fallback_build_leaf_node_cid_ms := i64(0)
		mut fallback_build_leaf_node_add_ms := i64(0)
		mut fallback_build_internal_ms := i64(0)
		mut commit_ms := i64(0)
		mut checkpoint_ms := i64(0)
		mut flush_ms := i64(0)
		if use_split_group_commit {
			if stale_entry_ids.len > 0 {
				delete_result := split_session.delete_rows(mut db, 'entries', stale_entry_ids, cfg,
					sync_meta('delete stale entries ${summary.id}'))!
				tx_ms += delete_result.group_commit.transaction_ms
				commit_ms += delete_result.group_commit.commit_ms
				checkpoint_ms += delete_result.group_commit.checkpoint_ms
				flush_ms += delete_result.group_commit.flush_ms
				entry_state_delete_result := split_session.delete_rows(mut db,
					'entry_ingest_state', stale_entry_ids, cfg,
					sync_meta('delete stale entry ingest state ${summary.id}'))!
				tx_ms += entry_state_delete_result.group_commit.transaction_ms
				commit_ms += entry_state_delete_result.group_commit.commit_ms
				checkpoint_ms += entry_state_delete_result.group_commit.checkpoint_ms
				flush_ms += entry_state_delete_result.group_commit.flush_ms
			}
			session_result := split_session.put_rows(mut db, 'sessions', session_rows, cfg,
				sync_meta('sync session ${summary.id}'))!
			tx_ms += session_result.group_commit.transaction_ms
			commit_ms += session_result.group_commit.commit_ms
			checkpoint_ms += session_result.group_commit.checkpoint_ms
			flush_ms += session_result.group_commit.flush_ms
			if entry_rows.len > 0 {
				entry_result := split_session.put_rows(mut db, 'entries', entry_rows, cfg,
					sync_meta('sync entries ${summary.id}'))!
				tx_ms += entry_result.group_commit.transaction_ms
				commit_ms += entry_result.group_commit.commit_ms
				checkpoint_ms += entry_result.group_commit.checkpoint_ms
				flush_ms += entry_result.group_commit.flush_ms
			}
			if entry_state_rows.len > 0 {
				entry_state_result := split_session.put_rows(mut db, 'entry_ingest_state',
					entry_state_rows, cfg, sync_meta('sync entry ingest state ${summary.id}'))!
				tx_ms += entry_state_result.group_commit.transaction_ms
				commit_ms += entry_state_result.group_commit.commit_ms
				checkpoint_ms += entry_state_result.group_commit.checkpoint_ms
				flush_ms += entry_state_result.group_commit.flush_ms
			}
		} else {
			if stale_entry_ids.len > 0 {
				delete_result := session.delete_rows(mut db, 'entries', stale_entry_ids, cfg,
					sync_meta('delete stale entries ${summary.id}'))!
				tx_ms += delete_result.group_commit.transaction_ms
				aggregate_ms += delete_result.timings.aggregate_ms
				fast_update_ms += delete_result.timings.fast_update_ms
				fast_update_can_ms += delete_result.timings.fast_update_can_ms
				fast_update_path_ms += delete_result.timings.fast_update_path_ms
				fast_update_encode_ms += delete_result.timings.fast_update_encode_ms
				fast_update_replace_ms += delete_result.timings.fast_update_replace_ms
				fallback_ms += delete_result.timings.fallback_ms
				fallback_items_ms += delete_result.timings.fallback_items_ms
				fallback_items_key_ms += delete_result.timings.fallback_items_key_ms
				fallback_items_fill_ms += delete_result.timings.fallback_items_fill_ms
				fallback_ops_ms += delete_result.timings.fallback_ops_ms
				fallback_ops_key_ms += delete_result.timings.fallback_ops_key_ms
				fallback_ops_lookup_ms += delete_result.timings.fallback_ops_lookup_ms
				fallback_ops_encode_ms += delete_result.timings.fallback_ops_encode_ms
				fallback_ops_state_ms += delete_result.timings.fallback_ops_state_ms
				fallback_ops_state_new_key_ms += delete_result.timings.fallback_ops_state_new_key_ms
				fallback_ops_state_item_ms += delete_result.timings.fallback_ops_state_item_ms
				fallback_ops_state_cache_ms += delete_result.timings.fallback_ops_state_cache_ms
				fallback_ops_index_ms += delete_result.timings.fallback_ops_index_ms
				fallback_build_ms += delete_result.timings.fallback_build_ms
				fallback_build_prepare_ms += delete_result.timings.fallback_build_prepare_ms
				fallback_build_prepare_keys_ms += delete_result.timings.fallback_build_prepare_keys_ms
				fallback_build_prepare_keys_sort_ms += delete_result.timings.fallback_build_prepare_keys_sort_ms
				fallback_build_prepare_keys_merge_ms += delete_result.timings.fallback_build_prepare_keys_merge_ms
				fallback_build_prepare_rows_ms += delete_result.timings.fallback_build_prepare_rows_ms
				fallback_build_prepare_rows_key_ms += delete_result.timings.fallback_build_prepare_rows_key_ms
				fallback_build_prepare_rows_value_ms += delete_result.timings.fallback_build_prepare_rows_value_ms
				fallback_build_leaf_ms += delete_result.timings.fallback_build_leaf_ms
				fallback_build_leaf_chunk_ms += delete_result.timings.fallback_build_leaf_chunk_ms
				fallback_build_leaf_node_ms += delete_result.timings.fallback_build_leaf_node_ms
				fallback_build_leaf_node_serialize_ms += delete_result.timings.fallback_build_leaf_node_serialize_ms
				fallback_build_leaf_node_cid_ms += delete_result.timings.fallback_build_leaf_node_cid_ms
				fallback_build_leaf_node_add_ms += delete_result.timings.fallback_build_leaf_node_add_ms
				fallback_build_internal_ms += delete_result.timings.fallback_build_internal_ms
				commit_ms += delete_result.group_commit.commit_ms
				checkpoint_ms += delete_result.group_commit.checkpoint_ms
				flush_ms += delete_result.group_commit.flush_ms
				entry_state_delete_result := session.delete_rows(mut db, 'entry_ingest_state',
					stale_entry_ids, cfg,
					sync_meta('delete stale entry ingest state ${summary.id}'))!
				tx_ms += entry_state_delete_result.group_commit.transaction_ms
				aggregate_ms += entry_state_delete_result.timings.aggregate_ms
				fast_update_ms += entry_state_delete_result.timings.fast_update_ms
				fast_update_can_ms += entry_state_delete_result.timings.fast_update_can_ms
				fast_update_path_ms += entry_state_delete_result.timings.fast_update_path_ms
				fast_update_encode_ms += entry_state_delete_result.timings.fast_update_encode_ms
				fast_update_replace_ms += entry_state_delete_result.timings.fast_update_replace_ms
				fallback_ms += entry_state_delete_result.timings.fallback_ms
				fallback_items_ms += entry_state_delete_result.timings.fallback_items_ms
				fallback_items_key_ms += entry_state_delete_result.timings.fallback_items_key_ms
				fallback_items_fill_ms += entry_state_delete_result.timings.fallback_items_fill_ms
				fallback_ops_ms += entry_state_delete_result.timings.fallback_ops_ms
				fallback_ops_key_ms += entry_state_delete_result.timings.fallback_ops_key_ms
				fallback_ops_lookup_ms += entry_state_delete_result.timings.fallback_ops_lookup_ms
				fallback_ops_encode_ms += entry_state_delete_result.timings.fallback_ops_encode_ms
				fallback_ops_state_ms += entry_state_delete_result.timings.fallback_ops_state_ms
				fallback_ops_state_new_key_ms += entry_state_delete_result.timings.fallback_ops_state_new_key_ms
				fallback_ops_state_item_ms += entry_state_delete_result.timings.fallback_ops_state_item_ms
				fallback_ops_state_cache_ms += entry_state_delete_result.timings.fallback_ops_state_cache_ms
				fallback_ops_index_ms += entry_state_delete_result.timings.fallback_ops_index_ms
				fallback_build_ms += entry_state_delete_result.timings.fallback_build_ms
				fallback_build_prepare_ms += entry_state_delete_result.timings.fallback_build_prepare_ms
				fallback_build_prepare_keys_ms += entry_state_delete_result.timings.fallback_build_prepare_keys_ms
				fallback_build_prepare_keys_sort_ms += entry_state_delete_result.timings.fallback_build_prepare_keys_sort_ms
				fallback_build_prepare_keys_merge_ms += entry_state_delete_result.timings.fallback_build_prepare_keys_merge_ms
				fallback_build_prepare_rows_ms += entry_state_delete_result.timings.fallback_build_prepare_rows_ms
				fallback_build_prepare_rows_key_ms += entry_state_delete_result.timings.fallback_build_prepare_rows_key_ms
				fallback_build_prepare_rows_value_ms += entry_state_delete_result.timings.fallback_build_prepare_rows_value_ms
				fallback_build_leaf_ms += entry_state_delete_result.timings.fallback_build_leaf_ms
				fallback_build_leaf_chunk_ms += entry_state_delete_result.timings.fallback_build_leaf_chunk_ms
				fallback_build_leaf_node_ms += entry_state_delete_result.timings.fallback_build_leaf_node_ms
				fallback_build_leaf_node_serialize_ms += entry_state_delete_result.timings.fallback_build_leaf_node_serialize_ms
				fallback_build_leaf_node_cid_ms += entry_state_delete_result.timings.fallback_build_leaf_node_cid_ms
				fallback_build_leaf_node_add_ms += entry_state_delete_result.timings.fallback_build_leaf_node_add_ms
				fallback_build_internal_ms += entry_state_delete_result.timings.fallback_build_internal_ms
				commit_ms += entry_state_delete_result.group_commit.commit_ms
				checkpoint_ms += entry_state_delete_result.group_commit.checkpoint_ms
				flush_ms += entry_state_delete_result.group_commit.flush_ms
			}
			session_result := session.put_rows(mut db, 'sessions', session_rows, cfg,
				sync_meta('sync session ${summary.id}'))!
			tx_ms += session_result.group_commit.transaction_ms
			aggregate_ms += session_result.timings.aggregate_ms
			fast_update_ms += session_result.timings.fast_update_ms
			fast_update_can_ms += session_result.timings.fast_update_can_ms
			fast_update_path_ms += session_result.timings.fast_update_path_ms
			fast_update_encode_ms += session_result.timings.fast_update_encode_ms
			fast_update_replace_ms += session_result.timings.fast_update_replace_ms
			fallback_ms += session_result.timings.fallback_ms
			fallback_items_ms += session_result.timings.fallback_items_ms
			fallback_items_key_ms += session_result.timings.fallback_items_key_ms
			fallback_items_fill_ms += session_result.timings.fallback_items_fill_ms
			fallback_ops_ms += session_result.timings.fallback_ops_ms
			fallback_ops_key_ms += session_result.timings.fallback_ops_key_ms
			fallback_ops_lookup_ms += session_result.timings.fallback_ops_lookup_ms
			fallback_ops_encode_ms += session_result.timings.fallback_ops_encode_ms
			fallback_ops_state_ms += session_result.timings.fallback_ops_state_ms
			fallback_ops_state_new_key_ms += session_result.timings.fallback_ops_state_new_key_ms
			fallback_ops_state_item_ms += session_result.timings.fallback_ops_state_item_ms
			fallback_ops_state_cache_ms += session_result.timings.fallback_ops_state_cache_ms
			fallback_ops_index_ms += session_result.timings.fallback_ops_index_ms
			fallback_build_ms += session_result.timings.fallback_build_ms
			fallback_build_prepare_ms += session_result.timings.fallback_build_prepare_ms
			fallback_build_prepare_keys_ms += session_result.timings.fallback_build_prepare_keys_ms
			fallback_build_prepare_keys_sort_ms += session_result.timings.fallback_build_prepare_keys_sort_ms
			fallback_build_prepare_keys_merge_ms += session_result.timings.fallback_build_prepare_keys_merge_ms
			fallback_build_prepare_rows_ms += session_result.timings.fallback_build_prepare_rows_ms
			fallback_build_prepare_rows_key_ms += session_result.timings.fallback_build_prepare_rows_key_ms
			fallback_build_prepare_rows_value_ms += session_result.timings.fallback_build_prepare_rows_value_ms
			fallback_build_leaf_ms += session_result.timings.fallback_build_leaf_ms
			fallback_build_leaf_chunk_ms += session_result.timings.fallback_build_leaf_chunk_ms
			fallback_build_leaf_node_ms += session_result.timings.fallback_build_leaf_node_ms
			fallback_build_leaf_node_serialize_ms += session_result.timings.fallback_build_leaf_node_serialize_ms
			fallback_build_leaf_node_cid_ms += session_result.timings.fallback_build_leaf_node_cid_ms
			fallback_build_leaf_node_add_ms += session_result.timings.fallback_build_leaf_node_add_ms
			fallback_build_internal_ms += session_result.timings.fallback_build_internal_ms
			commit_ms += session_result.group_commit.commit_ms
			checkpoint_ms += session_result.group_commit.checkpoint_ms
			flush_ms += session_result.group_commit.flush_ms
			if entry_rows.len > 0 {
				entry_result := session.put_rows(mut db, 'entries', entry_rows, cfg,
					sync_meta('sync entries ${summary.id}'))!
				tx_ms += entry_result.group_commit.transaction_ms
				aggregate_ms += entry_result.timings.aggregate_ms
				fast_update_ms += entry_result.timings.fast_update_ms
				fast_update_can_ms += entry_result.timings.fast_update_can_ms
				fast_update_path_ms += entry_result.timings.fast_update_path_ms
				fast_update_encode_ms += entry_result.timings.fast_update_encode_ms
				fast_update_replace_ms += entry_result.timings.fast_update_replace_ms
				fallback_ms += entry_result.timings.fallback_ms
				fallback_items_ms += entry_result.timings.fallback_items_ms
				fallback_items_key_ms += entry_result.timings.fallback_items_key_ms
				fallback_items_fill_ms += entry_result.timings.fallback_items_fill_ms
				fallback_ops_ms += entry_result.timings.fallback_ops_ms
				fallback_ops_key_ms += entry_result.timings.fallback_ops_key_ms
				fallback_ops_lookup_ms += entry_result.timings.fallback_ops_lookup_ms
				fallback_ops_encode_ms += entry_result.timings.fallback_ops_encode_ms
				fallback_ops_state_ms += entry_result.timings.fallback_ops_state_ms
				fallback_ops_state_new_key_ms += entry_result.timings.fallback_ops_state_new_key_ms
				fallback_ops_state_item_ms += entry_result.timings.fallback_ops_state_item_ms
				fallback_ops_state_cache_ms += entry_result.timings.fallback_ops_state_cache_ms
				fallback_ops_index_ms += entry_result.timings.fallback_ops_index_ms
				fallback_build_ms += entry_result.timings.fallback_build_ms
				fallback_build_prepare_ms += entry_result.timings.fallback_build_prepare_ms
				fallback_build_prepare_keys_ms += entry_result.timings.fallback_build_prepare_keys_ms
				fallback_build_prepare_keys_sort_ms += entry_result.timings.fallback_build_prepare_keys_sort_ms
				fallback_build_prepare_keys_merge_ms += entry_result.timings.fallback_build_prepare_keys_merge_ms
				fallback_build_prepare_rows_ms += entry_result.timings.fallback_build_prepare_rows_ms
				fallback_build_prepare_rows_key_ms += entry_result.timings.fallback_build_prepare_rows_key_ms
				fallback_build_prepare_rows_value_ms += entry_result.timings.fallback_build_prepare_rows_value_ms
				fallback_build_leaf_ms += entry_result.timings.fallback_build_leaf_ms
				fallback_build_leaf_chunk_ms += entry_result.timings.fallback_build_leaf_chunk_ms
				fallback_build_leaf_node_ms += entry_result.timings.fallback_build_leaf_node_ms
				fallback_build_leaf_node_serialize_ms += entry_result.timings.fallback_build_leaf_node_serialize_ms
				fallback_build_leaf_node_cid_ms += entry_result.timings.fallback_build_leaf_node_cid_ms
				fallback_build_leaf_node_add_ms += entry_result.timings.fallback_build_leaf_node_add_ms
				fallback_build_internal_ms += entry_result.timings.fallback_build_internal_ms
				commit_ms += entry_result.group_commit.commit_ms
				checkpoint_ms += entry_result.group_commit.checkpoint_ms
				flush_ms += entry_result.group_commit.flush_ms
			}
			if entry_state_rows.len > 0 {
				entry_state_result := session.put_rows(mut db, 'entry_ingest_state',
					entry_state_rows, cfg, sync_meta('sync entry ingest state ${summary.id}'))!
				tx_ms += entry_state_result.group_commit.transaction_ms
				aggregate_ms += entry_state_result.timings.aggregate_ms
				fast_update_ms += entry_state_result.timings.fast_update_ms
				fast_update_can_ms += entry_state_result.timings.fast_update_can_ms
				fast_update_path_ms += entry_state_result.timings.fast_update_path_ms
				fast_update_encode_ms += entry_state_result.timings.fast_update_encode_ms
				fast_update_replace_ms += entry_state_result.timings.fast_update_replace_ms
				fallback_ms += entry_state_result.timings.fallback_ms
				fallback_items_ms += entry_state_result.timings.fallback_items_ms
				fallback_items_key_ms += entry_state_result.timings.fallback_items_key_ms
				fallback_items_fill_ms += entry_state_result.timings.fallback_items_fill_ms
				fallback_ops_ms += entry_state_result.timings.fallback_ops_ms
				fallback_ops_key_ms += entry_state_result.timings.fallback_ops_key_ms
				fallback_ops_lookup_ms += entry_state_result.timings.fallback_ops_lookup_ms
				fallback_ops_encode_ms += entry_state_result.timings.fallback_ops_encode_ms
				fallback_ops_state_ms += entry_state_result.timings.fallback_ops_state_ms
				fallback_ops_state_new_key_ms += entry_state_result.timings.fallback_ops_state_new_key_ms
				fallback_ops_state_item_ms += entry_state_result.timings.fallback_ops_state_item_ms
				fallback_ops_state_cache_ms += entry_state_result.timings.fallback_ops_state_cache_ms
				fallback_ops_index_ms += entry_state_result.timings.fallback_ops_index_ms
				fallback_build_ms += entry_state_result.timings.fallback_build_ms
				fallback_build_prepare_ms += entry_state_result.timings.fallback_build_prepare_ms
				fallback_build_prepare_keys_ms += entry_state_result.timings.fallback_build_prepare_keys_ms
				fallback_build_prepare_keys_sort_ms += entry_state_result.timings.fallback_build_prepare_keys_sort_ms
				fallback_build_prepare_keys_merge_ms += entry_state_result.timings.fallback_build_prepare_keys_merge_ms
				fallback_build_prepare_rows_ms += entry_state_result.timings.fallback_build_prepare_rows_ms
				fallback_build_prepare_rows_key_ms += entry_state_result.timings.fallback_build_prepare_rows_key_ms
				fallback_build_prepare_rows_value_ms += entry_state_result.timings.fallback_build_prepare_rows_value_ms
				fallback_build_leaf_ms += entry_state_result.timings.fallback_build_leaf_ms
				fallback_build_leaf_chunk_ms += entry_state_result.timings.fallback_build_leaf_chunk_ms
				fallback_build_leaf_node_ms += entry_state_result.timings.fallback_build_leaf_node_ms
				fallback_build_leaf_node_serialize_ms += entry_state_result.timings.fallback_build_leaf_node_serialize_ms
				fallback_build_leaf_node_cid_ms += entry_state_result.timings.fallback_build_leaf_node_cid_ms
				fallback_build_leaf_node_add_ms += entry_state_result.timings.fallback_build_leaf_node_add_ms
				fallback_build_internal_ms += entry_state_result.timings.fallback_build_internal_ms
				commit_ms += entry_state_result.group_commit.commit_ms
				checkpoint_ms += entry_state_result.group_commit.checkpoint_ms
				flush_ms += entry_state_result.group_commit.flush_ms
			}
		}
		ingest_rows[path] = build_ingest_state_row(path, summary.id, fingerprint)
		existing_ingest[path] = IngestState{
			path:              path
			session_id:        summary.id
			source_mtime_unix: fingerprint.source_mtime_unix
			source_size_bytes: fingerprint.source_size_bytes
		}
		existing[summary.id] = summary
		apply_ms := apply_sw.elapsed().milliseconds()
		total_apply_ms += apply_ms
		total_tx_ms += tx_ms
		total_aggregate_ms += aggregate_ms
		total_fast_update_ms += fast_update_ms
		total_fast_update_can_ms += fast_update_can_ms
		total_fast_update_path_ms += fast_update_path_ms
		total_fast_update_encode_ms += fast_update_encode_ms
		total_fast_update_replace_ms += fast_update_replace_ms
		total_fallback_ms += fallback_ms
		total_fallback_items_ms += fallback_items_ms
		total_fallback_items_key_ms += fallback_items_key_ms
		total_fallback_items_fill_ms += fallback_items_fill_ms
		total_fallback_ops_ms += fallback_ops_ms
		total_fallback_ops_key_ms += fallback_ops_key_ms
		total_fallback_ops_lookup_ms += fallback_ops_lookup_ms
		total_fallback_ops_encode_ms += fallback_ops_encode_ms
		total_fallback_ops_state_ms += fallback_ops_state_ms
		total_fallback_ops_state_new_key_ms += fallback_ops_state_new_key_ms
		total_fallback_ops_state_item_ms += fallback_ops_state_item_ms
		total_fallback_ops_state_cache_ms += fallback_ops_state_cache_ms
		total_fallback_ops_index_ms += fallback_ops_index_ms
		total_fallback_build_ms += fallback_build_ms
		total_fallback_build_prepare_ms += fallback_build_prepare_ms
		total_fallback_build_prepare_keys_ms += fallback_build_prepare_keys_ms
		total_fallback_build_prepare_keys_sort_ms += fallback_build_prepare_keys_sort_ms
		total_fallback_build_prepare_keys_merge_ms += fallback_build_prepare_keys_merge_ms
		total_fallback_build_prepare_rows_ms += fallback_build_prepare_rows_ms
		total_fallback_build_prepare_rows_key_ms += fallback_build_prepare_rows_key_ms
		total_fallback_build_prepare_rows_value_ms += fallback_build_prepare_rows_value_ms
		total_fallback_build_leaf_ms += fallback_build_leaf_ms
		total_fallback_build_leaf_chunk_ms += fallback_build_leaf_chunk_ms
		total_fallback_build_leaf_node_ms += fallback_build_leaf_node_ms
		total_fallback_build_leaf_node_serialize_ms += fallback_build_leaf_node_serialize_ms
		total_fallback_build_leaf_node_cid_ms += fallback_build_leaf_node_cid_ms
		total_fallback_build_leaf_node_add_ms += fallback_build_leaf_node_add_ms
		total_fallback_build_internal_ms += fallback_build_internal_ms
		total_commit_ms += commit_ms
		total_checkpoint_ms += checkpoint_ms
		total_flush_ms += flush_ms
		reporter(SyncProgress{
			total_sessions:                        paths.len
			processed_sessions:                    processed
			imported_sessions:                     imported
			imported_entries:                      entry_count
			skipped_sessions:                      skipped
			checkpoint_count:                      checkpoint_count
			batch_sessions:                        batch_sessions
			session_id:                            summary.id
			session_title:                         summary.title
			phase:                                 'profile'
			read_ms:                               read_ms
			build_ms:                              build_ms
			apply_ms:                              apply_ms
			tx_ms:                                 tx_ms
			aggregate_ms:                          aggregate_ms
			fast_update_ms:                        fast_update_ms
			fast_update_can_ms:                    fast_update_can_ms
			fast_update_path_ms:                   fast_update_path_ms
			fast_update_encode_ms:                 fast_update_encode_ms
			fast_update_replace_ms:                fast_update_replace_ms
			fallback_ms:                           fallback_ms
			fallback_items_ms:                     fallback_items_ms
			fallback_items_key_ms:                 fallback_items_key_ms
			fallback_items_fill_ms:                fallback_items_fill_ms
			fallback_ops_ms:                       fallback_ops_ms
			fallback_ops_key_ms:                   fallback_ops_key_ms
			fallback_ops_lookup_ms:                fallback_ops_lookup_ms
			fallback_ops_encode_ms:                fallback_ops_encode_ms
			fallback_ops_state_ms:                 fallback_ops_state_ms
			fallback_ops_state_new_key_ms:         fallback_ops_state_new_key_ms
			fallback_ops_state_item_ms:            fallback_ops_state_item_ms
			fallback_ops_state_cache_ms:           fallback_ops_state_cache_ms
			fallback_ops_index_ms:                 fallback_ops_index_ms
			fallback_build_ms:                     fallback_build_ms
			fallback_build_prepare_ms:             fallback_build_prepare_ms
			fallback_build_prepare_keys_ms:        fallback_build_prepare_keys_ms
			fallback_build_prepare_keys_sort_ms:   fallback_build_prepare_keys_sort_ms
			fallback_build_prepare_keys_merge_ms:  fallback_build_prepare_keys_merge_ms
			fallback_build_prepare_rows_ms:        fallback_build_prepare_rows_ms
			fallback_build_prepare_rows_key_ms:    fallback_build_prepare_rows_key_ms
			fallback_build_prepare_rows_value_ms:  fallback_build_prepare_rows_value_ms
			fallback_build_leaf_ms:                fallback_build_leaf_ms
			fallback_build_leaf_chunk_ms:          fallback_build_leaf_chunk_ms
			fallback_build_leaf_node_ms:           fallback_build_leaf_node_ms
			fallback_build_leaf_node_serialize_ms: fallback_build_leaf_node_serialize_ms
			fallback_build_leaf_node_cid_ms:       fallback_build_leaf_node_cid_ms
			fallback_build_leaf_node_add_ms:       fallback_build_leaf_node_add_ms
			fallback_build_internal_ms:            fallback_build_internal_ms
			commit_ms:                             commit_ms
			checkpoint_ms:                         checkpoint_ms
			flush_ms:                              flush_ms
			total_ms:                              read_ms + build_ms + apply_ms
		})
		imported++
		processed++
		batch_imported++
		last_completed_path = path
		last_completed_session_id = summary.id
		if batch_sessions > 0 && batch_imported >= batch_sessions {
			flush_sync_batch(mut db, mut session, mut split_session, use_split_group_commit,
				ingest_rows, cfg)!
			ingest_rows = map[string]storage.TypedRowData{}
			batch_imported = 0
			active_group_commit = false
			checkpoint_count++
			write_sync_resume_state(mut db, SyncResumeState{
				name:                      'codex_sync'
				last_completed_path:       last_completed_path
				last_completed_session_id: last_completed_session_id
				completed_batches:         existing_resume.completed_batches + checkpoint_count
				completed_sessions:        existing_resume.completed_sessions + imported
			})!
			reporter(SyncProgress{
				total_sessions:     paths.len
				processed_sessions: processed
				imported_sessions:  imported
				imported_entries:   entry_count
				skipped_sessions:   skipped
				checkpoint_count:   checkpoint_count
				batch_sessions:     batch_sessions
				phase:              'checkpoint'
				checkpoint_ms:      total_checkpoint_ms
			})
			stopped_after_batch = true
			break
		}
	}
	mut finish_sw := time.new_stopwatch()
	if seeded && active_group_commit {
		if ingest_rows.len > 0 || batch_imported > 0 || imported == 0 {
			flush_sync_batch(mut db, mut session, mut split_session, use_split_group_commit,
				ingest_rows, cfg)!
			checkpoint_count++
			if imported > 0 {
				write_sync_resume_state(mut db, SyncResumeState{
					name:                      'codex_sync'
					last_completed_path:       last_completed_path
					last_completed_session_id: last_completed_session_id
					completed_batches:         existing_resume.completed_batches + checkpoint_count
					completed_sessions:        existing_resume.completed_sessions + imported
				})!
			}
		}
	}
	if !stopped_after_batch {
		clear_sync_resume_state(mut db, 'codex_sync')!
		last_completed_path = ''
		last_completed_session_id = ''
	}
	finish_ms := finish_sw.elapsed().milliseconds()
	reporter(SyncProgress{
		total_sessions:                        paths.len
		processed_sessions:                    processed
		imported_sessions:                     imported
		imported_entries:                      entry_count
		skipped_sessions:                      skipped
		checkpoint_count:                      checkpoint_count
		batch_sessions:                        batch_sessions
		phase:                                 'done'
		read_ms:                               total_read_ms
		build_ms:                              total_build_ms
		apply_ms:                              total_apply_ms
		tx_ms:                                 total_tx_ms
		aggregate_ms:                          total_aggregate_ms
		fast_update_ms:                        total_fast_update_ms
		fast_update_can_ms:                    total_fast_update_can_ms
		fast_update_path_ms:                   total_fast_update_path_ms
		fast_update_encode_ms:                 total_fast_update_encode_ms
		fast_update_replace_ms:                total_fast_update_replace_ms
		fallback_ms:                           total_fallback_ms
		fallback_items_ms:                     total_fallback_items_ms
		fallback_items_key_ms:                 total_fallback_items_key_ms
		fallback_items_fill_ms:                total_fallback_items_fill_ms
		fallback_ops_ms:                       total_fallback_ops_ms
		fallback_ops_key_ms:                   total_fallback_ops_key_ms
		fallback_ops_lookup_ms:                total_fallback_ops_lookup_ms
		fallback_ops_encode_ms:                total_fallback_ops_encode_ms
		fallback_ops_state_ms:                 total_fallback_ops_state_ms
		fallback_ops_state_new_key_ms:         total_fallback_ops_state_new_key_ms
		fallback_ops_state_item_ms:            total_fallback_ops_state_item_ms
		fallback_ops_state_cache_ms:           total_fallback_ops_state_cache_ms
		fallback_ops_index_ms:                 total_fallback_ops_index_ms
		fallback_build_ms:                     total_fallback_build_ms
		fallback_build_prepare_ms:             total_fallback_build_prepare_ms
		fallback_build_prepare_keys_ms:        total_fallback_build_prepare_keys_ms
		fallback_build_prepare_keys_sort_ms:   total_fallback_build_prepare_keys_sort_ms
		fallback_build_prepare_keys_merge_ms:  total_fallback_build_prepare_keys_merge_ms
		fallback_build_prepare_rows_ms:        total_fallback_build_prepare_rows_ms
		fallback_build_prepare_rows_key_ms:    total_fallback_build_prepare_rows_key_ms
		fallback_build_prepare_rows_value_ms:  total_fallback_build_prepare_rows_value_ms
		fallback_build_leaf_ms:                total_fallback_build_leaf_ms
		fallback_build_leaf_chunk_ms:          total_fallback_build_leaf_chunk_ms
		fallback_build_leaf_node_ms:           total_fallback_build_leaf_node_ms
		fallback_build_leaf_node_serialize_ms: total_fallback_build_leaf_node_serialize_ms
		fallback_build_leaf_node_cid_ms:       total_fallback_build_leaf_node_cid_ms
		fallback_build_leaf_node_add_ms:       total_fallback_build_leaf_node_add_ms
		fallback_build_internal_ms:            total_fallback_build_internal_ms
		commit_ms:                             total_commit_ms
		checkpoint_ms:                         total_checkpoint_ms
		flush_ms:                              total_flush_ms
		finish_ms:                             finish_ms
		total_ms:                              total_sw.elapsed().milliseconds()
	})
	return SyncStats{
		sessions:                              imported
		entries:                               entry_count
		skipped:                               skipped
		processed_sessions:                    processed
		total_sessions:                        paths.len
		paused_for_resume:                     stopped_after_batch
		resume_session_id:                     if stopped_after_batch {
			last_completed_session_id
		} else {
			''
		}
		resume_path:                           if stopped_after_batch {
			last_completed_path
		} else {
			''
		}
		read_ms:                               total_read_ms
		build_ms:                              total_build_ms
		apply_ms:                              total_apply_ms
		tx_ms:                                 total_tx_ms
		aggregate_ms:                          total_aggregate_ms
		fast_update_ms:                        total_fast_update_ms
		fast_update_can_ms:                    total_fast_update_can_ms
		fast_update_path_ms:                   total_fast_update_path_ms
		fast_update_encode_ms:                 total_fast_update_encode_ms
		fast_update_replace_ms:                total_fast_update_replace_ms
		fallback_ms:                           total_fallback_ms
		fallback_items_ms:                     total_fallback_items_ms
		fallback_items_key_ms:                 total_fallback_items_key_ms
		fallback_items_fill_ms:                total_fallback_items_fill_ms
		fallback_ops_ms:                       total_fallback_ops_ms
		fallback_ops_key_ms:                   total_fallback_ops_key_ms
		fallback_ops_lookup_ms:                total_fallback_ops_lookup_ms
		fallback_ops_encode_ms:                total_fallback_ops_encode_ms
		fallback_ops_state_ms:                 total_fallback_ops_state_ms
		fallback_ops_state_new_key_ms:         total_fallback_ops_state_new_key_ms
		fallback_ops_state_item_ms:            total_fallback_ops_state_item_ms
		fallback_ops_state_cache_ms:           total_fallback_ops_state_cache_ms
		fallback_ops_index_ms:                 total_fallback_ops_index_ms
		fallback_build_ms:                     total_fallback_build_ms
		fallback_build_prepare_ms:             total_fallback_build_prepare_ms
		fallback_build_prepare_keys_ms:        total_fallback_build_prepare_keys_ms
		fallback_build_prepare_keys_sort_ms:   total_fallback_build_prepare_keys_sort_ms
		fallback_build_prepare_keys_merge_ms:  total_fallback_build_prepare_keys_merge_ms
		fallback_build_prepare_rows_ms:        total_fallback_build_prepare_rows_ms
		fallback_build_prepare_rows_key_ms:    total_fallback_build_prepare_rows_key_ms
		fallback_build_prepare_rows_value_ms:  total_fallback_build_prepare_rows_value_ms
		fallback_build_leaf_ms:                total_fallback_build_leaf_ms
		fallback_build_leaf_chunk_ms:          total_fallback_build_leaf_chunk_ms
		fallback_build_leaf_node_ms:           total_fallback_build_leaf_node_ms
		fallback_build_leaf_node_serialize_ms: total_fallback_build_leaf_node_serialize_ms
		fallback_build_leaf_node_cid_ms:       total_fallback_build_leaf_node_cid_ms
		fallback_build_leaf_node_add_ms:       total_fallback_build_leaf_node_add_ms
		fallback_build_internal_ms:            total_fallback_build_internal_ms
		commit_ms:                             total_commit_ms
		checkpoint_ms:                         total_checkpoint_ms
		flush_ms:                              total_flush_ms
		finish_ms:                             finish_ms
		total_ms:                              total_sw.elapsed().milliseconds()
	}
}

fn flush_sync_batch(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, mut split_session storage.SplitGroupCommitSession, use_split_group_commit bool, ingest_rows map[string]storage.TypedRowData, cfg storage.ChunkConfig) ! {
	if use_split_group_commit {
		if ingest_rows.len > 0 {
			_ = split_session.put_rows(mut db, 'ingest_state', ingest_rows, cfg,
				sync_meta('sync ingest state'))!
		}
		split_session.finish(mut db)!
	} else {
		if ingest_rows.len > 0 {
			_ = session.put_rows(mut db, 'ingest_state', ingest_rows, cfg,
				sync_meta('sync ingest state'))!
		}
		session.finish(mut db)!
	}
	db.checkpoint()!
}

fn no_sync_progress(_ SyncProgress) {}

fn no_search_index_progress(_ SearchIndexProgress) {}

pub fn (store PollyDbStore) list_sessions(limit int) ![]SessionSummary {
	result := store.list_sessions_page(SessionListRequest{
		limit: limit
	})!
	return result.sessions
}

pub fn (store PollyDbStore) list_sessions_page(request SessionListRequest) !SessionListResult {
	return (store.list_sessions_page_explained(request)!).result
}

pub fn (mut store_session BrowserStoreSession) list_sessions_page_explained(request SessionListRequest) !SessionListExecution {
	mut total_sw := time.new_stopwatch()
	return list_sessions_page_in_session(mut store_session.db, store_session.session, request, storage.PersistentDatabaseOpenTimings{},
		0, mut total_sw)
}

pub fn (store PollyDbStore) list_sessions_page_explained(request SessionListRequest) !SessionListExecution {
	mut total_sw := time.new_stopwatch()
	open_result := storage.PersistentDatabase.open_profiled(store.root_dir, store_branch)!
	mut db := open_result.database
	defer {
		db.close() or {}
	}
	mut session_sw := time.new_stopwatch()
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	session_ms := session_sw.elapsed().milliseconds()
	return list_sessions_page_in_session(mut db, session, request, open_result.timings, session_ms, mut
		total_sw)!
}

fn list_sessions_page_in_session(mut db storage.PersistentDatabase, session storage.DatabaseSession, request SessionListRequest, open_timings storage.PersistentDatabaseOpenTimings, session_ms i64, mut total_sw time.StopWatch) !SessionListExecution {
	if request.query.len == 0 && request.cwd_prefix.len == 0 && request.source.len == 0
		&& request.include_archived {
		fetch_limit := max_int(request.offset + max_int(request.limit, 0),
			max_int(request.limit, 0))
		mut query_db := queryapi.open_database(db.root_dir, session.branch_name)!
		defer {
			query_db.close() or {}
		}
		query_session := query_db.begin_session(session.branch_name)!
		profile := queryapi.query_page_profiled(query_session, mut query_db, queryapi.Request{
			table_name:     'sessions'
			order_by:       queryapi.Order{
				column_name: 'updated_at'
				direction:   .desc
			}
			select_columns: session_summary_select_columns
			limit:          fetch_limit
		})!
		page := profile.page
		mut out := []SessionSummary{cap: page.rows.len}
		for row in page.rows {
			out << decode_session_summary_query(row)!
		}
		start := clamp_offset(request.offset, out.len)
		end := clamp_limit(start, request.limit, out.len)
		lower_bound_total := if page.cursor.has_more {
			request.offset + out.len + 1
		} else {
			out.len
		}
		return SessionListExecution{
			result:                 SessionListResult{
				total:    lower_bound_total
				sessions: out[start..end].clone()
			}
			explain:                explain_session_list_path(session.table_spec('sessions') or {
				storage.TypedTableSpec{}
			}, request)
			query:                  profile.timings
			open_ms:                open_timings.total_ms
			open_backends_ms:       open_timings.backends_ms
			open_catalog_ms:        open_timings.catalog_ms
			open_engine_ms:         open_timings.engine.total_ms
			open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
			open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
			open_node_store_ms:     open_timings.engine.repository.node_store_ms
			open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
			session_ms:             session_ms
			total_ms:               total_sw.elapsed().milliseconds()
		}
	}
	rows := load_session_list_rows(mut db, session)!
	mut out := []SessionSummary{cap: rows.len}
	for row in rows {
		out << decode_session_summary(row)!
	}
	if request.query.len > 0 || request.cwd_prefix.len > 0 || request.source.len > 0
		|| !request.include_archived {
		needle := request.query.to_lower()
		mut filtered := []SessionSummary{}
		for item in out {
			if !request.include_archived && item.archived {
				continue
			}
			if request.cwd_prefix.len > 0 && !item.cwd.starts_with(request.cwd_prefix) {
				continue
			}
			if request.source.len > 0 && item.source.to_lower() != request.source.to_lower() {
				continue
			}
			if needle.len > 0 {
				haystack := '${item.title}\n${item.cwd}\n${item.path}'.to_lower()
				if !haystack.contains(needle) {
					continue
				}
			}
			filtered << item
		}
		out = filtered.clone()
	}
	total := out.len
	start := clamp_offset(request.offset, total)
	end := clamp_limit(start, request.limit, total)
	return SessionListExecution{
		result:                 SessionListResult{
			total:    total
			sessions: out[start..end].clone()
		}
		explain:                explain_session_list_path(session.table_spec('sessions') or {
			storage.TypedTableSpec{}
		}, request)
		query:                  queryapi.ExecutionTimings{
			total_ms:      total_sw.elapsed().milliseconds()
			fetched_rows:  rows.len
			filtered_rows: out.len
			returned_rows: max_int(end - start, 0)
		}
		open_ms:                open_timings.total_ms
		open_backends_ms:       open_timings.backends_ms
		open_catalog_ms:        open_timings.catalog_ms
		open_engine_ms:         open_timings.engine.total_ms
		open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
		open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
		open_node_store_ms:     open_timings.engine.repository.node_store_ms
		open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
		session_ms:             session_ms
		total_ms:               total_sw.elapsed().milliseconds()
	}
}

pub fn (store PollyDbStore) explain_browser_queries(session_request SessionListRequest, transcript_request TranscriptRequest, search_request SearchRequest) !BrowserQueryExplain {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	sessions_spec := session.table_spec('sessions') or { storage.TypedTableSpec{} }
	entries_spec := session.table_spec('entries') or { storage.TypedTableSpec{} }
	return BrowserQueryExplain{
		sessions:   explain_session_list_path(sessions_spec, session_request)
		transcript: explain_transcript_path(entries_spec, transcript_request)
		search:     explain_search_path(entries_spec, search_request)
	}
}

fn recent_entry_rows(mut db storage.PersistentDatabase, session storage.DatabaseSession, recent_sessions int) ![]storage.TypedSchemaRow {
	mut session_rows := []storage.TypedSchemaRow{}
	sessions_spec := session.table_spec('sessions') or { storage.TypedTableSpec{} }
	if table_has_index(sessions_spec, 'updated_at_cover_idx') {
		session_rows = session.lookup_index_between_reverse_projected(mut db, 'sessions',
			'updated_at_cover_idx', session_list_min_updated_at, session_list_max_updated_at,
			recent_sessions, ['id', 'updated_at']) or { []storage.TypedSchemaRow{} }
	} else {
		session_rows = session.scan_table(mut db, 'sessions', 0)!
		session_rows.sort_with_compare(fn (a &storage.TypedSchemaRow, b &storage.TypedSchemaRow) int {
			a_updated := agentview_optional_row_string(*a, 'updated_at')
			b_updated := agentview_optional_row_string(*b, 'updated_at')
			if a_updated > b_updated {
				return -1
			}
			if a_updated < b_updated {
				return 1
			}
			return 0
		})
		if session_rows.len > recent_sessions {
			session_rows = session_rows[..recent_sessions].clone()
		}
	}
	if session_rows.len == 0 {
		return []storage.TypedSchemaRow{}
	}
	mut out := []storage.TypedSchemaRow{}
	for session_row in session_rows {
		session_id := agentview_required_row_string(session_row, 'id') or { continue }
		rows := if table_has_index(session.table_spec('entries') or { storage.TypedTableSpec{} },
			'entries_session_cover_idx')
		{
			session.lookup_index_projected(mut db, 'entries', 'entries_session_cover_idx',
				session_id, 0, ['id', 'timestamp']) or { []storage.TypedSchemaRow{} }
		} else if table_has_index(session.table_spec('entries') or { storage.TypedTableSpec{} },
			'entries_session_idx')
		{
			session.lookup_index_projected(mut db, 'entries', 'entries_session_idx', session_id, 0, [
				'id',
				'timestamp',
			]) or { []storage.TypedSchemaRow{} }
		} else {
			[]storage.TypedSchemaRow{}
		}
		for row in rows {
			out << row
		}
	}
	out.sort_with_compare(fn (a &storage.TypedSchemaRow, b &storage.TypedSchemaRow) int {
		a_ts := agentview_optional_row_string(*a, 'timestamp')
		b_ts := agentview_optional_row_string(*b, 'timestamp')
		if a_ts > b_ts {
			return -1
		}
		if a_ts < b_ts {
			return 1
		}
		a_id := agentview_optional_row_string(*a, 'id')
		b_id := agentview_optional_row_string(*b, 'id')
		if a_id < b_id {
			return -1
		}
		if a_id > b_id {
			return 1
		}
		return 0
	})
	return out
}

fn agentview_required_row_string(row storage.TypedSchemaRow, field string) !string {
	value := row.data.get(field) or { return error('missing required field: ${field}') }
	match value {
		string { return value }
		else { return error('field ${field} is not a string') }
	}
}

fn agentview_optional_row_string(row storage.TypedSchemaRow, field string) string {
	value := row.data.get(field) or { return '' }
	return match value {
		string { value }
		else { '' }
	}
}

fn load_session_list_rows(mut db storage.PersistentDatabase, session storage.DatabaseSession) ![]storage.TypedSchemaRow {
	spec := session.table_spec('sessions') or { storage.TypedTableSpec{} }
	if table_has_index(spec, 'updated_at_cover_idx') {
		mut rows := session.lookup_index_between(mut db, 'sessions', 'updated_at_cover_idx',
			session_list_min_updated_at, session_list_max_updated_at, 0)!
		rows.reverse_in_place()
		return rows
	}
	mut rows := session.scan_table(mut db, 'sessions', 0)!
	rows.sort_with_compare(fn (a &storage.TypedSchemaRow, b &storage.TypedSchemaRow) int {
		left := a.data.get('updated_at') or { storage.ColumnValue('') }
		right := b.data.get('updated_at') or { storage.ColumnValue('') }
		left_value := match left {
			string { left }
			else { '' }
		}

		right_value := match right {
			string { right }
			else { '' }
		}

		if left_value > right_value {
			return -1
		}
		if left_value < right_value {
			return 1
		}
		return 0
	})
	return rows
}

fn explain_session_list_path(spec storage.TypedTableSpec, request SessionListRequest) QueryPathExplain {
	if request.query.len == 0 && request.cwd_prefix.len == 0 && request.source.len == 0
		&& request.include_archived {
		return QueryPathExplain{
			strategy:   'query_order_desc_projected'
			index_name: 'updated_at_cover_idx'
			notes:      [
				'session list uses query_page(order_by updated_at desc) with covering projection',
			]
		}
	}
	if table_has_index(spec, 'updated_at_cover_idx') {
		mut notes := [
			'results are read from updated_at covering index and reversed to newest-first',
		]
		if request.query.len > 0 || request.cwd_prefix.len > 0 || request.source.len > 0
			|| !request.include_archived {
			notes << 'text/source/cwd/archived filters are applied in memory after indexed read'
		}
		return QueryPathExplain{
			strategy:   'index_between_reverse'
			index_name: 'updated_at_cover_idx'
			notes:      notes
		}
	}
	return QueryPathExplain{
		strategy:   'table_scan'
		index_name: ''
		notes:      ['sessions table is fully scanned and sorted in memory']
	}
}

fn explain_transcript_path(spec storage.TypedTableSpec, request TranscriptRequest) QueryPathExplain {
	if request.session_id.len == 0 {
		return QueryPathExplain{
			strategy:   'not_requested'
			index_name: ''
			notes:      ['no session_id provided']
		}
	}
	if table_has_index(spec, 'entries_session_cover_idx') {
		return QueryPathExplain{
			strategy:   'index_exact_projected'
			index_name: 'entries_session_cover_idx'
			notes:      [
				'entries are fetched by covering session_id index, then ordered by seq in memory',
			]
		}
	}
	if table_has_index(spec, 'entries_session_idx') {
		return QueryPathExplain{
			strategy:   'index_exact'
			index_name: 'entries_session_idx'
			notes:      [
				'entries are fetched by session_id index, then ordered by seq in memory',
			]
		}
	}
	return QueryPathExplain{
		strategy:   'table_scan'
		index_name: ''
		notes:      [
			'entries_session_idx is missing, transcript would require full scan',
		]
	}
}

fn explain_search_path(spec storage.TypedTableSpec, request SearchRequest) QueryPathExplain {
	terms := normalized_search_terms(request.query)
	if terms.len == 0 {
		return QueryPathExplain{
			strategy:   'not_requested'
			index_name: ''
			notes:      ['no search query provided']
		}
	}
	mut indexes := []string{}
	for index_name in agentview_general_fts_indexes {
		if table_has_index(spec, index_name) {
			indexes << index_name
		}
	}
	if indexes.len > 0 {
		return QueryPathExplain{
			strategy:   'general_fts_prefix'
			index_name: indexes.join(',')
			notes:      [
				'search uses general PollyDB FTS indexes backed by SQLite FTS5; if no indexed hits are found it returns no results',
			]
		}
	}
	return QueryPathExplain{
		strategy:   'no_fts_indexes'
		index_name: ''
		notes:      [
			'FTS indexes are missing, so browser search returns no results instead of scanning entries',
		]
	}
}

pub fn (store PollyDbStore) load_session(session_id string) !SessionTranscript {
	page := store.load_transcript_page(TranscriptRequest{
		session_id: session_id
		limit:      100000
	})!
	return SessionTranscript{
		summary: page.summary
		entries: page.entries
	}
}

pub fn (store PollyDbStore) load_transcript_page(request TranscriptRequest) !TranscriptPage {
	return (store.load_transcript_page_explained(request)!).result
}

pub fn (mut store_session BrowserStoreSession) load_transcript_page_explained(request TranscriptRequest) !TranscriptExecution {
	mut total_sw := time.new_stopwatch()
	return load_transcript_page_in_session(mut store_session.db, store_session.session, request, storage.PersistentDatabaseOpenTimings{},
		0, mut total_sw)
}

pub fn (store PollyDbStore) load_transcript_page_explained(request TranscriptRequest) !TranscriptExecution {
	mut total_sw := time.new_stopwatch()
	open_result := storage.PersistentDatabase.open_profiled(store.root_dir, store_branch)!
	mut db := open_result.database
	defer {
		db.close() or {}
	}
	mut session_sw := time.new_stopwatch()
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	session_ms := session_sw.elapsed().milliseconds()
	return load_transcript_page_in_session(mut db, session, request, open_result.timings,
		session_ms, mut total_sw)!
}

fn load_transcript_page_in_session(mut db storage.PersistentDatabase, session storage.DatabaseSession, request TranscriptRequest, open_timings storage.PersistentDatabaseOpenTimings, session_ms i64, mut total_sw time.StopWatch) !TranscriptExecution {
	mut summary_sw := time.new_stopwatch()
	session_row := session.get_row(mut db, 'sessions', request.session_id.bytes())!
	summary := decode_session_summary(session_row)!
	summary_lookup_ms := summary_sw.elapsed().milliseconds()
	mut index_sw := time.new_stopwatch()
	rows := if table_has_index(session.table_spec('entries') or { storage.TypedTableSpec{} },
		'entries_session_cover_idx')
	{
		session.lookup_index_projected(mut db, 'entries', 'entries_session_cover_idx',
			request.session_id, 0, transcript_entry_select_columns)!
	} else {
		session.lookup_index(mut db, 'entries', 'entries_session_idx', request.session_id, 0)!
	}
	index_lookup_ms := index_sw.elapsed().milliseconds()
	mut decode_sw := time.new_stopwatch()
	mut order_sw := time.new_stopwatch()
	mut entries := []SessionEntry{cap: rows.len}
	mut page_rows := []storage.TypedSchemaRow{}
	for row in rows {
		entries << decode_session_entry(row)!
		page_rows << row
	}
	decode_ms := decode_sw.elapsed().milliseconds()
	mut ordered := []SessionEntry{cap: entries.len}
	mut ordered_rows := []storage.TypedSchemaRow{cap: page_rows.len}
	mut order := []int{cap: entries.len}
	for idx in 0 .. entries.len {
		order << idx
	}
	order.sort_with_compare(fn [entries] (a &int, b &int) int {
		if entries[*a].seq < entries[*b].seq {
			return -1
		}
		if entries[*a].seq > entries[*b].seq {
			return 1
		}
		return 0
	})
	for idx in order {
		ordered << entries[idx]
		ordered_rows << page_rows[idx]
	}
	order_ms := order_sw.elapsed().milliseconds()
	total := ordered.len
	start := clamp_offset(request.offset, total)
	end := clamp_limit(start, request.limit, total)
	mut markdown_sw := time.new_stopwatch()
	mut page_entries := []SessionEntry{cap: max_int(end - start, 0)}
	for idx in start .. end {
		page_entries << decode_session_entry_with_markdown(mut db, ordered_rows[idx])!
	}
	markdown_ms := markdown_sw.elapsed().milliseconds()
	return TranscriptExecution{
		result:                 TranscriptPage{
			summary:       summary
			total_entries: total
			entries:       page_entries
		}
		explain:                explain_transcript_path(session.table_spec('entries') or {
			storage.TypedTableSpec{}
		}, request)
		open_ms:                open_timings.total_ms
		open_backends_ms:       open_timings.backends_ms
		open_catalog_ms:        open_timings.catalog_ms
		open_engine_ms:         open_timings.engine.total_ms
		open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
		open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
		open_node_store_ms:     open_timings.engine.repository.node_store_ms
		open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
		session_ms:             session_ms
		summary_lookup_ms:      summary_lookup_ms
		index_lookup_ms:        index_lookup_ms
		decode_ms:              decode_ms
		order_ms:               order_ms
		markdown_ms:            markdown_ms
		total_ms:               total_sw.elapsed().milliseconds()
	}
}

pub fn (store PollyDbStore) search(query string, limit int) ![]SearchHit {
	result := store.search_entries(SearchRequest{
		query: query
		limit: limit
	})!
	return result.hits
}

pub fn (store PollyDbStore) search_entries(request SearchRequest) !SearchResult {
	return (store.search_entries_explained(request)!).result
}

pub fn (mut store_session BrowserStoreSession) search_entries_explained(request SearchRequest) !SearchExecution {
	mut total_sw := time.new_stopwatch()
	query := request.query
	terms := normalized_search_terms(query)
	if terms.len == 0 {
		return SearchExecution{
			result:   SearchResult{}
			explain:  QueryPathExplain{
				strategy:   'not_requested'
				index_name: ''
				notes:      ['no search query provided']
			}
			total_ms: total_sw.elapsed().milliseconds()
		}
	}
	return search_entries_in_session(mut store_session.db, store_session.session, request, query,
		terms, storage.PersistentDatabaseOpenTimings{}, 0, mut total_sw)
}

pub fn (store PollyDbStore) search_entries_explained(request SearchRequest) !SearchExecution {
	mut total_sw := time.new_stopwatch()
	query := request.query
	terms := normalized_search_terms(query)
	if terms.len == 0 {
		return SearchExecution{
			result:   SearchResult{}
			explain:  QueryPathExplain{
				strategy:   'not_requested'
				index_name: ''
				notes:      ['no search query provided']
			}
			total_ms: total_sw.elapsed().milliseconds()
		}
	}
	open_result := storage.PersistentDatabase.open_profiled(store.root_dir, store_branch)!
	mut db := open_result.database
	defer {
		db.close() or {}
	}
	mut session_sw := time.new_stopwatch()
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	session_ms := session_sw.elapsed().milliseconds()
	return search_entries_in_session(mut db, session, request, query, terms, open_result.timings,
		session_ms, mut total_sw)!
}

fn search_entries_in_session(mut db storage.PersistentDatabase, session storage.DatabaseSession, request SearchRequest, query string, terms []string, open_timings storage.PersistentDatabaseOpenTimings, session_ms i64, mut total_sw time.StopWatch) !SearchExecution {
	mut session_summary_ms := i64(0)
	entries_spec := session.table_spec('entries') or { storage.TypedTableSpec{} }
	mut ranked := []RankedSearchHit{}
	mut seen := map[string]bool{}
	mut candidate_rows := []queryapi.QueryRow{}
	mut candidate_session_ids := []string{}
	mut seen_session_ids := map[string]bool{}
	mut used_fts := false
	mut fts_lookup_ms := i64(0)
	mut filter_rank_ms := i64(0)
	mut fts_pages := []queryapi.CursorPage{}
	for index_name in agentview_general_fts_indexes {
		if !table_has_index(entries_spec, index_name) {
			continue
		}
		used_fts = true
		mut lookup_sw := time.new_stopwatch()
		mut query_db := queryapi.open_database(db.root_dir, session.branch_name)!
		defer {
			query_db.close() or {}
		}
		query_session := query_db.begin_session(session.branch_name)!
		page := queryapi.query_page(query_session, mut query_db, queryapi.Request{
			table_name:     'entries'
			general_fts:    queryapi.GeneralFtsClause{
				index_name: index_name
				kind:       if terms.len > 1 {
					queryapi.FtsKind.all
				} else {
					queryapi.FtsKind.prefix
				}
				terms:      if terms.len > 1 { terms.clone() } else { [terms[0]] }
			}
			select_columns: [
				'id',
				'session_id',
				'session_title',
				'seq',
				'role',
				'kind',
				'tool_name',
				'title',
				'timestamp',
				'content_text',
			]
			limit:          search_candidate_fetch_limit(request)
		})!
		fts_lookup_ms += lookup_sw.elapsed().milliseconds()
		fts_pages << page
		if terms.len > 1 {
			break
		}
	}
	for page in fts_pages {
		for idx, row in page.rows {
			entry_id := must_string_query(row, 'id')!
			if seen[entry_id] {
				continue
			}
			seen[entry_id] = true
			candidate_rows << row
			session_id := entry_session_id_query(row)!
			if !seen_session_ids[session_id] {
				seen_session_ids[session_id] = true
				candidate_session_ids << session_id
			}
			_ = idx
		}
	}
	mut session_summaries := map[string]SessionSummary{}
	if candidate_session_ids.len > 0 {
		mut session_summary_sw := time.new_stopwatch()
		session_rows := session.get_rows_projected(mut db, 'sessions',
			candidate_session_ids.map(it.bytes()), session_summary_select_columns) or {
			[]storage.TypedSchemaRow{}
		}
		session_summary_ms = session_summary_sw.elapsed().milliseconds()
		for row in session_rows {
			summary := decode_session_summary(row) or { continue }
			session_summaries[summary.id] = summary
		}
	}
	if candidate_rows.len > 0 {
		mut general_fts_by_entry_id := map[string]queryapi.GeneralFtsHit{}
		for page in fts_pages {
			for idx, row in page.rows {
				if idx >= page.general_fts_hits.len {
					continue
				}
				entry_id := must_string_query(row, 'id') or { continue }
				if entry_id !in general_fts_by_entry_id {
					general_fts_by_entry_id[entry_id] = page.general_fts_hits[idx]
				}
			}
		}
		mut rank_sw := time.new_stopwatch()
		for row in candidate_rows {
			summary := session_summaries[entry_session_id_query(row)!] or { SessionSummary{} }
			if !search_request_matches_query_row_metadata(request, row, summary) {
				continue
			}
			entry_id := must_string_query(row, 'id')!
			fts_hit := general_fts_by_entry_id[entry_id] or { queryapi.GeneralFtsHit{} }
			ranked << RankedSearchHit{
				hit:   build_search_hit_query_row_with_snippet(row, summary, query, fts_hit.snippet)
				score: score_search_query_row_fts(query, terms, row, summary, fts_hit.score)
			}
		}
		filter_rank_ms += rank_sw.elapsed().milliseconds()
	}
	if ranked.len > 0 {
		mut paginate_sw := time.new_stopwatch()
		result := paginate_ranked_search_hits(ranked, request)
		paginate_ms := paginate_sw.elapsed().milliseconds()
		return SearchExecution{
			result:                 result
			explain:                QueryPathExplain{
				strategy:   'general_fts_prefix'
				index_name: if used_fts { agentview_general_fts_indexes.join(',') } else { '' }
				notes:      [
					'search returned indexed hits from the general PollyDB FTS path without table-scan fallback',
				]
			}
			open_ms:                open_timings.total_ms
			open_backends_ms:       open_timings.backends_ms
			open_catalog_ms:        open_timings.catalog_ms
			open_engine_ms:         open_timings.engine.total_ms
			open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
			open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
			open_node_store_ms:     open_timings.engine.repository.node_store_ms
			open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
			session_ms:             session_ms
			session_summary_ms:     session_summary_ms
			fts_lookup_ms:          fts_lookup_ms
			filter_rank_ms:         filter_rank_ms
			paginate_ms:            paginate_ms
			total_ms:               total_sw.elapsed().milliseconds()
		}
	}
	if request.session_id.len > 0 {
		mut fallback_sw := time.new_stopwatch()
		ranked = collect_session_local_search_hits(mut db, session, request, query, terms)!
		filter_rank_ms += fallback_sw.elapsed().milliseconds()
		if ranked.len > 0 {
			mut paginate_sw := time.new_stopwatch()
			result := paginate_ranked_search_hits(ranked, request)
			paginate_ms := paginate_sw.elapsed().milliseconds()
			return SearchExecution{
				result:                 result
				explain:                QueryPathExplain{
					strategy:   'session_index_substring'
					index_name: if table_has_index(entries_spec, 'entries_session_cover_idx') {
						'entries_session_cover_idx'
					} else {
						'entries_session_idx'
					}
					notes:      [
						'no FTS hits; search fell back to substring matching inside the current session only',
					]
				}
				open_ms:                open_timings.total_ms
				open_backends_ms:       open_timings.backends_ms
				open_catalog_ms:        open_timings.catalog_ms
				open_engine_ms:         open_timings.engine.total_ms
				open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
				open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
				open_node_store_ms:     open_timings.engine.repository.node_store_ms
				open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
				session_ms:             session_ms
				session_summary_ms:     session_summary_ms
				fts_lookup_ms:          fts_lookup_ms
				filter_rank_ms:         filter_rank_ms
				paginate_ms:            paginate_ms
				total_ms:               total_sw.elapsed().milliseconds()
			}
		}
	}
	if request.session_id.len == 0 && request.preferred_session_id.len > 0 {
		preferred_request := SearchRequest{
			query:                request.query
			session_id:           request.preferred_session_id
			preferred_session_id: ''
			cwd_prefix:           request.cwd_prefix
			source:               request.source
			kind:                 request.kind
			limit:                request.limit
			offset:               request.offset
		}
		mut preferred_sw := time.new_stopwatch()
		ranked =
			collect_session_local_search_hits(mut db, session, preferred_request, query, terms)!
		filter_rank_ms += preferred_sw.elapsed().milliseconds()
		if ranked.len > 0 {
			mut paginate_sw := time.new_stopwatch()
			result := paginate_ranked_search_hits(ranked, request)
			paginate_ms := paginate_sw.elapsed().milliseconds()
			return SearchExecution{
				result:                 result
				explain:                QueryPathExplain{
					strategy:   'preferred_session_substring'
					index_name: if table_has_index(entries_spec, 'entries_session_cover_idx') {
						'entries_session_cover_idx'
					} else {
						'entries_session_idx'
					}
					notes:      [
						'no FTS hits; search fell back to substring matching inside the currently open session',
					]
				}
				open_ms:                open_timings.total_ms
				open_backends_ms:       open_timings.backends_ms
				open_catalog_ms:        open_timings.catalog_ms
				open_engine_ms:         open_timings.engine.total_ms
				open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
				open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
				open_node_store_ms:     open_timings.engine.repository.node_store_ms
				open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
				session_ms:             session_ms
				session_summary_ms:     session_summary_ms
				fts_lookup_ms:          fts_lookup_ms
				filter_rank_ms:         filter_rank_ms
				paginate_ms:            paginate_ms
				total_ms:               total_sw.elapsed().milliseconds()
			}
		}
	}
	if request.session_id.len == 0 {
		mut recent_sw := time.new_stopwatch()
		ranked = collect_recent_session_body_search_hits(mut db, session, request, query, terms)!
		filter_rank_ms += recent_sw.elapsed().milliseconds()
		if ranked.len > 0 {
			mut paginate_sw := time.new_stopwatch()
			result := paginate_ranked_search_hits(ranked, request)
			paginate_ms := paginate_sw.elapsed().milliseconds()
			return SearchExecution{
				result:                 result
				explain:                QueryPathExplain{
					strategy:   'recent_sessions_substring'
					index_name: if table_has_index(entries_spec, 'entries_session_cover_idx') {
						'updated_at_cover_idx+entries_session_cover_idx'
					} else {
						'updated_at_cover_idx+entries_session_idx'
					}
					notes:      [
						'no FTS hits; search fell back to substring matching across recent session bodies',
					]
				}
				open_ms:                open_timings.total_ms
				open_backends_ms:       open_timings.backends_ms
				open_catalog_ms:        open_timings.catalog_ms
				open_engine_ms:         open_timings.engine.total_ms
				open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
				open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
				open_node_store_ms:     open_timings.engine.repository.node_store_ms
				open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
				session_ms:             session_ms
				session_summary_ms:     session_summary_ms
				fts_lookup_ms:          fts_lookup_ms
				filter_rank_ms:         filter_rank_ms
				paginate_ms:            paginate_ms
				total_ms:               total_sw.elapsed().milliseconds()
			}
		}
	}
	if request.session_id.len == 0 {
		mut metadata_sw := time.new_stopwatch()
		ranked = collect_session_metadata_search_hits(mut db, session, request, query, terms)!
		filter_rank_ms += metadata_sw.elapsed().milliseconds()
		if ranked.len > 0 {
			mut paginate_sw := time.new_stopwatch()
			result := paginate_ranked_search_hits(ranked, request)
			paginate_ms := paginate_sw.elapsed().milliseconds()
			return SearchExecution{
				result:                 result
				explain:                QueryPathExplain{
					strategy:   'session_metadata_substring'
					index_name: if table_has_index(session.table_spec('sessions') or {
						storage.TypedTableSpec{}
					}, 'updated_at_cover_idx')
					{
						'updated_at_cover_idx'
					} else {
						''
					}
					notes:      [
						'no FTS hits; search fell back to session title/cwd/source/path substring matching',
					]
				}
				open_ms:                open_timings.total_ms
				open_backends_ms:       open_timings.backends_ms
				open_catalog_ms:        open_timings.catalog_ms
				open_engine_ms:         open_timings.engine.total_ms
				open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
				open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
				open_node_store_ms:     open_timings.engine.repository.node_store_ms
				open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
				session_ms:             session_ms
				session_summary_ms:     session_summary_ms
				fts_lookup_ms:          fts_lookup_ms
				filter_rank_ms:         filter_rank_ms
				paginate_ms:            paginate_ms
				total_ms:               total_sw.elapsed().milliseconds()
			}
		}
	}
	return SearchExecution{
		result:                 SearchResult{}
		explain:                if used_fts {
			QueryPathExplain{
				strategy:   'fts_no_hits'
				index_name: agentview_general_fts_indexes.join(',')
				notes:      [
					'general FTS indexes were queried but returned no usable hits',
				]
			}
		} else {
			QueryPathExplain{
				strategy:   'no_fts_indexes'
				index_name: ''
				notes:      [
					'FTS indexes are missing, so browser search returned no results',
				]
			}
		}
		open_ms:                open_timings.total_ms
		open_backends_ms:       open_timings.backends_ms
		open_catalog_ms:        open_timings.catalog_ms
		open_engine_ms:         open_timings.engine.total_ms
		open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
		open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
		open_node_store_ms:     open_timings.engine.repository.node_store_ms
		open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
		session_ms:             session_ms
		session_summary_ms:     session_summary_ms
		fts_lookup_ms:          fts_lookup_ms
		filter_rank_ms:         filter_rank_ms
		total_ms:               total_sw.elapsed().milliseconds()
	}
}

fn search_candidate_fetch_limit(request SearchRequest) int {
	base := if request.limit > 0 {
		max_int((request.offset + request.limit) * 3, 24)
	} else {
		24
	}
	return min_int(base, 48)
}

fn collect_session_local_search_hits(mut db storage.PersistentDatabase, session storage.DatabaseSession, request SearchRequest, query string, terms []string) ![]RankedSearchHit {
	if request.session_id.len == 0 {
		return []RankedSearchHit{}
	}
	session_row := session.get_row(mut db, 'sessions', request.session_id.bytes()) or {
		return []RankedSearchHit{}
	}
	summary := decode_session_summary(session_row) or { return []RankedSearchHit{} }
	rows := if table_has_index(session.table_spec('entries') or { storage.TypedTableSpec{} },
		'entries_session_cover_idx')
	{
		session.lookup_index_projected(mut db, 'entries', 'entries_session_cover_idx',
			request.session_id, 0, [
			'id',
			'session_id',
			'session_title',
			'seq',
			'role',
			'kind',
			'tool_name',
			'title',
			'timestamp',
			'content_text',
		])!
	} else {
		session.lookup_index(mut db, 'entries', 'entries_session_idx', request.session_id, 0)!
	}
	mut ranked := []RankedSearchHit{}
	for row in rows {
		entry := decode_session_entry(row) or { continue }
		if !search_request_matches_entry(request, entry, summary, terms) {
			continue
		}
		ranked << RankedSearchHit{
			hit:   build_search_hit(row, entry, summary, query)
			score: score_search_entry(query, terms, entry, summary)
		}
	}
	return ranked
}

fn collect_session_metadata_search_hits(mut db storage.PersistentDatabase, session storage.DatabaseSession, request SearchRequest, query string, terms []string) ![]RankedSearchHit {
	rows := load_session_list_rows(mut db, session)!
	mut ranked := []RankedSearchHit{}
	for row in rows {
		summary := decode_session_summary(row) or { continue }
		if request.cwd_prefix.len > 0 && !summary.cwd.starts_with(request.cwd_prefix) {
			continue
		}
		if request.source.len > 0 && summary.source.to_lower() != request.source.to_lower() {
			continue
		}
		if request.kind.len > 0 && request.kind != 'all' {
			continue
		}
		haystack :=
			'${summary.title}\n${summary.cwd}\n${summary.source}\n${summary.path}'.to_lower()
		mut matched := true
		for term in terms {
			if !haystack.contains(term) {
				matched = false
				break
			}
		}
		if !matched {
			continue
		}
		ranked << RankedSearchHit{
			hit:   build_session_metadata_search_hit(summary, query)
			score: score_session_metadata_search_hit(query, terms, summary)
		}
	}
	return ranked
}

fn collect_recent_session_body_search_hits(mut db storage.PersistentDatabase, session storage.DatabaseSession, request SearchRequest, query string, terms []string) ![]RankedSearchHit {
	rows := load_session_list_rows(mut db, session)!
	mut ranked := []RankedSearchHit{}
	mut sessions_scanned := 0
	mut entries_scanned := 0
	max_sessions := 48
	max_entries := 4000
	for row in rows {
		if sessions_scanned >= max_sessions || entries_scanned >= max_entries {
			break
		}
		summary := decode_session_summary(row) or { continue }
		if request.cwd_prefix.len > 0 && !summary.cwd.starts_with(request.cwd_prefix) {
			continue
		}
		if request.source.len > 0 && summary.source.to_lower() != request.source.to_lower() {
			continue
		}
		session_request := SearchRequest{
			query:      query
			session_id: summary.id
			cwd_prefix: request.cwd_prefix
			source:     request.source
			kind:       request.kind
			limit:      request.limit
			offset:     0
		}
		hits := collect_session_local_search_hits(mut db, session, session_request, query, terms)!
		sessions_scanned++
		entries_scanned += max_int(hits.len, 1)
		ranked << hits
		if ranked.len >= max_int((request.offset + request.limit) * 3, 20) {
			break
		}
	}
	return ranked
}

fn table_has_index(spec storage.TypedTableSpec, index_name string) bool {
	for index in spec.indexes {
		if index.name == index_name {
			return true
		}
	}
	return false
}

struct RankedSearchHit {
	hit   SearchHit
	score int
}

struct IngestState {
	path              string
	session_id        string
	source_mtime_unix i64
	source_size_bytes i64
}

struct SearchState {
	session_id        string
	source_mtime_unix i64
	source_size_bytes i64
}

struct SyncResumeState {
	name                      string
	last_completed_path       string
	last_completed_session_id string
	completed_batches         int
	completed_sessions        int
}

struct EntryIngestState {
	id         string
	session_id string
	entry_hash string
}

struct EntrySearchState {
	id         string
	session_id string
	entry_hash string
}

struct SourceFingerprint {
	source_mtime_unix i64
	source_size_bytes i64
}

fn sessions_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('sessions', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('title', .string_, false)!,
		storage.ColumnDef.new('updated_at', .datetime_, false)!,
		storage.ColumnDef.new('started_at', .datetime_, true)!,
		storage.ColumnDef.new('cwd', .string_, true)!,
		storage.ColumnDef.new('source', .string_, true)!,
		storage.ColumnDef.new('originator', .string_, true)!,
		storage.ColumnDef.new('cli_version', .string_, true)!,
		storage.ColumnDef.new('path', .string_, false)!,
		storage.ColumnDef.new('archived', .bool_, false)!,
		storage.ColumnDef.new('entry_count', .i64_, false)!,
		storage.ColumnDef.new('user_turns', .i64_, false)!,
		storage.ColumnDef.new('tool_calls', .i64_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.new('updated_at_idx', 'updated_at')!,
		storage.SchemaIndexDef.covering('updated_at_cover_idx', 'updated_at')!,
		storage.SchemaIndexDef.new('path_idx', 'path')!,
	])!
}

fn ingest_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('ingest_state', [
		storage.ColumnDef.new('path', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('source_mtime_unix', .i64_, false)!,
		storage.ColumnDef.new('source_size_bytes', .i64_, false)!,
	], ['path'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.new('ingest_session_idx', 'session_id')!,
	])!
}

fn search_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('search_state', [
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('source_mtime_unix', .i64_, false)!,
		storage.ColumnDef.new('source_size_bytes', .i64_, false)!,
	], ['session_id'])!
	return storage.TypedTableSpec.new(table, []storage.SchemaIndexDef{})!
}

fn search_meta_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('search_meta_state', [
		storage.ColumnDef.new('name', .string_, false)!,
		storage.ColumnDef.new('value', .string_, false)!,
	], ['name'])!
	return storage.TypedTableSpec.new(table, []storage.SchemaIndexDef{})!
}

fn sync_resume_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('sync_resume_state', [
		storage.ColumnDef.new('name', .string_, false)!,
		storage.ColumnDef.new('last_completed_path', .string_, false)!,
		storage.ColumnDef.new('last_completed_session_id', .string_, false)!,
		storage.ColumnDef.new('completed_batches', .i64_, false)!,
		storage.ColumnDef.new('completed_sessions', .i64_, false)!,
	], ['name'])!
	return storage.TypedTableSpec.new(table, []storage.SchemaIndexDef{})!
}

fn entry_ingest_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('entry_ingest_state', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('entry_hash', .string_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.new('entry_ingest_session_idx', 'session_id')!,
	])!
}

fn entry_search_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('entry_search_state', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('entry_hash', .string_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.new('entry_search_session_idx', 'session_id')!,
	])!
}

fn entries_spec(include_search_indexes bool) !storage.TypedTableSpec {
	table := storage.TableDef.new('entries', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('session_title', .string_, false)!,
		storage.ColumnDef.new('seq', .i64_, false)!,
		storage.ColumnDef.new('timestamp', .datetime_, false)!,
		storage.ColumnDef.new('role', .string_, false)!,
		storage.ColumnDef.new('kind', .string_, false)!,
		storage.ColumnDef.new('tool_name', .string_, true)!,
		storage.ColumnDef.new('call_id', .string_, true)!,
		storage.ColumnDef.new('title', .string_, true)!,
		storage.ColumnDef.new('content_text', .string_, false)!,
		storage.ColumnDef.new('content_md', .markdown_, false)!,
		storage.ColumnDef.new('raw_type', .string_, true)!,
		storage.ColumnDef.new('phase', .string_, true)!,
	], ['id'])!
	mut indexes := [
		storage.SchemaIndexDef.new('entries_session_idx', 'session_id')!,
		storage.SchemaIndexDef.covering('entries_session_cover_idx', 'session_id')!,
		storage.SchemaIndexDef.new('entries_timestamp_idx', 'timestamp')!,
	]
	if include_search_indexes {
		indexes << storage.SchemaIndexDef.fts_with_options('entries_content_text_fts_idx',
			'content_text', storage.FtsIndexOptions{
			tokenizer:      'unicode61 remove_diacritics 2'
			prefix_lengths: [2, 3, 4]
		})!
	}
	return storage.TypedTableSpec.new(table, indexes)!
}

fn entries_memory_spec(include_search_indexes bool) !storage.TypedTableSpec {
	base := entries_spec(include_search_indexes)!
	mut indexes := base.indexes.clone()
	indexes << storage.SchemaIndexDef.embedding_markdown('entries_content_block_vec_idx',
		'content_md', memory.MarkdownEmbeddingScope.block, 'bge-small-zh-v1.5')!
	indexes << storage.SchemaIndexDef.embedding_markdown(agentview_memory_path_index, 'content_md',
		memory.MarkdownEmbeddingScope.path, 'bge-small-zh-v1.5')!
	return storage.TypedTableSpec.new(base.table, indexes)
}

fn ensure_agentview_memory_capability(mut db storage.PersistentDatabase) !bool {
	for capability in db.memory_capabilities_for_table(agentview_memory_capability_table) {
		if capability.column_name == agentview_memory_capability_column {
			return false
		}
	}
	db.register_memory_capability(storage.MemoryCapabilityDef.reflective_field(agentview_memory_capability_table,
		agentview_memory_capability_column, storage.ReflectionOptions{
		embedding_index: agentview_memory_path_index
		reflection_kind: 'summary'
	})!)!
	return true
}

fn put_session_summary(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, summary SessionSummary) ! {
	row := build_session_row(summary)
	_ = session.put_row(mut db, 'sessions', summary.id.bytes(), row, storage.ChunkConfig.default(),
		sync_meta('sync session ${summary.id}'))!
}

fn put_session_entry(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, summary SessionSummary, entry SessionEntry, empty_markdown storage.MarkdownRef) ! {
	entry_markdown := build_session_entry_markdown(mut db, entry, empty_markdown)!
	entry_id, row := build_session_entry_row(summary, entry, entry_markdown)
	_ = session.put_row(mut db, 'entries', entry_id.bytes(), row, storage.ChunkConfig.default(),
		sync_meta('sync entry ${entry_id}'))!
}

fn build_session_entry_markdown(mut db storage.PersistentDatabase, entry SessionEntry, empty_markdown storage.MarkdownRef) !storage.MarkdownRef {
	content_text := if entry.text.len > 0 { entry.text } else { entry.tool_name }
	if should_skip_markdown_index(entry, content_text) {
		return empty_markdown
	}
	return ingest_markdown_for_store(mut db, content_text)!
}

fn build_session_entry_row(summary SessionSummary, entry SessionEntry, empty_markdown storage.MarkdownRef) (string, storage.TypedRowData) {
	entry_id := '${summary.id}:${entry.seq}'
	mut row := storage.TypedRowData.new()
	row.set('id', entry_id)
	row.set('session_id', summary.id)
	row.set('session_title', summary.title)
	row.set('seq', i64(entry.seq))
	row.set('timestamp', if entry.timestamp.len > 0 { entry.timestamp } else { summary.updated_at })
	row.set('role', entry.role)
	row.set('kind', entry.kind.str())
	if entry.tool_name.len > 0 {
		row.set('tool_name', entry.tool_name)
	} else {
		row.set_null('tool_name')
	}
	if entry.call_id.len > 0 {
		row.set('call_id', entry.call_id)
	} else {
		row.set_null('call_id')
	}
	if entry.title.len > 0 {
		row.set('title', entry.title)
	} else {
		row.set_null('title')
	}
	content_text := if entry.text.len > 0 { entry.text } else { entry.tool_name }
	row.set('content_text', content_text)
	row.set('content_md', empty_markdown)
	if entry.raw_type.len > 0 {
		row.set('raw_type', entry.raw_type)
	} else {
		row.set_null('raw_type')
	}
	if entry.phase.len > 0 {
		row.set('phase', entry.phase)
	} else {
		row.set_null('phase')
	}
	return entry_id, row
}

fn should_skip_markdown_index(entry SessionEntry, content_text string) bool {
	if entry.kind in [.tool_call, .tool_result, .meta] {
		return true
	}
	if content_text.len > 32768 {
		return true
	}
	return likely_skip_memory_markdown_content(content_text)
}

fn likely_skip_memory_markdown_content(content_text string) bool {
	trimmed := content_text.trim_space()
	if trimmed.len == 0 {
		return true
	}
	if trimmed.starts_with('<environment_context>') || trimmed.contains('<cwd>')
		|| trimmed.contains('<shell>') || trimmed.contains('<timezone>')
		|| trimmed.contains('<current_date>') {
		return true
	}
	if trimmed.starts_with('<turn_aborted>') || trimmed.contains('::git-stage{')
		|| trimmed.contains('::git-commit{') || trimmed.contains('::git-push{')
		|| trimmed.contains('::git-create-branch{') || trimmed.contains('::git-create-pr{') {
		return true
	}
	return false
}

struct SearchBackfillResult {
	rows_scanned    int
	rows_backfilled int
}

fn backfill_search_markdown_for_entries(mut db storage.PersistentDatabase, entry_ids []string) !SearchBackfillResult {
	return backfill_search_markdown_for_entries_with_config(mut db, entry_ids,
		storage.ChunkConfig.default(), false)
}

fn backfill_search_markdown_for_entries_with_config(mut db storage.PersistentDatabase, entry_ids []string, cfg storage.ChunkConfig, force_reingest bool) !SearchBackfillResult {
	if !store_branch_exists(mut db) {
		return SearchBackfillResult{}
	}
	if entry_ids.len == 0 {
		return SearchBackfillResult{}
	}
	reader := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	use_split_group_commit := cfg.enable_split_backed_working_set
	mut session := storage.GroupCommitSession{}
	mut split_session := storage.SplitGroupCommitSession{}
	if use_split_group_commit {
		split_session = db.begin_split_group_commit_session(storage.SessionOptions.for_branch(store_branch),
			storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512), cfg)!
	} else {
		session = db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
			storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	}
	mut updated := 0
	mut scanned := 0
	for entry_id in entry_ids {
		memory_distill_progress('markdown backfill row ${scanned + 1}/${entry_ids.len} key=${entry_id}')
		row := reader.get_row(mut db, 'entries', entry_id.bytes()) or { continue }
		scanned++
		entry := decode_session_entry(row) or { continue }
		if should_skip_markdown_index(entry, entry.text) {
			continue
		}
		current_ref := opt_markdown_ref(row, 'content_md') or { storage.MarkdownRef{} }
		if current_ref.source_len > 0 && !force_reingest {
			continue
		}
		next_ref := ingest_markdown_for_store(mut db, entry.text) or { continue }
		memory_distill_progress('markdown ingested key=${entry_id} bytes=${next_ref.source_len}')
		mut next_row := row.data
		next_row.set('content_md', next_ref)
		if use_split_group_commit {
			_ = split_session.put_row(mut db, 'entries', row.primary_key, next_row, cfg,
				sync_meta('backfill markdown ${row.primary_key.bytestr()}'))!
		} else {
			_ = session.put_row(mut db, 'entries', row.primary_key, next_row,
				storage.ChunkConfig.default(),
				sync_meta('backfill markdown ${row.primary_key.bytestr()}'))!
		}
		memory_distill_progress('markdown queued key=${entry_id}')
		updated++
	}
	if updated > 0 {
		memory_distill_progress('markdown backfill finish updated=${updated}')
		if use_split_group_commit {
			split_session.finish(mut db)!
		} else {
			session.finish(mut db)!
		}
		memory_distill_progress('markdown backfill committed updated=${updated}')
	}
	return SearchBackfillResult{
		rows_scanned:    scanned
		rows_backfilled: updated
	}
}

fn ingest_markdown_for_store(mut db storage.PersistentDatabase, text string) !storage.MarkdownRef {
	stored := storage.ingest_external_field_value(mut db, storage.ColumnDef.new('content_md',
		.markdown_, false)!, text)!
	return match stored {
		storage.MarkdownRef { stored }
		else { return error('expected markdown ref from external storage ingest') }
	}
}

fn sync_meta(message string) storage.CommitMeta {
	return storage.CommitMeta{
		author:    'agentview'
		message:   message
		timestamp: 0
	}
}

fn store_branch_exists(mut db storage.PersistentDatabase) bool {
	return store_branch in db.branch_names()
}

fn seed_store_branch(mut db storage.PersistentDatabase, summary SessionSummary) ! {
	spec := sessions_spec()!
	cfg := storage.ChunkConfig.default()
	codec := storage.TypedRowCodec.new(spec.table)
	row := build_session_row(summary)
	table_view := storage.TableView.new(storage.Tree{}, 'sessions')
	mut tree := storage.Tree.build([
		storage.KVPair{
			key:   table_view.row_key(summary.id.bytes())
			value: codec.encode(row)!
		},
	], cfg)!
	tree = storage.rebuild_typed_indexes_for_specs(tree, [spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entries_spec(false)!], cfg)!
	tree = storage.rebuild_typed_aggregates_for_specs(tree, [spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entries_spec(false)!], cfg)!
	_ = db.commit_to_branch(store_branch, tree, storage.CommitMeta{
		author:    'agentview'
		message:   'seed agentview store'
		timestamp: 0
	})!
}

fn current_source_fingerprint(path string) SourceFingerprint {
	return SourceFingerprint{
		source_mtime_unix: os.file_last_mod_unix(path)
		source_size_bytes: i64(os.file_size(path))
	}
}

fn build_ingest_state_row(path string, session_id string, fingerprint SourceFingerprint) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('path', path)
	row.set('session_id', session_id)
	row.set('source_mtime_unix', fingerprint.source_mtime_unix)
	row.set('source_size_bytes', fingerprint.source_size_bytes)
	return row
}

fn build_search_state_row(session_id string, fingerprint SourceFingerprint) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('session_id', session_id)
	row.set('source_mtime_unix', fingerprint.source_mtime_unix)
	row.set('source_size_bytes', fingerprint.source_size_bytes)
	return row
}

fn build_entry_ingest_state_row(entry_id string, session_id string, entry_hash string) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('id', entry_id)
	row.set('session_id', session_id)
	row.set('entry_hash', entry_hash)
	return row
}

fn build_entry_search_state_row(entry_id string, session_id string, entry_hash string) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('id', entry_id)
	row.set('session_id', session_id)
	row.set('entry_hash', entry_hash)
	return row
}

fn build_search_meta_state_row(name string, value string) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('name', name)
	row.set('value', value)
	return row
}

fn fingerprint_session_entry_row(row storage.TypedRowData) string {
	mut parts := []string{}
	for column in ['id', 'session_id', 'session_title', 'seq', 'timestamp', 'role', 'kind',
		'tool_name', 'call_id', 'title', 'content_text', 'raw_type', 'phase'] {
		value := row.get(column) or { storage.NullValue{} }
		parts << '${value}'
	}
	return storage.chunk_cid_hex(parts.join('\n').bytes())
}

fn decode_session_summary(row storage.TypedSchemaRow) !SessionSummary {
	return SessionSummary{
		id:          must_string(row, 'id')!
		title:       must_string(row, 'title')!
		updated_at:  must_string(row, 'updated_at')!
		started_at:  opt_string(row, 'started_at')
		cwd:         opt_string(row, 'cwd')
		source:      opt_string(row, 'source')
		originator:  opt_string(row, 'originator')
		cli_version: opt_string(row, 'cli_version')
		path:        must_string(row, 'path')!
		archived:    must_bool(row, 'archived')!
		entry_count: int(must_i64(row, 'entry_count')!)
		user_turns:  int(must_i64(row, 'user_turns')!)
		tool_calls:  int(must_i64(row, 'tool_calls')!)
	}
}

fn decode_session_summary_query(row queryapi.QueryRow) !SessionSummary {
	return SessionSummary{
		id:          must_string_query(row, 'id')!
		title:       must_string_query(row, 'title')!
		updated_at:  must_string_query(row, 'updated_at')!
		started_at:  opt_string_query(row, 'started_at')
		cwd:         opt_string_query(row, 'cwd')
		source:      opt_string_query(row, 'source')
		originator:  opt_string_query(row, 'originator')
		cli_version: opt_string_query(row, 'cli_version')
		path:        must_string_query(row, 'path')!
		archived:    must_bool_query(row, 'archived')!
		entry_count: int(must_i64_query(row, 'entry_count')!)
		user_turns:  int(must_i64_query(row, 'user_turns')!)
		tool_calls:  int(must_i64_query(row, 'tool_calls')!)
	}
}

fn load_existing_sessions_by_id(mut db storage.PersistentDatabase) !map[string]SessionSummary {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'sessions', 0)!
	mut out := map[string]SessionSummary{}
	for row in rows {
		summary := decode_session_summary(row)!
		out[summary.id] = summary
	}
	return out
}

fn decode_ingest_state(row storage.TypedSchemaRow) !IngestState {
	return IngestState{
		path:              must_string(row, 'path')!
		session_id:        must_string(row, 'session_id')!
		source_mtime_unix: must_i64(row, 'source_mtime_unix')!
		source_size_bytes: must_i64(row, 'source_size_bytes')!
	}
}

fn load_existing_ingest_states_by_path(mut db storage.PersistentDatabase) !map[string]IngestState {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'ingest_state', 0) or { return map[string]IngestState{} }
	mut out := map[string]IngestState{}
	for row in rows {
		state := decode_ingest_state(row) or { continue }
		out[state.path] = state
	}
	return out
}

fn decode_search_state(row storage.TypedSchemaRow) !SearchState {
	return SearchState{
		session_id:        must_string(row, 'session_id')!
		source_mtime_unix: must_i64(row, 'source_mtime_unix')!
		source_size_bytes: must_i64(row, 'source_size_bytes')!
	}
}

fn decode_entry_ingest_state(row storage.TypedSchemaRow) !EntryIngestState {
	return EntryIngestState{
		id:         must_string(row, 'id')!
		session_id: must_string(row, 'session_id')!
		entry_hash: must_string(row, 'entry_hash')!
	}
}

fn decode_entry_search_state(row storage.TypedSchemaRow) !EntrySearchState {
	return EntrySearchState{
		id:         must_string(row, 'id')!
		session_id: must_string(row, 'session_id')!
		entry_hash: must_string(row, 'entry_hash')!
	}
}

fn load_existing_search_states_by_session(mut db storage.PersistentDatabase) !map[string]SearchState {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'search_state', 0) or { return map[string]SearchState{} }
	mut out := map[string]SearchState{}
	for row in rows {
		state := decode_search_state(row) or { continue }
		out[state.session_id] = state
	}
	return out
}

fn load_search_meta_value(mut db storage.PersistentDatabase, name string) !string {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	row := session.get_row(mut db, 'search_meta_state', name.bytes()) or { return '' }
	return must_string(row, 'value')!
}

fn write_search_meta_value(mut db storage.PersistentDatabase, name string, value string) ! {
	mut session := db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
		storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	_ = session.put_row(mut db, 'search_meta_state', name.bytes(), build_search_meta_state_row(name,
		value), storage.ChunkConfig.default(), sync_meta('sync search meta ${name}'))!
	session.finish(mut db)!
}

fn build_sync_resume_state_row(state SyncResumeState) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('name', state.name)
	row.set('last_completed_path', state.last_completed_path)
	row.set('last_completed_session_id', state.last_completed_session_id)
	row.set('completed_batches', i64(state.completed_batches))
	row.set('completed_sessions', i64(state.completed_sessions))
	return row
}

fn decode_sync_resume_state(row storage.TypedSchemaRow) !SyncResumeState {
	return SyncResumeState{
		name:                      must_string(row, 'name')!
		last_completed_path:       must_string(row, 'last_completed_path')!
		last_completed_session_id: must_string(row, 'last_completed_session_id')!
		completed_batches:         int(must_i64(row, 'completed_batches')!)
		completed_sessions:        int(must_i64(row, 'completed_sessions')!)
	}
}

fn load_sync_resume_state(mut db storage.PersistentDatabase, name string) !SyncResumeState {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	row := session.get_row(mut db, 'sync_resume_state', name.bytes()) or {
		return SyncResumeState{}
	}
	return decode_sync_resume_state(row)!
}

fn write_sync_resume_state(mut db storage.PersistentDatabase, state SyncResumeState) ! {
	if state.name.len == 0 {
		return
	}
	mut session := db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
		storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	_ = session.put_row(mut db, 'sync_resume_state', state.name.bytes(),
		build_sync_resume_state_row(state), storage.ChunkConfig.default(),
		sync_meta('sync resume state ${state.name}'))!
	session.finish(mut db)!
}

fn clear_sync_resume_state(mut db storage.PersistentDatabase, name string) ! {
	if name.len == 0 {
		return
	}
	mut session := db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
		storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	_ = session.delete_row(mut db, 'sync_resume_state', name.bytes(),
		storage.ChunkConfig.default(), sync_meta('clear resume state ${name}'))!
	session.finish(mut db)!
}

fn load_existing_entry_ingest_states_by_session(mut db storage.PersistentDatabase, session_id string) !map[string]EntryIngestState {
	if session_id.len == 0 {
		return map[string]EntryIngestState{}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.lookup_index(mut db, 'entry_ingest_state', 'entry_ingest_session_idx',
		session_id, 0) or { return map[string]EntryIngestState{} }
	mut out := map[string]EntryIngestState{}
	for row in rows {
		state := decode_entry_ingest_state(row) or { continue }
		out[state.id] = state
	}
	return out
}

fn load_all_entry_ingest_states(mut db storage.PersistentDatabase) !map[string]EntryIngestState {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'entry_ingest_state', 0) or {
		return map[string]EntryIngestState{}
	}
	mut out := map[string]EntryIngestState{}
	for row in rows {
		state := decode_entry_ingest_state(row) or { continue }
		out[state.id] = state
	}
	return out
}

fn load_all_entry_ids(mut db storage.PersistentDatabase) ![]string {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'entries', 0) or { return []string{} }
	mut out := []string{cap: rows.len}
	for row in rows {
		entry_id := must_string(row, 'id') or { continue }
		out << entry_id
	}
	return out
}

fn load_meta_markup_entry_ids(mut db storage.PersistentDatabase) ![]string {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'entries', 0) or { return []string{} }
	mut out := []string{}
	for row in rows {
		entry_id := must_string(row, 'id') or { continue }
		content_text := must_string(row, 'content_text') or { continue }
		if likely_needs_meta_fts_reingest(content_text) {
			out << entry_id
		}
	}
	return out
}

fn likely_needs_meta_fts_reingest(content_text string) bool {
	if content_text.len == 0 {
		return false
	}
	if !content_text.contains('<') || !content_text.contains('>') {
		return false
	}
	return content_text.contains('</') || content_text.contains('/>')
		|| content_text.contains('<cwd>') || content_text.contains('<shell>')
		|| content_text.contains('<environment_context>')
}

fn load_all_entry_search_states(mut db storage.PersistentDatabase) !map[string]EntrySearchState {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'entry_search_state', 0) or {
		return map[string]EntrySearchState{}
	}
	mut out := map[string]EntrySearchState{}
	for row in rows {
		state := decode_entry_search_state(row) or { continue }
		out[state.id] = state
	}
	return out
}

fn write_search_states(mut db storage.PersistentDatabase, ingest_states map[string]IngestState, session_ids []string) ! {
	if session_ids.len == 0 {
		return
	}
	mut seen := map[string]bool{}
	mut rows := map[string]storage.TypedRowData{}
	for _, ingest in ingest_states {
		if ingest.session_id.len == 0 || ingest.session_id !in session_ids
			|| seen[ingest.session_id] {
			continue
		}
		rows[ingest.session_id] = build_search_state_row(ingest.session_id, SourceFingerprint{
			source_mtime_unix: ingest.source_mtime_unix
			source_size_bytes: ingest.source_size_bytes
		})
		seen[ingest.session_id] = true
	}
	if rows.len == 0 {
		return
	}
	mut session := db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
		storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	_ = session.put_rows(mut db, 'search_state', rows, storage.ChunkConfig.default(),
		sync_meta('sync search state'))!
	session.finish(mut db)!
}

fn write_entry_search_states(mut db storage.PersistentDatabase, ingest_states map[string]EntryIngestState, entry_ids []string, stale_entry_ids []string, cfg storage.ChunkConfig) ! {
	if entry_ids.len == 0 && stale_entry_ids.len == 0 {
		return
	}
	use_split_group_commit := cfg.enable_split_backed_working_set
	mut session := storage.GroupCommitSession{}
	mut split_session := storage.SplitGroupCommitSession{}
	if use_split_group_commit {
		split_session = db.begin_split_group_commit_session(storage.SessionOptions.for_branch(store_branch),
			storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512), cfg)!
	} else {
		session = db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
			storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	}
	if stale_entry_ids.len > 0 {
		mut delete_keys := [][]u8{cap: stale_entry_ids.len}
		for entry_id in stale_entry_ids {
			delete_keys << entry_id.bytes()
		}
		if use_split_group_commit {
			_ = split_session.delete_rows(mut db, 'entry_search_state', delete_keys, cfg,
				sync_meta('delete stale entry search state'))!
		} else {
			_ = session.delete_rows(mut db, 'entry_search_state', delete_keys,
				storage.ChunkConfig.default(), sync_meta('delete stale entry search state'))!
		}
	}
	if entry_ids.len > 0 {
		mut rows := map[string]storage.TypedRowData{}
		for entry_id in entry_ids {
			state := ingest_states[entry_id] or { EntryIngestState{} }
			if state.id.len == 0 {
				continue
			}
			rows[entry_id] = build_entry_search_state_row(entry_id, state.session_id,
				state.entry_hash)
		}
		if rows.len > 0 {
			if use_split_group_commit {
				_ = split_session.put_rows(mut db, 'entry_search_state', rows, cfg,
					sync_meta('sync entry search state'))!
			} else {
				_ = session.put_rows(mut db, 'entry_search_state', rows,
					storage.ChunkConfig.default(), sync_meta('sync entry search state'))!
			}
		}
	}
	if use_split_group_commit {
		split_session.finish(mut db)!
	} else {
		session.finish(mut db)!
	}
}

fn same_session_summary(left SessionSummary, right SessionSummary) bool {
	return left.id == right.id && left.title == right.title && left.updated_at == right.updated_at
		&& left.started_at == right.started_at && left.cwd == right.cwd
		&& left.source == right.source && left.originator == right.originator
		&& left.cli_version == right.cli_version && left.path == right.path
		&& left.archived == right.archived && left.entry_count == right.entry_count
		&& left.user_turns == right.user_turns && left.tool_calls == right.tool_calls
}

fn delete_entries_for_sessions(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, session_ids []string) ! {
	if session_ids.len == 0 {
		return
	}
	reader := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	for session_id in session_ids {
		rows := reader.lookup_index(mut db, 'entries', 'entries_session_idx', session_id, 0)!
		for row in rows {
			_ = session.delete_row(mut db, 'entries', row.primary_key,
				storage.ChunkConfig.default(),
				sync_meta('delete stale entry ${row.primary_key.bytestr()}'))!
		}
	}
}

fn delete_entries_for_session(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, session_id string) ! {
	if session_id.len == 0 {
		return
	}
	delete_entries_for_sessions(mut db, mut session, [session_id])!
}

fn existing_entry_primary_keys(mut db storage.PersistentDatabase, session_id string) ![][]u8 {
	if session_id.len == 0 {
		return [][]u8{}
	}
	reader := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := reader.lookup_index(mut db, 'entries', 'entries_session_idx', session_id, 0)!
	mut out := [][]u8{cap: rows.len}
	for row in rows {
		out << row.primary_key.clone()
	}
	return out
}

fn build_session_row(summary SessionSummary) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('id', summary.id)
	row.set('title', summary.title)
	row.set('updated_at', summary.updated_at)
	if summary.started_at.len > 0 {
		row.set('started_at', summary.started_at)
	} else {
		row.set_null('started_at')
	}
	if summary.cwd.len > 0 {
		row.set('cwd', summary.cwd)
	} else {
		row.set_null('cwd')
	}
	if summary.source.len > 0 {
		row.set('source', summary.source)
	} else {
		row.set_null('source')
	}
	if summary.originator.len > 0 {
		row.set('originator', summary.originator)
	} else {
		row.set_null('originator')
	}
	if summary.cli_version.len > 0 {
		row.set('cli_version', summary.cli_version)
	} else {
		row.set_null('cli_version')
	}
	row.set('path', summary.path)
	row.set('archived', summary.archived)
	row.set('entry_count', i64(summary.entry_count))
	row.set('user_turns', i64(summary.user_turns))
	row.set('tool_calls', i64(summary.tool_calls))
	return row
}

fn decode_session_entry(row storage.TypedSchemaRow) !SessionEntry {
	return SessionEntry{
		seq:       int(must_i64(row, 'seq')!)
		timestamp: must_string(row, 'timestamp')!
		kind:      parse_entry_kind(must_string(row, 'kind')!)
		role:      must_string(row, 'role')!
		title:     opt_string(row, 'title')
		text:      must_string(row, 'content_text')!
		markdown:  ''
		tool_name: opt_string(row, 'tool_name')
		call_id:   opt_string(row, 'call_id')
		raw_type:  opt_string(row, 'raw_type')
		phase:     opt_string(row, 'phase')
	}
}

fn decode_session_entry_with_markdown(mut db storage.PersistentDatabase, row storage.TypedSchemaRow) !SessionEntry {
	mut entry := decode_session_entry(row)!
	ref := opt_markdown_ref(row, 'content_md') or { return entry }
	entry.markdown = db.load_markdown(ref) or { entry.text }
	return entry
}

fn entry_session_id(row storage.TypedSchemaRow) !string {
	return must_string(row, 'session_id')
}

fn entry_session_id_query(row queryapi.QueryRow) !string {
	return must_string_query(row, 'session_id')
}

fn entry_session_title(row storage.TypedSchemaRow) !string {
	return must_string(row, 'session_title')
}

fn entry_session_title_query(row queryapi.QueryRow) !string {
	return must_string_query(row, 'session_title')
}

fn must_string(row storage.TypedSchemaRow, name string) !string {
	value := row.data.get(name)!
	return match value {
		string { value }
		else { return error('expected string column: ${name}') }
	}
}

fn must_string_query(row queryapi.QueryRow, name string) !string {
	return row.data.get(name)!.as_string()
}

fn opt_markdown_ref(row storage.TypedSchemaRow, name string) ?storage.MarkdownRef {
	value := row.data.get(name) or { return none }
	return match value {
		storage.MarkdownRef { value }
		else { none }
	}
}

fn opt_string_query(row queryapi.QueryRow, name string) string {
	value := row.data.get(name) or { return '' }
	if value.is_null() {
		return ''
	}
	return value.as_string() or { '' }
}

fn must_i64_query(row queryapi.QueryRow, name string) !i64 {
	return row.data.get(name)!.as_i64()
}

fn must_bool_query(row queryapi.QueryRow, name string) !bool {
	return row.data.get(name)!.as_bool()
}

fn opt_string(row storage.TypedSchemaRow, name string) string {
	if !row.data.has(name) {
		return ''
	}
	value := row.data.get(name) or { return '' }
	return match value {
		string { value }
		else { '' }
	}
}

fn must_i64(row storage.TypedSchemaRow, name string) !i64 {
	value := row.data.get(name)!
	return match value {
		i64 { value }
		else { return error('expected i64 column: ${name}') }
	}
}

fn must_bool(row storage.TypedSchemaRow, name string) !bool {
	value := row.data.get(name)!
	return match value {
		bool { value }
		else { return error('expected bool column: ${name}') }
	}
}

fn parse_entry_kind(value string) EntryKind {
	return match value {
		'message' { .message }
		'reasoning' { .reasoning }
		'tool_call' { .tool_call }
		'tool_result' { .tool_result }
		else { .meta }
	}
}

fn normalized_search_terms(query string) []string {
	mut terms := []string{}
	mut seen := map[string]bool{}
	for term in storage.fts_tokenize_text(query.replace('\n', ' ')) {
		if term.len > 0 && !seen[term] {
			seen[term] = true
			terms << term
		}
	}
	if terms.len > 0 {
		return terms
	}
	for raw in query.replace('\n', ' ').split(' ') {
		term := raw.trim_space().to_lower()
		if term.len > 0 && !seen[term] {
			seen[term] = true
			terms << term
		}
	}
	return terms
}

fn search_request_matches_entry(request SearchRequest, entry SessionEntry, summary SessionSummary, terms []string) bool {
	if !search_request_matches_entry_metadata(request, entry, summary) {
		return false
	}
	haystack := search_haystack(entry, summary)
	for term in terms {
		if !haystack.contains(term) {
			return false
		}
	}
	return true
}

fn search_request_matches_row_metadata(request SearchRequest, row storage.TypedSchemaRow, summary SessionSummary) bool {
	if request.session_id.len > 0 && summary.id != request.session_id {
		return false
	}
	if request.cwd_prefix.len > 0 && !summary.cwd.starts_with(request.cwd_prefix) {
		return false
	}
	if request.source.len > 0 && summary.source.to_lower() != request.source.to_lower() {
		return false
	}
	return entry_kind_matches_filter(search_hit_entry_kind(row), request.kind)
}

fn search_request_matches_query_row_metadata(request SearchRequest, row queryapi.QueryRow, summary SessionSummary) bool {
	if request.session_id.len > 0 && summary.id != request.session_id {
		return false
	}
	if request.cwd_prefix.len > 0 && !summary.cwd.starts_with(request.cwd_prefix) {
		return false
	}
	if request.source.len > 0 && summary.source.to_lower() != request.source.to_lower() {
		return false
	}
	return entry_kind_matches_filter(search_hit_entry_kind_query(row), request.kind)
}

fn search_request_matches_entry_metadata(request SearchRequest, entry SessionEntry, summary SessionSummary) bool {
	if request.session_id.len > 0 && summary.id != request.session_id {
		return false
	}
	if request.cwd_prefix.len > 0 && !summary.cwd.starts_with(request.cwd_prefix) {
		return false
	}
	if request.source.len > 0 && summary.source.to_lower() != request.source.to_lower() {
		return false
	}
	if !entry_kind_matches_filter(entry.kind, request.kind) {
		return false
	}
	return true
}

fn search_haystack(entry SessionEntry, summary SessionSummary) string {
	return '${entry.title}\n${entry.tool_name}\n${entry.text}\n${summary.title}\n${summary.cwd}\n${summary.source}'.to_lower()
}

fn entry_kind_matches_filter(kind EntryKind, filter string) bool {
	if filter.len == 0 || filter == 'all' {
		return true
	}
	return match filter {
		'message' { kind == .message }
		'reasoning' { kind == .reasoning }
		'meta' { kind == .meta }
		'tool' { kind in [.tool_call, .tool_result] }
		'tool_call' { kind == .tool_call }
		'tool_result' { kind == .tool_result }
		else { kind.str() == filter }
	}
}

fn build_search_hit(row storage.TypedSchemaRow, entry SessionEntry, summary SessionSummary, query string) SearchHit {
	return build_search_hit_with_snippet(row, entry, summary, query, '')
}

fn build_search_hit_row_with_snippet(row storage.TypedSchemaRow, summary SessionSummary, query string, snippet string) SearchHit {
	return SearchHit{
		session_id:     entry_session_id(row) or { summary.id }
		session_title:  entry_session_title(row) or { summary.title }
		session_cwd:    summary.cwd
		session_source: summary.source
		path:           summary.path
		entry_seq:      search_hit_entry_seq(row)
		kind:           search_hit_entry_kind(row)
		role:           opt_string(row, 'role')
		timestamp:      opt_string(row, 'timestamp')
		snippet:        if snippet.len > 0 {
			snippet
		} else {
			compact_snippet(search_hit_text(row, summary), query, 160)
		}
	}
}

fn build_search_hit_query_row_with_snippet(row queryapi.QueryRow, summary SessionSummary, query string, snippet string) SearchHit {
	return SearchHit{
		session_id:     entry_session_id_query(row) or { summary.id }
		session_title:  entry_session_title_query(row) or { summary.title }
		session_cwd:    summary.cwd
		session_source: summary.source
		path:           summary.path
		entry_seq:      search_hit_entry_seq_query(row)
		kind:           search_hit_entry_kind_query(row)
		role:           opt_string_query(row, 'role')
		timestamp:      opt_string_query(row, 'timestamp')
		snippet:        if snippet.len > 0 {
			snippet
		} else {
			compact_snippet(search_hit_text_query(row, summary), query, 160)
		}
	}
}

fn build_search_hit_with_snippet(row storage.TypedSchemaRow, entry SessionEntry, summary SessionSummary, query string, snippet string) SearchHit {
	haystack := if entry.text.len > 0 {
		entry.text
	} else {
		'${entry.title}\n${entry.tool_name}\n${summary.title}'
	}
	return SearchHit{
		session_id:     entry_session_id(row) or { summary.id }
		session_title:  entry_session_title(row) or { summary.title }
		session_cwd:    summary.cwd
		session_source: summary.source
		path:           summary.path
		entry_seq:      entry.seq
		kind:           entry.kind
		role:           entry.role
		timestamp:      entry.timestamp
		snippet:        if snippet.len > 0 { snippet } else { compact_snippet(haystack, query, 160) }
	}
}

fn build_session_metadata_search_hit(summary SessionSummary, query string) SearchHit {
	haystack := '${summary.title}\n${summary.cwd}\n${summary.source}\n${summary.path}'
	return SearchHit{
		session_id:     summary.id
		session_title:  summary.title
		session_cwd:    summary.cwd
		session_source: summary.source
		path:           summary.path
		entry_seq:      -1
		kind:           .meta
		role:           'session'
		timestamp:      summary.updated_at
		snippet:        compact_snippet(haystack, query, 160)
	}
}

fn search_hit_entry_seq(row storage.TypedSchemaRow) int {
	return int(must_i64(row, 'seq') or { 0 })
}

fn search_hit_entry_seq_query(row queryapi.QueryRow) int {
	return int(must_i64_query(row, 'seq') or { 0 })
}

fn search_hit_entry_kind(row storage.TypedSchemaRow) EntryKind {
	return parse_entry_kind(opt_string(row, 'kind'))
}

fn search_hit_entry_kind_query(row queryapi.QueryRow) EntryKind {
	return parse_entry_kind(opt_string_query(row, 'kind'))
}

fn search_hit_text(row storage.TypedSchemaRow, summary SessionSummary) string {
	content_text := opt_string(row, 'content_text')
	if content_text.len > 0 {
		return content_text
	}
	return '${opt_string(row, 'title')}\n${opt_string(row, 'tool_name')}\n${summary.title}'
}

fn search_hit_text_query(row queryapi.QueryRow, summary SessionSummary) string {
	content_text := opt_string_query(row, 'content_text')
	if content_text.len > 0 {
		return content_text
	}
	return '${opt_string_query(row, 'title')}\n${opt_string_query(row, 'tool_name')}\n${summary.title}'
}

fn score_search_entry(query string, terms []string, entry SessionEntry, summary SessionSummary) int {
	mut score := 0
	title := entry.title.to_lower()
	tool_name := entry.tool_name.to_lower()
	text := entry.text.to_lower()
	session_title := summary.title.to_lower()
	query_lower := query.to_lower()
	if title.contains(query_lower) {
		score += 90
	}
	if tool_name.contains(query_lower) {
		score += 80
	}
	if session_title.contains(query_lower) {
		score += 70
	}
	if text.contains(query_lower) {
		score += 50
	}
	for term in terms {
		if title.contains(term) {
			score += 24
		}
		if tool_name.contains(term) {
			score += 22
		}
		if session_title.contains(term) {
			score += 18
		}
		if text.contains(term) {
			score += 10
		}
	}
	score += match entry.kind {
		.message { 8 }
		.reasoning { 6 }
		.tool_call { 4 }
		.tool_result { 4 }
		.meta { 2 }
	}

	return score
}

fn score_search_row_fts(query string, terms []string, row storage.TypedSchemaRow, summary SessionSummary, fts_score f64) int {
	mut score := 0
	title := opt_string(row, 'title').to_lower()
	tool_name := opt_string(row, 'tool_name').to_lower()
	text := opt_string(row, 'content_text').to_lower()
	session_title := summary.title.to_lower()
	query_lower := query.to_lower()
	if title.contains(query_lower) {
		score += 90
	}
	if tool_name.contains(query_lower) {
		score += 80
	}
	if session_title.contains(query_lower) {
		score += 70
	}
	if text.contains(query_lower) {
		score += 50
	}
	for term in terms {
		if title.contains(term) {
			score += 24
		}
		if tool_name.contains(term) {
			score += 22
		}
		if session_title.contains(term) {
			score += 18
		}
		if text.contains(term) {
			score += 10
		}
	}
	score += match search_hit_entry_kind(row) {
		.message { 8 }
		.reasoning { 6 }
		.tool_call { 4 }
		.tool_result { 4 }
		.meta { 2 }
	}

	if fts_score < 0 {
		score += int((-fts_score) * 1000.0)
	}
	return score
}

fn score_search_query_row_fts(query string, terms []string, row queryapi.QueryRow, summary SessionSummary, fts_score f64) int {
	mut score := 0
	title := opt_string_query(row, 'title').to_lower()
	tool_name := opt_string_query(row, 'tool_name').to_lower()
	text := opt_string_query(row, 'content_text').to_lower()
	session_title := summary.title.to_lower()
	query_lower := query.to_lower()
	if title.contains(query_lower) {
		score += 90
	}
	if tool_name.contains(query_lower) {
		score += 80
	}
	if session_title.contains(query_lower) {
		score += 70
	}
	if text.contains(query_lower) {
		score += 50
	}
	for term in terms {
		if title.contains(term) {
			score += 24
		}
		if tool_name.contains(term) {
			score += 22
		}
		if session_title.contains(term) {
			score += 18
		}
		if text.contains(term) {
			score += 10
		}
	}
	score += match search_hit_entry_kind_query(row) {
		.message { 8 }
		.reasoning { 6 }
		.tool_call { 4 }
		.tool_result { 4 }
		.meta { 2 }
	}

	if fts_score < 0 {
		score += int((-fts_score) * 1000.0)
	}
	return score
}

fn score_search_entry_fts(query string, terms []string, entry SessionEntry, summary SessionSummary, fts_score f64) int {
	mut score := score_search_entry(query, terms, entry, summary)
	if fts_score < 0 {
		score += int((-fts_score) * 1000.0)
	}
	return score
}

fn score_session_metadata_search_hit(query string, terms []string, summary SessionSummary) int {
	mut score := 0
	query_lower := query.to_lower()
	title := summary.title.to_lower()
	cwd := summary.cwd.to_lower()
	source := summary.source.to_lower()
	path := summary.path.to_lower()
	if title.contains(query_lower) {
		score += 120
	}
	if cwd.contains(query_lower) {
		score += 100
	}
	if source.contains(query_lower) {
		score += 70
	}
	if path.contains(query_lower) {
		score += 60
	}
	for term in terms {
		if title.contains(term) {
			score += 20
		}
		if cwd.contains(term) {
			score += 15
		}
		if source.contains(term) {
			score += 10
		}
		if path.contains(term) {
			score += 10
		}
	}
	return score
}

fn clamp_offset(offset int, total int) int {
	if offset <= 0 {
		return 0
	}
	if offset >= total {
		return total
	}
	return offset
}

fn clamp_limit(start int, limit int, total int) int {
	if limit <= 0 {
		return total
	}
	end := start + limit
	if end > total {
		return total
	}
	return end
}

fn paginate_ranked_search_hits(hits []RankedSearchHit, request SearchRequest) SearchResult {
	mut ranked := hits.clone()
	ranked.sort_with_compare(fn (a &RankedSearchHit, b &RankedSearchHit) int {
		if a.score > b.score {
			return -1
		}
		if a.score < b.score {
			return 1
		}
		if a.hit.timestamp > b.hit.timestamp {
			return -1
		}
		if a.hit.timestamp < b.hit.timestamp {
			return 1
		}
		if a.hit.entry_seq > b.hit.entry_seq {
			return -1
		}
		if a.hit.entry_seq < b.hit.entry_seq {
			return 1
		}
		return 0
	})
	total := ranked.len
	start := clamp_offset(request.offset, total)
	end := clamp_limit(start, request.limit, total)
	mut out := []SearchHit{cap: max_int(end - start, 0)}
	for item in ranked[start..end] {
		out << item.hit
	}
	return SearchResult{
		total: total
		hits:  out
	}
}
