module storage

import encoding.base64
import json
import rand

pub struct ReflectionEvidence {
pub:
	table_name  string
	primary_key []u8
	column_name string
	target_id   string
	score       f64
	scope       MarkdownEmbeddingScope
	kind        string
	anchor      string
	path_hint   string
	text        string
}

struct ReflectionSourceRefDto {
	table_name  string
	primary_key string
	column_name string
	target_id   string
	score       f64
	scope       string
	kind        string
	anchor      string
	path_hint   string
	text        string
}

struct MemoryLinkMetadataDto {
	target_id       string
	score           f64
	scope           string
	kind            string
	anchor          string
	path_hint       string
	text            string
	seed_scope      string
	seed_anchor     string
	seed_text       string
	reflection_kind string
}

pub struct ReflectionSourceRef {
pub:
	table_name  string
	primary_key []u8
	column_name string
	target_id   string
	score       f64
	scope       MarkdownEmbeddingScope
	kind        string
	anchor      string
	path_hint   string
	text        string
}

pub struct MemoryLink {
pub:
	link_id                string
	link_kind              string
	from_table_name        string
	from_primary_key       []u8
	from_column_name       string
	to_table_name          string
	to_primary_key         []u8
	to_column_name         string
	metadata_json          string
	derived_from_root_hash string
	created_at             string
}

pub struct ReflectionJob {
pub:
	branch_name     string
	table_name      string
	primary_key     []u8
	column_name     string
	reflection_kind string
	seed_scope      MarkdownEmbeddingScope
	seed_anchor     string
	seed_text       string
	evidence        []ReflectionEvidence
}

pub struct ReflectionPersistInput {
pub:
	title                    string
	summary_md               string
	insight_md               string
	parent_ref               string
	topic_key                string
	supersedes_reflection_id string
}

pub struct PersistedReflection {
pub:
	reflection_id            string
	reflection_kind          string
	title                    string
	summary_ref              MarkdownRef
	insight_ref              MarkdownRef
	source_refs              []ReflectionSourceRef
	parent_ref               string
	topic_key                string
	derived_from_root_hash   string
	supersedes_reflection_id string
	created_at               string
	links                    []MemoryLink
}

pub struct ReplayQueryRequest {
pub:
	branch_name      string
	text             string
	seed_limit       int = 4
	neighbor_limit   int = 8
	reflection_limit int = 4
}

pub struct ReplayEvidenceHit {
pub:
	table_name       string
	primary_key      []u8
	column_name      string
	score            f64
	anchor           string
	path_hint        string
	text             string
	via_link_kind    string
	source_target_id string
}

pub struct ReplayReflectionHit {
pub:
	reflection_id          string
	reflection_kind        string
	title                  string
	summary_md             string
	insight_md             string
	topic_key              string
	score                  f64
	derived_from_root_hash string
	source_refs            []ReflectionSourceRef
}

pub struct ReplayQueryResult {
pub:
	source_hits   []VectorSearchHit
	evidence_hits []ReplayEvidenceHit
	reflections   []ReplayReflectionHit
}

pub struct ReplayTopicView {
pub:
	reflection_id   string
	title           string
	reflection_kind string
	topic_key       string
	score           f64
	summary_md      string
	insight_md      string
	evidence_count  int
}

pub struct ReplayEvidenceView {
pub:
	table_name    string
	primary_key   []u8
	column_name   string
	score         f64
	anchor        string
	path_hint     string
	text          string
	via_link_kind string
}

pub struct ReplayTimelineView {
pub:
	branch_name              string
	derived_from_root_hashes []string
	reflection_ids           []string
	source_keys              []string
}

pub struct ReplayOverview {
pub:
	topics   []ReplayTopicView
	evidence []ReplayEvidenceView
	timeline ReplayTimelineView
}

pub struct ReflectMemoryOptions {
pub:
	neighbor_limit int = 8
	max_jobs       int = 1
	min_evidence   int = 1
	title          string
	topic_key      string
	cfg            ChunkConfig = ChunkConfig.default()
	meta           CommitMeta
}

pub struct ReflectorScheduleOptions {
pub:
	write_threshold int = 16
	max_jobs        int = 1
	neighbor_limit  int = 8
	min_evidence    int = 1
}

pub struct ReflectorScheduleDecision {
pub:
	should_reflect bool
	reason         string
	pending_writes int
}

pub struct ReflectorState {
pub:
	branch_name              string
	pending_writes           int
	last_reflected_root_hash string
	last_reflected_at        string
	updated_at               string
}

pub struct ReflectorScheduler {
pub:
	options ReflectorScheduleOptions
mut:
	pending_writes int
}

struct ReflectMemoryCandidate {
	table_name  string
	primary_key []u8
	column_name string
}

pub fn ReflectorScheduler.new(options ReflectorScheduleOptions) ReflectorScheduler {
	return ReflectorScheduler{
		options: options
	}
}

pub fn ReflectorScheduler.from_state(options ReflectorScheduleOptions, state ReflectorState) ReflectorScheduler {
	return ReflectorScheduler{
		options:        options
		pending_writes: state.pending_writes
	}
}

pub fn (mut scheduler ReflectorScheduler) note_write(count int) {
	if count <= 0 {
		return
	}
	scheduler.pending_writes += count
}

pub fn (scheduler ReflectorScheduler) decision() ReflectorScheduleDecision {
	threshold := if scheduler.options.write_threshold > 0 {
		scheduler.options.write_threshold
	} else {
		16
	}
	if scheduler.pending_writes >= threshold {
		return ReflectorScheduleDecision{
			should_reflect: true
			reason:         'write_threshold'
			pending_writes: scheduler.pending_writes
		}
	}
	return ReflectorScheduleDecision{
		should_reflect: false
		reason:         'below_threshold'
		pending_writes: scheduler.pending_writes
	}
}

pub fn (mut scheduler ReflectorScheduler) reset_after_reflect(reflected_count int) {
	if reflected_count > 0 {
		scheduler.pending_writes = 0
	}
}

pub fn (mut scheduler ReflectorScheduler) maybe_reflect(mut database PersistentDatabase, branch_name string, mut embedding_engine EmbeddingEngine, mut generator ReflectionTextGenerator) ![]PersistedReflection {
	decision := scheduler.decision()
	if !decision.should_reflect {
		return []PersistedReflection{}
	}
	persisted := database.reflect_memory_once(branch_name, mut embedding_engine, mut generator,
		ReflectMemoryOptions{
		neighbor_limit: scheduler.options.neighbor_limit
		max_jobs:       scheduler.options.max_jobs
		min_evidence:   scheduler.options.min_evidence
	})!
	scheduler.reset_after_reflect(persisted.len)
	return persisted
}

pub fn (mut scheduler ReflectorScheduler) maybe_reflect_persistent(mut database PersistentDatabase, branch_name string, mut embedding_engine EmbeddingEngine, mut generator ReflectionTextGenerator, cfg ChunkConfig, meta CommitMeta) ![]PersistedReflection {
	state := database.load_reflector_state(branch_name)!
	if state.pending_writes > scheduler.pending_writes {
		scheduler.pending_writes = state.pending_writes
	}
	persisted := scheduler.maybe_reflect(mut database, branch_name, mut embedding_engine, mut
		generator)!
	last_root := if persisted.len > 0 {
		persisted[persisted.len - 1].derived_from_root_hash
	} else {
		state.last_reflected_root_hash
	}
	last_at := if persisted.len > 0 {
		persisted[persisted.len - 1].created_at
	} else {
		state.last_reflected_at
	}
	database.save_reflector_state(ReflectorState{
		branch_name:              branch_name
		pending_writes:           scheduler.pending_writes
		last_reflected_root_hash: last_root
		last_reflected_at:        last_at
	}, cfg, meta)!
	return persisted
}

pub fn memory_reflections_spec() !TypedTableSpec {
	return TypedTableSpec.new(TableDef.new('memory_reflections', [
		ColumnDef.new('reflection_id', .string_, false)!,
		ColumnDef.new('reflection_kind', .string_, false)!,
		ColumnDef.new('title', .string_, false)!,
		ColumnDef.new('summary_md', .markdown_, false)!,
		ColumnDef.new('insight_md', .markdown_, true)!,
		ColumnDef.new('source_refs', .json_, false)!,
		ColumnDef.new('parent_ref', .string_, true)!,
		ColumnDef.new('topic_key', .string_, true)!,
		ColumnDef.new('derived_from_root_hash', .string_, false)!,
		ColumnDef.new('supersedes_reflection_id', .string_, true)!,
		ColumnDef.datetime_with_current_timestamp('created_at', false, false)!,
	], ['reflection_id'])!, [
		SchemaIndexDef.new('reflection_kind_idx', 'reflection_kind')!,
		SchemaIndexDef.new('topic_key_idx', 'topic_key')!,
		SchemaIndexDef.new('derived_from_root_hash_idx', 'derived_from_root_hash')!,
	])!
}

pub fn memory_reflector_state_spec() !TypedTableSpec {
	return TypedTableSpec.new(TableDef.new('memory_reflector_state', [
		ColumnDef.new('branch_name', .string_, false)!,
		ColumnDef.new('pending_writes', .i64_, false)!,
		ColumnDef.new('last_reflected_root_hash', .string_, true)!,
		ColumnDef.new('last_reflected_at', .datetime_, true)!,
		ColumnDef.datetime_with_current_timestamp('updated_at', false, true)!,
	], ['branch_name'])!, [
		SchemaIndexDef.new('updated_at_idx', 'updated_at')!,
	])!
}

pub fn memory_links_spec() !TypedTableSpec {
	return TypedTableSpec.new(TableDef.new('memory_links', [
		ColumnDef.new('link_id', .string_, false)!,
		ColumnDef.new('link_kind', .string_, false)!,
		ColumnDef.new('from_table_name', .string_, false)!,
		ColumnDef.new('from_primary_key_b64', .string_, false)!,
		ColumnDef.new('from_column_name', .string_, true)!,
		ColumnDef.new('to_table_name', .string_, false)!,
		ColumnDef.new('to_primary_key_b64', .string_, false)!,
		ColumnDef.new('to_column_name', .string_, true)!,
		ColumnDef.new('metadata_json', .json_, false)!,
		ColumnDef.new('derived_from_root_hash', .string_, false)!,
		ColumnDef.datetime_with_current_timestamp('created_at', false, false)!,
	], ['link_id'])!, [
		SchemaIndexDef.new('link_kind_idx', 'link_kind')!,
		SchemaIndexDef.new('from_table_idx', 'from_table_name')!,
		SchemaIndexDef.new('to_table_idx', 'to_table_name')!,
		SchemaIndexDef.new('derived_from_root_hash_idx', 'derived_from_root_hash')!,
	])!
}

pub fn (mut database PersistentDatabase) ensure_memory_reflections_table() ! {
	if database.has_table('memory_reflections') {
		return
	}
	database.register_table(memory_reflections_spec()!)!
}

pub fn (mut database PersistentDatabase) ensure_memory_reflector_state_table() ! {
	if database.has_table('memory_reflector_state') {
		return
	}
	database.register_table(memory_reflector_state_spec()!)!
}

pub fn (mut database PersistentDatabase) ensure_memory_links_table() ! {
	if database.has_table('memory_links') {
		return
	}
	database.register_table(memory_links_spec()!)!
}

pub fn (database PersistentDatabase) reflection_capabilities() []MemoryCapabilityDef {
	mut out := []MemoryCapabilityDef{}
	for key in sorted_memory_capability_keys(database.memory_capabilities) {
		capability := database.memory_capabilities[key] or { continue }
		out << capability
	}
	return out
}

pub fn (database PersistentDatabase) reflection_capabilities_for_table(table_name string) []MemoryCapabilityDef {
	return database.memory_capabilities_for_table(table_name)
}

pub fn (mut database PersistentDatabase) load_reflector_state(branch_name string) !ReflectorState {
	if branch_name.len == 0 {
		return error('reflector state requires branch_name')
	}
	database.ensure_memory_reflector_state_table()!
	session := database.open_session(branch_name)!
	row := session.get_row(mut database, 'memory_reflector_state', branch_name.bytes()) or {
		return ReflectorState{
			branch_name:    branch_name
			pending_writes: 0
		}
	}
	return decode_reflector_state_row(row)
}

pub fn (mut database PersistentDatabase) save_reflector_state(state ReflectorState, cfg ChunkConfig, meta CommitMeta) !ReflectorState {
	if state.branch_name.len == 0 {
		return error('reflector state requires branch_name')
	}
	database.ensure_memory_reflector_state_table()!
	mut row := TypedRowData.new()
	row.set('branch_name', state.branch_name)
	row.set('pending_writes', i64(state.pending_writes))
	if state.last_reflected_root_hash.len > 0 {
		row.set('last_reflected_root_hash', state.last_reflected_root_hash)
	} else {
		row.set('last_reflected_root_hash', NullValue{})
	}
	if state.last_reflected_at.len > 0 {
		row.set('last_reflected_at', state.last_reflected_at)
	} else {
		row.set('last_reflected_at', NullValue{})
	}
	mut writes := TypedWriteSet.new()
	writes.put('memory_reflector_state', state.branch_name.bytes(), row)
	commit_meta := if meta.message.len > 0 || meta.author.len > 0 || meta.timestamp != 0 {
		meta
	} else {
		CommitMeta{
			author:  'pollydb/reflector'
			message: 'save reflector state'
		}
	}
	database.apply_typed_write_set(state.branch_name, writes, cfg, commit_meta)!
	return database.load_reflector_state(state.branch_name)!
}

pub fn (mut database PersistentDatabase) note_reflector_writes(branch_name string, count int, cfg ChunkConfig, meta CommitMeta) !ReflectorState {
	if count <= 0 {
		return database.load_reflector_state(branch_name)!
	}
	state := database.load_reflector_state(branch_name)!
	return database.save_reflector_state(ReflectorState{
		branch_name:              branch_name
		pending_writes:           state.pending_writes + count
		last_reflected_root_hash: state.last_reflected_root_hash
		last_reflected_at:        state.last_reflected_at
	}, cfg, meta)!
}

pub fn (mut database PersistentDatabase) reflect_memory_once(branch_name string, mut embedding_engine EmbeddingEngine, mut generator ReflectionTextGenerator, options ReflectMemoryOptions) ![]PersistedReflection {
	if branch_name.len == 0 {
		return error('reflect memory requires branch_name')
	}
	max_jobs := if options.max_jobs > 0 { options.max_jobs } else { 1 }
	min_evidence := if options.min_evidence >= 0 { options.min_evidence } else { 1 }
	candidates := database.reflective_markdown_candidates(branch_name)!
	if candidates.len == 0 {
		return []PersistedReflection{}
	}
	for candidate in candidates {
		database.index_reflective_markdown_fields(branch_name, candidate.table_name, candidate.primary_key, mut
			embedding_engine)!
	}
	reflected_sources := database.reflected_source_keys(branch_name)!
	mut persisted := []PersistedReflection{cap: max_jobs}
	for candidate in candidates {
		candidate_key := reflection_source_key(candidate.table_name, candidate.primary_key,
			candidate.column_name)
		if candidate_key in reflected_sources {
			continue
		}
		job := database.build_markdown_reflection_job(branch_name, candidate.table_name,
			candidate.primary_key, candidate.column_name, mut embedding_engine, options.neighbor_limit) or {
			continue
		}
		if job.evidence.len < min_evidence {
			continue
		}
		input := generate_reflection_persist_input(job, mut generator, ReflectionDistillOptions{
			title:        if options.title.len > 0 {
				options.title
			} else {
				reflection_default_title(job)
			}
			topic_key:    if options.topic_key.len > 0 {
				options.topic_key
			} else {
				reflection_default_topic_key(job)
			}
			max_evidence: options.neighbor_limit
		})!
		meta := if options.meta.message.len > 0 || options.meta.author.len > 0
			|| options.meta.timestamp != 0 {
			options.meta
		} else {
			CommitMeta{
				author:  'pollydb/reflector'
				message: 'reflect memory'
			}
		}
		persisted << database.persist_reflection_job(job, input, options.cfg, meta)!
		if persisted.len >= max_jobs {
			break
		}
	}
	return persisted
}

fn (mut database PersistentDatabase) reflective_markdown_candidates(branch_name string) ![]ReflectMemoryCandidate {
	mut out := []ReflectMemoryCandidate{}
	session := database.open_session(branch_name)!
	for capability in database.reflection_capabilities() {
		if !capability.options.enabled {
			continue
		}
		spec := database.table_spec(capability.table_name)!
		column := spec.table.column(capability.column_name)!
		if column.typ != .markdown_ {
			continue
		}
		rows := session.scan_table(mut database, capability.table_name, 0) or { []TypedSchemaRow{} }
		for row in rows {
			out << ReflectMemoryCandidate{
				table_name:  capability.table_name
				primary_key: row.primary_key.clone()
				column_name: capability.column_name
			}
		}
	}
	return out
}

fn (mut database PersistentDatabase) reflected_source_keys(branch_name string) !map[string]bool {
	mut out := map[string]bool{}
	if !database.has_table('memory_links') {
		return out
	}
	session := database.open_session(branch_name)!
	rows := session.scan_table(mut database, 'memory_links', 0) or { []TypedSchemaRow{} }
	for row in rows {
		link := decode_memory_link_row(row) or { continue }
		if link.link_kind != 'semantic_neighbor' {
			continue
		}
		out[reflection_source_key(link.from_table_name, link.from_primary_key, link.from_column_name)] = true
	}
	return out
}

pub fn (mut database PersistentDatabase) index_reflective_markdown_fields(branch_name string, table_name string, primary_key []u8, mut engine EmbeddingEngine) ![]string {
	spec := database.table_spec(table_name)!
	session := database.open_session(branch_name)!
	row := session.get_row(mut database, table_name, primary_key)!
	mut indexed_columns := []string{}
	for capability in database.memory_capabilities_for_table(table_name) {
		if !capability.options.enabled {
			continue
		}
		column := spec.table.column(capability.column_name)!
		if column.typ != .markdown_ || capability.options.embedding_index.len == 0 {
			continue
		}
		ref := get_markdown_ref_from_row(row, column, capability.column_name)!
		database.index_markdown_ref_embeddings_for_source(branch_name, table_name, primary_key,
			capability.column_name, ref, mut engine)!
		indexed_columns << capability.column_name
	}
	return indexed_columns
}

pub fn (mut database PersistentDatabase) build_markdown_reflection_job(branch_name string, table_name string, primary_key []u8, column_name string, mut engine EmbeddingEngine, neighbor_limit int) !ReflectionJob {
	capability := database.memory_capability(table_name, column_name) or {
		return error('memory capability not registered: ${table_name}.${column_name}')
	}
	spec := database.table_spec(table_name)!
	column := spec.table.column(column_name)!
	if column.typ != .markdown_ {
		return error('reflection job currently requires markdown column: ${column_name}')
	}
	session := database.open_session(branch_name)!
	ref := session.get_markdown_ref(mut database, table_name, primary_key, column_name)!
	targets := markdown_embedding_targets_from_ref(database, ref)!
	if targets.len == 0 {
		return error('markdown column has no embedding targets: ${table_name}.${column_name}')
	}
	preferred_scope := reflection_preferred_scope(spec, capability)
	mut seed_targets := []MarkdownEmbeddingTarget{}
	for target in targets {
		if target.scope == preferred_scope {
			seed_targets << target
		}
	}
	if seed_targets.len == 0 {
		seed_targets = targets.clone()
	}
	limit := if neighbor_limit > 0 { neighbor_limit } else { 8 }
	mut evidence_by_source := map[string]ReflectionEvidence{}
	for seed in seed_targets {
		query_vector := engine.embed(seed.text)!
		hits := database.query_markdown_embedding_vector(query_vector, VectorSearchQuery{
			branch_name: branch_name
			limit:       limit + 8
			scope:       seed.scope
			scope_set:   true
		})!
		for hit in hits {
			if hit.table_name.len == 0 || hit.column_name.len == 0 {
				continue
			}
			if hit.table_name == table_name && hit.column_name == column_name
				&& hit.primary_key == primary_key {
				continue
			}
			key := reflection_source_key(hit.table_name, hit.primary_key, hit.column_name)
			existing := evidence_by_source[key] or { ReflectionEvidence{} }
			if existing.target_id.len > 0 && existing.score >= hit.score {
				continue
			}
			evidence_by_source[key] = ReflectionEvidence{
				table_name:  hit.table_name
				primary_key: hit.primary_key.clone()
				column_name: hit.column_name
				target_id:   hit.target_id
				score:       hit.score
				scope:       hit.scope
				kind:        hit.kind
				anchor:      hit.anchor
				path_hint:   hit.path_hint
				text:        hit.text
			}
		}
	}
	mut evidence := []ReflectionEvidence{}
	for key in evidence_by_source.keys() {
		evidence << evidence_by_source[key]
	}
	evidence.sort_with_compare(fn (a &ReflectionEvidence, b &ReflectionEvidence) int {
		if a.score > b.score {
			return -1
		}
		if a.score < b.score {
			return 1
		}
		a_key := reflection_source_key(a.table_name, a.primary_key, a.column_name)
		b_key := reflection_source_key(b.table_name, b.primary_key, b.column_name)
		if a_key < b_key {
			return -1
		}
		if a_key > b_key {
			return 1
		}
		return 0
	})
	if evidence.len > limit {
		evidence = evidence[..limit].clone()
	}
	return ReflectionJob{
		branch_name:     branch_name
		table_name:      table_name
		primary_key:     primary_key.clone()
		column_name:     column_name
		reflection_kind: capability.options.reflection_kind
		seed_scope:      seed_targets[0].scope
		seed_anchor:     seed_targets[0].anchor
		seed_text:       reflection_seed_text(seed_targets)
		evidence:        evidence
	}
}

pub fn encode_reflection_source_refs(refs []ReflectionSourceRef) string {
	mut payload := []ReflectionSourceRefDto{cap: refs.len}
	for ref in refs {
		payload << ReflectionSourceRefDto{
			table_name:  ref.table_name
			primary_key: base64.encode(ref.primary_key)
			column_name: ref.column_name
			target_id:   ref.target_id
			score:       ref.score
			scope:       ref.scope.str()
			kind:        ref.kind
			anchor:      ref.anchor
			path_hint:   ref.path_hint
			text:        ref.text
		}
	}
	return json.encode(payload)
}

pub fn decode_reflection_source_refs(raw string) ![]ReflectionSourceRef {
	if raw.trim_space().len == 0 {
		return []ReflectionSourceRef{}
	}
	payload := json.decode([]ReflectionSourceRefDto, raw)!
	mut refs := []ReflectionSourceRef{cap: payload.len}
	for item in payload {
		scope := if item.scope == MarkdownEmbeddingScope.path.str() {
			MarkdownEmbeddingScope.path
		} else {
			MarkdownEmbeddingScope.block
		}
		refs << ReflectionSourceRef{
			table_name:  item.table_name
			primary_key: if item.primary_key.len == 0 {
				[]u8{}
			} else {
				base64.decode(item.primary_key)
			}
			column_name: item.column_name
			target_id:   item.target_id
			score:       item.score
			scope:       scope
			kind:        item.kind
			anchor:      item.anchor
			path_hint:   item.path_hint
			text:        item.text
		}
	}
	return refs
}

pub fn (job ReflectionJob) source_refs() []ReflectionSourceRef {
	mut refs := []ReflectionSourceRef{cap: job.evidence.len}
	for evidence in job.evidence {
		refs << ReflectionSourceRef{
			table_name:  evidence.table_name
			primary_key: evidence.primary_key.clone()
			column_name: evidence.column_name
			target_id:   evidence.target_id
			score:       evidence.score
			scope:       evidence.scope
			kind:        evidence.kind
			anchor:      evidence.anchor
			path_hint:   evidence.path_hint
			text:        evidence.text
		}
	}
	return refs
}

pub fn encode_memory_link_metadata(ref ReflectionSourceRef, seed_scope MarkdownEmbeddingScope, seed_anchor string, seed_text string, reflection_kind string) string {
	return json.encode(MemoryLinkMetadataDto{
		target_id:       ref.target_id
		score:           ref.score
		scope:           ref.scope.str()
		kind:            ref.kind
		anchor:          ref.anchor
		path_hint:       ref.path_hint
		text:            ref.text
		seed_scope:      seed_scope.str()
		seed_anchor:     seed_anchor
		seed_text:       seed_text
		reflection_kind: reflection_kind
	})
}

fn decode_memory_link_metadata(raw string) !MemoryLinkMetadataDto {
	return json.decode(MemoryLinkMetadataDto, raw)
}

pub fn build_reflection_links(job ReflectionJob, reflection_id string, source_refs []ReflectionSourceRef, derived_from_root_hash string, created_at string) []MemoryLink {
	mut links := []MemoryLink{cap: source_refs.len * 2}
	for ref in source_refs {
		link_id := rand.uuid_v4()
		links << MemoryLink{
			link_id:                link_id
			link_kind:              'derived_from'
			from_table_name:        'memory_reflections'
			from_primary_key:       reflection_id.bytes()
			from_column_name:       'summary_md'
			to_table_name:          ref.table_name
			to_primary_key:         ref.primary_key.clone()
			to_column_name:         ref.column_name
			metadata_json:          encode_memory_link_metadata(ref, job.seed_scope, job.seed_anchor,
				job.seed_text, job.reflection_kind)
			derived_from_root_hash: derived_from_root_hash
			created_at:             created_at
		}
		neighbor_link_id := rand.uuid_v4()
		links << MemoryLink{
			link_id:                neighbor_link_id
			link_kind:              'semantic_neighbor'
			from_table_name:        job.table_name
			from_primary_key:       job.primary_key.clone()
			from_column_name:       job.column_name
			to_table_name:          ref.table_name
			to_primary_key:         ref.primary_key.clone()
			to_column_name:         ref.column_name
			metadata_json:          encode_memory_link_metadata(ref, job.seed_scope, job.seed_anchor,
				job.seed_text, job.reflection_kind)
			derived_from_root_hash: derived_from_root_hash
			created_at:             created_at
		}
	}
	return links
}

fn decode_memory_link_row(row TypedSchemaRow) !MemoryLink {
	link_id := required_row_string(row, 'link_id')!
	link_kind := required_row_string(row, 'link_kind')!
	from_table_name := required_row_string(row, 'from_table_name')!
	from_primary_key_b64 := required_row_string(row, 'from_primary_key_b64')!
	from_column_name := optional_row_string(row, 'from_column_name')
	to_table_name := required_row_string(row, 'to_table_name')!
	to_primary_key_b64 := required_row_string(row, 'to_primary_key_b64')!
	to_column_name := optional_row_string(row, 'to_column_name')
	metadata_json := required_row_string(row, 'metadata_json')!
	derived_from_root_hash := required_row_string(row, 'derived_from_root_hash')!
	created_at := required_row_string(row, 'created_at')!
	return MemoryLink{
		link_id:                link_id
		link_kind:              link_kind
		from_table_name:        from_table_name
		from_primary_key:       if from_primary_key_b64.len == 0 {
			[]u8{}
		} else {
			base64.decode(from_primary_key_b64)
		}
		from_column_name:       from_column_name
		to_table_name:          to_table_name
		to_primary_key:         if to_primary_key_b64.len == 0 {
			[]u8{}
		} else {
			base64.decode(to_primary_key_b64)
		}
		to_column_name:         to_column_name
		metadata_json:          metadata_json
		derived_from_root_hash: derived_from_root_hash
		created_at:             created_at
	}
}

fn required_row_string(row TypedSchemaRow, field string) !string {
	value := row.data.get(field)!
	return match value {
		string { value }
		else { error('expected string field: ${field}') }
	}
}

fn optional_row_string(row TypedSchemaRow, field string) string {
	value := row.data.get(field) or { return '' }
	return match value {
		string { value }
		else { '' }
	}
}

fn optional_row_int(row TypedSchemaRow, field string) int {
	value := row.data.get(field) or { return 0 }
	return match value {
		i64 { int(value) }
		else { 0 }
	}
}

fn decode_reflector_state_row(row TypedSchemaRow) !ReflectorState {
	branch_name := required_row_string(row, 'branch_name')!
	return ReflectorState{
		branch_name:              branch_name
		pending_writes:           optional_row_int(row, 'pending_writes')
		last_reflected_root_hash: optional_row_string(row, 'last_reflected_root_hash')
		last_reflected_at:        optional_row_string(row, 'last_reflected_at')
		updated_at:               optional_row_string(row, 'updated_at')
	}
}

fn replay_source_key(table_name string, primary_key []u8, column_name string) string {
	return reflection_source_key(table_name, primary_key, column_name)
}

fn decode_persisted_reflection(mut database PersistentDatabase, branch_name string, row TypedSchemaRow) !ReplayReflectionHit {
	_ = branch_name
	reflection_id := required_row_string(row, 'reflection_id')!
	reflection_kind := required_row_string(row, 'reflection_kind')!
	title := required_row_string(row, 'title')!
	topic_key := optional_row_string(row, 'topic_key')
	derived_from_root_hash := required_row_string(row, 'derived_from_root_hash')!
	source_refs_raw := required_row_string(row, 'source_refs')!
	source_refs := decode_reflection_source_refs(source_refs_raw)!
	summary_ref_value := row.data.get('summary_md')!
	summary_md := match summary_ref_value {
		MarkdownRef { database.load_markdown(summary_ref_value)! }
		else { return error('reflection summary_md must contain MarkdownRef payload') }
	}
	insight_value := row.data.get('insight_md') or { NullValue{} }
	insight_md := match insight_value {
		MarkdownRef { database.load_markdown(insight_value)! }
		else { '' }
	}
	return ReplayReflectionHit{
		reflection_id:          reflection_id
		reflection_kind:        reflection_kind
		title:                  title
		summary_md:             summary_md
		insight_md:             insight_md
		topic_key:              topic_key
		score:                  0.0
		derived_from_root_hash: derived_from_root_hash
		source_refs:            source_refs
	}
}

pub fn (mut database PersistentDatabase) replay_query(mut engine EmbeddingEngine, request ReplayQueryRequest) !ReplayQueryResult {
	if request.branch_name.len == 0 {
		return error('replay query requires branch_name')
	}
	if request.text.trim_space().len == 0 {
		return error('replay query requires text')
	}
	if !database.has_table('memory_links') || !database.has_table('memory_reflections') {
		return ReplayQueryResult{}
	}
	seed_limit := if request.seed_limit > 0 { request.seed_limit } else { 4 }
	neighbor_limit := if request.neighbor_limit > 0 { request.neighbor_limit } else { 8 }
	reflection_limit := if request.reflection_limit > 0 { request.reflection_limit } else { 4 }
	source_hits := database.query_markdown_text_embeddings(mut engine, request.text, VectorSearchQuery{
		branch_name: request.branch_name
		limit:       seed_limit
		scope:       .path
		scope_set:   true
	})!
	session := database.open_session(request.branch_name)!
	link_rows := session.scan_table(mut database, 'memory_links', 0)!
	mut links := []MemoryLink{cap: link_rows.len}
	for row in link_rows {
		links << decode_memory_link_row(row)!
	}
	mut evidence_by_key := map[string]ReplayEvidenceHit{}
	mut candidate_keys := map[string]f64{}
	for hit in source_hits {
		key := replay_source_key(hit.table_name, hit.primary_key, hit.column_name)
		current := candidate_keys[key] or { -1.0 }
		if hit.score > current {
			candidate_keys[key] = hit.score
		}
		evidence_by_key[key] = ReplayEvidenceHit{
			table_name:       hit.table_name
			primary_key:      hit.primary_key.clone()
			column_name:      hit.column_name
			score:            hit.score
			anchor:           hit.anchor
			path_hint:        hit.path_hint
			text:             hit.text
			via_link_kind:    'source_hit'
			source_target_id: hit.target_id
		}
	}
	for link in links {
		if link.link_kind != 'semantic_neighbor' {
			continue
		}
		from_key := replay_source_key(link.from_table_name, link.from_primary_key, link.from_column_name)
		base_score := candidate_keys[from_key] or { continue }
		metadata := decode_memory_link_metadata(link.metadata_json) or { continue }
		to_key := replay_source_key(link.to_table_name, link.to_primary_key, link.to_column_name)
		score := if metadata.score > 0 { metadata.score } else { base_score }
		current := candidate_keys[to_key] or { -1.0 }
		if score > current {
			candidate_keys[to_key] = score
		}
		existing := evidence_by_key[to_key] or { ReplayEvidenceHit{} }
		if existing.table_name.len > 0 && existing.score >= score {
			continue
		}
		evidence_by_key[to_key] = ReplayEvidenceHit{
			table_name:       link.to_table_name
			primary_key:      link.to_primary_key.clone()
			column_name:      link.to_column_name
			score:            score
			anchor:           metadata.anchor
			path_hint:        metadata.path_hint
			text:             metadata.text
			via_link_kind:    'semantic_neighbor'
			source_target_id: metadata.target_id
		}
	}
	mut evidence_hits := []ReplayEvidenceHit{}
	for key in evidence_by_key.keys() {
		evidence_hits << evidence_by_key[key]
	}
	evidence_hits.sort_with_compare(fn (a &ReplayEvidenceHit, b &ReplayEvidenceHit) int {
		if a.score > b.score {
			return -1
		}
		if a.score < b.score {
			return 1
		}
		a_key := replay_source_key(a.table_name, a.primary_key, a.column_name)
		b_key := replay_source_key(b.table_name, b.primary_key, b.column_name)
		if a_key < b_key {
			return -1
		}
		if a_key > b_key {
			return 1
		}
		return 0
	})
	if evidence_hits.len > neighbor_limit {
		evidence_hits = evidence_hits[..neighbor_limit].clone()
	}
	mut reflections_by_id := map[string]ReplayReflectionHit{}
	mut reflection_scores := map[string]f64{}
	for link in links {
		if link.link_kind != 'derived_from' || link.from_table_name != 'memory_reflections' {
			continue
		}
		to_key := replay_source_key(link.to_table_name, link.to_primary_key, link.to_column_name)
		score := candidate_keys[to_key] or { continue }
		reflection_id := link.from_primary_key.bytestr()
		current_score := reflection_scores[reflection_id] or { -1.0 }
		if reflection_id !in reflections_by_id {
			row := session.get_row(mut database, 'memory_reflections', link.from_primary_key)!
			reflections_by_id[reflection_id] = decode_persisted_reflection(mut database,
				request.branch_name, row)!
		}
		if score > current_score {
			reflection_scores[reflection_id] = score
		}
	}
	mut reflections := []ReplayReflectionHit{}
	for reflection_id, reflection in reflections_by_id {
		reflections << ReplayReflectionHit{
			...reflection
			score: reflection_scores[reflection_id] or { 0.0 }
		}
	}
	reflections.sort_with_compare(fn (a &ReplayReflectionHit, b &ReplayReflectionHit) int {
		if a.score > b.score {
			return -1
		}
		if a.score < b.score {
			return 1
		}
		if a.reflection_id < b.reflection_id {
			return -1
		}
		if a.reflection_id > b.reflection_id {
			return 1
		}
		return 0
	})
	if reflections.len > reflection_limit {
		reflections = reflections[..reflection_limit].clone()
	}
	return ReplayQueryResult{
		source_hits:   source_hits
		evidence_hits: evidence_hits
		reflections:   reflections
	}
}

pub fn replay_overview_from_result(branch_name string, result ReplayQueryResult) ReplayOverview {
	mut topics := []ReplayTopicView{cap: result.reflections.len}
	for reflection in result.reflections {
		topics << ReplayTopicView{
			reflection_id:   reflection.reflection_id
			title:           reflection.title
			reflection_kind: reflection.reflection_kind
			topic_key:       reflection.topic_key
			score:           reflection.score
			summary_md:      reflection.summary_md
			insight_md:      reflection.insight_md
			evidence_count:  reflection.source_refs.len
		}
	}
	mut evidence := []ReplayEvidenceView{cap: result.evidence_hits.len}
	mut source_keys := []string{}
	mut seen_source_keys := map[string]bool{}
	for hit in result.evidence_hits {
		evidence << ReplayEvidenceView{
			table_name:    hit.table_name
			primary_key:   hit.primary_key.clone()
			column_name:   hit.column_name
			score:         hit.score
			anchor:        hit.anchor
			path_hint:     hit.path_hint
			text:          hit.text
			via_link_kind: hit.via_link_kind
		}
		key := replay_source_key(hit.table_name, hit.primary_key, hit.column_name)
		if key !in seen_source_keys {
			seen_source_keys[key] = true
			source_keys << key
		}
	}
	mut root_hashes := []string{}
	mut seen_root_hashes := map[string]bool{}
	mut reflection_ids := []string{}
	for reflection in result.reflections {
		if reflection.derived_from_root_hash !in seen_root_hashes {
			seen_root_hashes[reflection.derived_from_root_hash] = true
			root_hashes << reflection.derived_from_root_hash
		}
		reflection_ids << reflection.reflection_id
	}
	return ReplayOverview{
		topics:   topics
		evidence: evidence
		timeline: ReplayTimelineView{
			branch_name:              branch_name
			derived_from_root_hashes: root_hashes
			reflection_ids:           reflection_ids
			source_keys:              source_keys
		}
	}
}

pub fn (mut database PersistentDatabase) replay_overview(mut engine EmbeddingEngine, request ReplayQueryRequest) !ReplayOverview {
	result := database.replay_query(mut engine, request)!
	return replay_overview_from_result(request.branch_name, result)
}

pub fn (mut database PersistentDatabase) persist_reflection_job(job ReflectionJob, input ReflectionPersistInput, cfg ChunkConfig, meta CommitMeta) !PersistedReflection {
	if input.summary_md.trim_space().len == 0 {
		return error('reflection summary_md cannot be empty')
	}
	database.ensure_memory_reflections_table()!
	database.ensure_memory_links_table()!
	derived_from_root_hash := database.engine.root_cid_at_branch(job.branch_name)!
	summary_ref := database.ingest_markdown(input.summary_md)!
	insight_ref := if input.insight_md.trim_space().len > 0 {
		database.ingest_markdown(input.insight_md)!
	} else {
		MarkdownRef{}
	}
	reflection_id := rand.uuid_v4()
	created_at := current_datetime_string()
	source_refs := job.source_refs()
	mut row := TypedRowData.new()
	row.set('reflection_id', reflection_id)
	row.set('reflection_kind', job.reflection_kind)
	row.set('title', input.title)
	row.set('summary_md', summary_ref)
	if input.insight_md.trim_space().len > 0 {
		row.set('insight_md', insight_ref)
	} else {
		row.set('insight_md', NullValue{})
	}
	row.set('source_refs', encode_reflection_source_refs(source_refs))
	if input.parent_ref.len > 0 {
		row.set('parent_ref', input.parent_ref)
	} else {
		row.set('parent_ref', NullValue{})
	}
	if input.topic_key.len > 0 {
		row.set('topic_key', input.topic_key)
	} else {
		row.set('topic_key', NullValue{})
	}
	row.set('derived_from_root_hash', derived_from_root_hash)
	if input.supersedes_reflection_id.len > 0 {
		row.set('supersedes_reflection_id', input.supersedes_reflection_id)
	} else {
		row.set('supersedes_reflection_id', NullValue{})
	}
	row.set('created_at', created_at)
	mut writes := TypedWriteSet.new()
	writes.put('memory_reflections', reflection_id.bytes(), row)
	links := build_reflection_links(job, reflection_id, source_refs, derived_from_root_hash,
		created_at)
	for link in links {
		mut link_row := TypedRowData.new()
		link_row.set('link_id', link.link_id)
		link_row.set('link_kind', link.link_kind)
		link_row.set('from_table_name', link.from_table_name)
		link_row.set('from_primary_key_b64', base64.encode(link.from_primary_key))
		if link.from_column_name.len > 0 {
			link_row.set('from_column_name', link.from_column_name)
		} else {
			link_row.set('from_column_name', NullValue{})
		}
		link_row.set('to_table_name', link.to_table_name)
		link_row.set('to_primary_key_b64', base64.encode(link.to_primary_key))
		if link.to_column_name.len > 0 {
			link_row.set('to_column_name', link.to_column_name)
		} else {
			link_row.set('to_column_name', NullValue{})
		}
		link_row.set('metadata_json', link.metadata_json)
		link_row.set('derived_from_root_hash', link.derived_from_root_hash)
		link_row.set('created_at', link.created_at)
		writes.put('memory_links', link.link_id.bytes(), link_row)
	}
	database.apply_typed_write_set(job.branch_name, writes, cfg, meta)!
	return PersistedReflection{
		reflection_id:            reflection_id
		reflection_kind:          job.reflection_kind
		title:                    input.title
		summary_ref:              summary_ref
		insight_ref:              insight_ref
		source_refs:              source_refs
		parent_ref:               input.parent_ref
		topic_key:                input.topic_key
		derived_from_root_hash:   derived_from_root_hash
		supersedes_reflection_id: input.supersedes_reflection_id
		created_at:               created_at
		links:                    links
	}
}

fn reflection_preferred_scope(spec TypedTableSpec, capability MemoryCapabilityDef) MarkdownEmbeddingScope {
	if capability.options.embedding_index.len > 0 {
		for index in spec.indexes {
			if index.name != capability.options.embedding_index {
				continue
			}
			if index.embedding_scope == MarkdownEmbeddingScope.path.str() {
				return .path
			}
			return .block
		}
	}
	return .path
}

fn reflection_seed_text(targets []MarkdownEmbeddingTarget) string {
	mut parts := []string{cap: targets.len}
	for target in targets {
		parts << target.text
	}
	return parts.join('\n\n')
}

fn reflection_default_title(job ReflectionJob) string {
	if job.seed_text.trim_space().len == 0 {
		return '${job.table_name}.${job.column_name} 记忆复盘'
	}
	first_line := job.seed_text.split_into_lines()[0].trim_space()
	if first_line.len == 0 {
		return '${job.table_name}.${job.column_name} 记忆复盘'
	}
	if first_line.len > 32 {
		return first_line[..32]
	}
	return first_line
}

fn reflection_default_topic_key(job ReflectionJob) string {
	return '${job.table_name}:${job.column_name}:${job.reflection_kind}'
}

fn reflection_source_key(table_name string, primary_key []u8, column_name string) string {
	return '${table_name}\x00${base64.encode(primary_key)}\x00${column_name}'
}
