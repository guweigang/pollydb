module memory

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
	summary_md               string
	insight_md               string
	source_refs              []ReflectionSourceRef
	parent_ref               string
	topic_key                string
	derived_from_root_hash   string
	supersedes_reflection_id string
	created_at               string
	links                    []MemoryLink
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

pub struct ReplaySourceHit {
pub:
	target_id   string
	table_name  string
	column_name string
	primary_key []u8
	score       f64
	scope       MarkdownEmbeddingScope
	kind        string
	anchor      string
	path_hint   string
	text        string
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
	source_hits   []ReplaySourceHit
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

pub struct ReflectionOptions {
pub:
	enabled                 bool = true
	embedding_index         string
	reflection_kind         string = 'summary'
	replay_anchor           bool   = true
	link_evidence_blocks    bool   = true
	link_semantic_neighbors bool   = true
}

pub struct MemoryCapabilityDef {
pub:
	table_name  string
	column_name string
	options     ReflectionOptions
}

pub fn MemoryCapabilityDef.reflective_field(table_name string, column_name string, options ReflectionOptions) !MemoryCapabilityDef {
	if table_name.len == 0 {
		return error('memory capability table name cannot be empty')
	}
	if column_name.len == 0 {
		return error('memory capability column name cannot be empty')
	}
	if options.reflection_kind.trim_space().len == 0 {
		return error('memory capability reflection kind cannot be empty')
	}
	return MemoryCapabilityDef{
		table_name:  table_name
		column_name: column_name
		options:     ReflectionOptions{
			enabled:                 options.enabled
			embedding_index:         options.embedding_index.trim_space()
			reflection_kind:         options.reflection_kind.trim_space()
			replay_anchor:           options.replay_anchor
			link_evidence_blocks:    options.link_evidence_blocks
			link_semantic_neighbors: options.link_semantic_neighbors
		}
	}
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

pub struct MemoryLinkMetadataDto {
pub:
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

const reflection_begin_marker = 'BEGIN_REFLECTION'
const reflection_end_marker = 'END_REFLECTION'

pub interface ReflectionTextGenerator {
mut:
	generate(prompt string) !string
}

pub struct ReflectionDistillOptions {
pub:
	title        string
	topic_key    string
	parent_ref   string
	max_evidence int = 8
}

pub fn reflection_default_title(job ReflectionJob) string {
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

pub fn reflection_default_topic_key(job ReflectionJob) string {
	return '${job.table_name}:${job.column_name}:${job.reflection_kind}'
}

pub fn reflection_distillation_prompt(job ReflectionJob, options ReflectionDistillOptions) string {
	limit := if options.max_evidence > 0 { options.max_evidence } else { 8 }
	mut evidence_lines := []string{cap: job.evidence.len}
	for idx, evidence in job.evidence {
		if idx >= limit {
			break
		}
		evidence_lines << '- score=${evidence.score:.4f} source=${evidence.table_name}.${evidence.column_name} anchor=${evidence.anchor} path=${evidence.path_hint}\n${evidence.text}'
	}
	title_hint := if options.title.len > 0 { options.title } else { '未命名记忆复盘' }
	topic_hint := if options.topic_key.len > 0 { options.topic_key } else { '' }
	return [
		'你是 PollyDB Agent 记忆系统的本地反思器。',
		'请基于给定 seed 和 evidence 生成一条可复盘的 Markdown 蒸馏记忆。',
		'要求：',
		'1. 不要编造 evidence 之外的事实。',
		'2. 用中文输出；代码名、文件名、函数名保持原样。',
		'3. 输出必须严格包在 ${reflection_begin_marker} 和 ${reflection_end_marker} 之间。',
		'4. 输出格式必须包含 TITLE、TOPIC、SUMMARY_MD、INSIGHT_MD 四段。',
		'5. SUMMARY_MD 和 INSIGHT_MD 必须是 Markdown。',
		'6. 每段最多 2 个要点，避免重复同一句话。',
		'7. 如果 evidence 已经很明确，只总结架构边界和下一步，不要展开背景知识。',
		'8. 禁止把 SQLite 或 USearch 描述成真相存储；SQLite 只能是 FTS，USearch 只能是 ANN 派生索引。',
		'',
		'期望格式：',
		reflection_begin_marker,
		'TITLE: ${title_hint}',
		'TOPIC: ${topic_hint}',
		'SUMMARY_MD:',
		'# Summary',
		'',
		'- ...',
		'',
		'INSIGHT_MD:',
		'## Insight',
		'',
		'- ...',
		reflection_end_marker,
		'',
		'Reflection kind: ${job.reflection_kind}',
		'Seed scope: ${job.seed_scope.str()}',
		'Seed anchor: ${job.seed_anchor}',
		'Seed:',
		job.seed_text,
		'',
		'Evidence:',
		evidence_lines.join('\n\n'),
	].join('\n')
}

pub fn generate_reflection_persist_input(job ReflectionJob, mut generator ReflectionTextGenerator, options ReflectionDistillOptions) !ReflectionPersistInput {
	prompt := reflection_distillation_prompt(job, options)
	raw := generator.generate(prompt)!
	mut input := parse_reflection_generation(raw)!
	if input.title.len == 0 {
		input = ReflectionPersistInput{
			...input
			title: if options.title.len > 0 { options.title } else { '未命名记忆复盘' }
		}
	}
	if input.topic_key.len == 0 && options.topic_key.len > 0 {
		input = ReflectionPersistInput{
			...input
			topic_key: options.topic_key
		}
	}
	if input.parent_ref.len == 0 && options.parent_ref.len > 0 {
		input = ReflectionPersistInput{
			...input
			parent_ref: options.parent_ref
		}
	}
	return normalize_reflection_persist_input(job, input)
}

pub fn parse_reflection_generation(raw string) !ReflectionPersistInput {
	body := reflection_generation_body(raw).trim_space()
	if body.len == 0 {
		return error('reflection generation output is empty')
	}
	lines := body.split_into_lines()
	mut title := ''
	mut topic_key := ''
	mut section := ''
	mut summary_lines := []string{}
	mut insight_lines := []string{}
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('TITLE:') {
			title = trimmed['TITLE:'.len..].trim_space()
			continue
		}
		if trimmed.starts_with('TOPIC:') {
			topic_key = trimmed['TOPIC:'.len..].trim_space()
			continue
		}
		if trimmed == 'SUMMARY_MD:' {
			section = 'summary'
			continue
		}
		if trimmed == 'INSIGHT_MD:' || trimmed == 'INSIGHT:' || trimmed == '## Insight'
			|| trimmed == '# Insight' {
			section = 'insight'
			if trimmed.starts_with('#') {
				insight_lines << line
			}
			continue
		}
		match section {
			'summary' { summary_lines << line }
			'insight' { insight_lines << line }
			else {}
		}
	}
	summary_md := summary_lines.join('\n').trim_space()
	if summary_md.len == 0 {
		return error('reflection generation missing SUMMARY_MD')
	}
	return ReflectionPersistInput{
		title:      title
		summary_md: summary_md + '\n'
		insight_md: if insight_lines.len > 0 {
			insight_lines.join('\n').trim_space() + '\n'
		} else {
			''
		}
		topic_key:  topic_key
	}
}

fn reflection_generation_body(raw string) string {
	begin_idx := raw.last_index(reflection_begin_marker) or { return raw }
	after_begin := begin_idx + reflection_begin_marker.len
	tail := raw[after_begin..]
	end_idx := tail.index(reflection_end_marker) or { return strip_llama_cli_tail(tail) }
	return tail[..end_idx]
}

fn strip_llama_cli_tail(raw string) string {
	mut end := raw.len
	for marker in ['llama_memory_breakdown_print:', 'common_perf_print:', '\nExiting...'] {
		idx := raw.index(marker) or { continue }
		if idx < end {
			end = idx
		}
	}
	return raw[..end]
}

fn normalize_reflection_persist_input(job ReflectionJob, input ReflectionPersistInput) ReflectionPersistInput {
	return ReflectionPersistInput{
		...input
		summary_md: compact_reflection_markdown(input.summary_md, '# Summary', 2)
		insight_md: compact_reflection_markdown(if input.insight_md.trim_space().len > 0 {
			input.insight_md
		} else {
			reflection_fallback_insight(job)
		}, '## Insight', 2)
	}
}

fn compact_reflection_markdown(raw string, fallback_heading string, max_points int) string {
	lines := raw.split_into_lines()
	mut heading := ''
	mut points := []string{}
	limit := if max_points > 0 { max_points } else { 2 }
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		if heading.len == 0 && trimmed.starts_with('#') {
			heading = trimmed
			continue
		}
		if reflection_markdown_is_point(trimmed) {
			if points.len < limit {
				points << trimmed
			}
			continue
		}
		if points.len == 0 && !trimmed.starts_with('#') {
			points << '- ${trimmed}'
		}
		if points.len >= limit {
			break
		}
	}
	if heading.len == 0 {
		heading = fallback_heading
	}
	if points.len == 0 {
		points << '- 保留这次复盘的证据链，后续查询应回到原始记忆。'
	}
	return '${heading}\n\n${points.join('\n')}\n'
}

fn reflection_markdown_is_point(line string) bool {
	if line.starts_with('- ') || line.starts_with('* ') {
		return true
	}
	if line.len < 3 {
		return false
	}
	dot_idx := line.index('.') or { return false }
	if dot_idx == 0 || dot_idx > 2 {
		return false
	}
	return line[..dot_idx].bytes().all(it >= `0` && it <= `9`)
}

fn reflection_fallback_insight(job ReflectionJob) string {
	if job.seed_text.contains('SQLite') || job.seed_text.contains('USearch')
		|| job.evidence.any(it.text.contains('SQLite') || it.text.contains('USearch')) {
		return '## Insight\n\n- PollyDB 继续持有真相；SQLite FTS 和 USearch 只作为可重建索引视图。\n'
	}
	return '## Insight\n\n- 这条反思必须保留 source_refs 与 root hash，复盘时回到原始 evidence。\n'
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

pub fn reflection_job_source_refs(job ReflectionJob) []ReflectionSourceRef {
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

pub fn decode_memory_link_metadata(raw string) !MemoryLinkMetadataDto {
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

pub fn replay_overview(branch_name string, evidence_hits []ReplayEvidenceHit, reflections []ReplayReflectionHit) ReplayOverview {
	mut topics := []ReplayTopicView{cap: reflections.len}
	for reflection in reflections {
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
	mut evidence := []ReplayEvidenceView{cap: evidence_hits.len}
	mut source_keys := []string{}
	mut seen_source_keys := map[string]bool{}
	for hit in evidence_hits {
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
		key := '${hit.table_name}\x00${base64.encode(hit.primary_key)}\x00${hit.column_name}'
		if key !in seen_source_keys {
			seen_source_keys[key] = true
			source_keys << key
		}
	}
	mut root_hashes := []string{}
	mut seen_root_hashes := map[string]bool{}
	mut reflection_ids := []string{}
	for reflection in reflections {
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

pub fn reflection_source_key(table_name string, primary_key []u8, column_name string) string {
	return '${table_name}\x00${base64.encode(primary_key)}\x00${column_name}'
}
