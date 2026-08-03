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
	reflection_kind          string
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

pub struct SceneBlock {
pub:
	scene_id          string
	repo              string
	cwd               string
	topic             string
	workflow          string
	time_start        string
	time_end          string
	atomic_memory_ids []string
	metadata_json     string
	created_at        string
	updated_at        string
}

pub struct PersonaProfile {
pub:
	persona_id      string
	preference_kind string
	content         string
	created_at      string
}

// ReflectionEvolutionNode 表示记忆演化链上的一个节点
pub struct ReflectionEvolutionNode {
pub:
	reflection_id            string
	reflection_kind          string
	title                    string
	summary_md               string
	insight_md               string
	topic_key                string
	parent_ref               string
	derived_from_root_hash   string
	supersedes_reflection_id string
	created_at               string
	source_count             int
	depth                    int // 从链尾回溯的深度(0 = 最新)
}

// ReflectionEvolutionChain 表示一条记忆的完整演化链（从最新回溯到最早祖先）
pub struct ReflectionEvolutionChain {
pub:
	root_reflection_id string // 链的起点（查询时的 reflection_id）
	nodes              []ReflectionEvolutionNode // depth=0 是最新节点，depth=N-1 是最早祖先
}

// ReflectionSupersedeNode 表示记忆更替图上的一个节点
pub struct ReflectionSupersedeNode {
pub:
	reflection_id            string
	title                    string
	reflection_kind          string
	topic_key                string
	supersedes_reflection_id string // 当前卡片更替了谁
	superseded_by_ids        []string // 谁更替了当前卡片
	created_at               string
	active                   bool // 是否还是活跃的（未被更替）
}

// ReflectionSupersedeGraph 表示围绕一条记忆的更替关系图
pub struct ReflectionSupersedeGraph {
pub:
	root_reflection_id string
	nodes              map[string]ReflectionSupersedeNode // key 是 reflection_id
}

// MemoryEvolutionRequest 查询记忆演化链的请求
pub struct MemoryEvolutionRequest {
pub:
	reflection_id string
}

// MemorySupersedeRequest 查询记忆更替图的请求
pub struct MemorySupersedeRequest {
pub:
	reflection_id string
}

// SceneCardAdditionEvent 表示一张卡片在某个 commit 中被添加到场景的事件
pub struct SceneCardAdditionEvent {
pub:
	reflection_id  string // 被添加的卡片 ID
	commit_cid     string // 添加发生的 commit CID
	commit_message string // commit 的 message
	commit_author  string // commit 的作者
	commit_time    i64 // commit 的时间戳
	position       int // 添加后在 atomic_memory_ids 中的位置
}

// SceneBlockCardTimeline 表示一个场景块中记忆卡片的完整添加时间线
// 通过回溯 commit 历史重建，不依赖物理 memory_chain 链接
pub struct SceneBlockCardTimeline {
pub:
	scene_id          string
	repo              string
	cwd               string
	topic             string
	current_card_ids  []string // 当前场景中的卡片 ID 列表（最新状态）
	events            []SceneCardAdditionEvent // 按时间顺序排列的添加事件
	total_commits     int // 扫描的总 commit 数
	matching_commits  int // 命中 scene_block 的 commit 数
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
	branch_name       string
	text              string
	seed_limit        int = 4
	neighbor_limit    int = 8
	reflection_limit  int = 4
	as_of_commit_cid  string // 如果设置，只返回该 commit 时间点及之前存在的记忆卡片和链接
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
const recap_begin_marker = 'BEGIN_RECAP'
const recap_end_marker = 'END_RECAP'

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

struct ReflectionOutline {
	title             string
	title_basis       string
	summary_points    []string
	decision_points   []string
	constraint_points []string
	insight_points    []string
	distillable       bool
}

pub fn reflection_default_title(job ReflectionJob) string {
	outline := build_reflection_outline(job, ReflectionDistillOptions{})
	if outline.title.len > 0 {
		return outline.title
	}
	return '${job.table_name}.${job.column_name} 记忆复盘'
}

pub fn reflection_default_topic_key(job ReflectionJob) string {
	return '${job.table_name}:${job.column_name}:${job.reflection_kind}'
}

pub fn reflection_job_has_distillable_outline(job ReflectionJob, options ReflectionDistillOptions) bool {
	return build_reflection_outline(job, options).distillable
}

pub fn reflection_distillation_prompt(job ReflectionJob, options ReflectionDistillOptions) string {
	outline := build_reflection_outline(job, options)
	limit := if options.max_evidence > 0 { options.max_evidence } else { 8 }
	mut evidence_lines := []string{cap: job.evidence.len}
	for idx, evidence in job.evidence {
		if idx >= limit {
			break
		}
		evidence_lines << '- score=${evidence.score:.4f} source=${evidence.table_name}.${evidence.column_name} anchor=${evidence.anchor} path=${evidence.path_hint}\n${evidence.text}'
	}
	title_hint := if options.title.len > 0 {
		options.title
	} else if outline.title.len > 0 {
		outline.title
	} else {
		'未命名记忆复盘'
	}
	topic_hint := if options.topic_key.len > 0 { options.topic_key } else { '' }
	kind_hint := if job.reflection_kind.len > 0 { job.reflection_kind } else { 'fact' }
	return [
		'你是 PollyDB Agent 记忆系统的本地反思器。',
		'请基于给定 seed 和 evidence 蒸馏提取一条短小、高价值的原子记忆。',
		'要求：',
		'1. 不要编造 evidence 之外的事实，只提取确实存在且极具参考价值的内容。',
		'2. 用中文输出；代码名、文件名、函数名保持原样。',
		'3. 输出必须严格包在 ${reflection_begin_marker} 和 ${reflection_end_marker} 之间。',
		'4. 输出格式必须为：',
		'   TITLE: <单行标题，如：对 L1/L2/L3 分层记忆设计的物理层映射决策>',
		'   KIND: <以下四个分类之一：fact, constraint, decision, state>',
		'   TOPIC: <单行主题，通常可以用作索引关联标签，如：memory_refactoring>',
		'   CONTENT:',
		'   <核心陈述内容，可以是单行或 1-2 行极其精炼的 Markdown，禁止废话和客套>',
		'   EVIDENCE:',
		'   <直接引用原始对话、日志或代码行片段的核心证据，指明出处，用作追溯依据>',
		'5. 绝对不要包含 "# 摘要", "## 关键决策", "## 重要约束", "## 后续关注" 等臃肿的 Markdown 二级标题标签，只写极简的原生内容！',
		'6. KIND 分类准则：',
		'   - fact: 客观物理事实、环境事实或不可变的基本面；',
		'   - constraint: 限制性规则、禁止项、编码边界或硬性约束（如“绝对禁止...”）；',
		'   - decision: 技术、方案或设计上的已定决策，避免未来重复纠结（如“决定使用...”）；',
		'   - state: 开发进度、任务所处的状态（如“正在重构...”）；',
		'',
		'期望格式：',
		reflection_begin_marker,
		'TITLE: ${title_hint}',
		'KIND: ${kind_hint}',
		'TOPIC: ${topic_hint}',
		'CONTENT:',
		'- ...',
		'EVIDENCE:',
		'- ...',
		reflection_end_marker,
		'',
		'结构化抽取：',
		'主题标题候选: ' + outline.title,
		'摘要要点:',
		outline.summary_points.join('\n'),
		'关键决策候选:',
		outline.decision_points.join('\n'),
		'重要约束候选:',
		outline.constraint_points.join('\n'),
		'后续关注候选:',
		outline.insight_points.join('\n'),
		'',
		'Reflection kind: ${kind_hint}',
		'Seed scope: ${job.seed_scope.str()}',
		'Seed anchor: ${job.seed_anchor}',
		'Seed:',
		job.seed_text,
		'',
		'Evidence:',
		evidence_lines.join('\n\n'),
	].join('\n')
}

// reflection_recap_prompt 生成 Claude 风格的 recap 提示词
// 产出精炼的一句话技术洞察，包含具体文件名/函数名和原因解释
pub fn reflection_recap_prompt(job ReflectionJob, options ReflectionDistillOptions) string {
	outline := build_reflection_outline(job, options)
	limit := if options.max_evidence > 0 { options.max_evidence } else { 8 }
	mut evidence_lines := []string{cap: job.evidence.len}
	for idx, evidence in job.evidence {
		if idx >= limit {
			break
		}
		evidence_lines << '- ${evidence.table_name}.${evidence.column_name} anchor=${evidence.anchor} path=${evidence.path_hint}\n${evidence.text}'
	}
	title_hint := if options.title.len > 0 {
		options.title
	} else if outline.title.len > 0 {
		outline.title
	} else {
		'技术洞察'
	}
	topic_hint := if options.topic_key.len > 0 { options.topic_key } else { '' }
	return [
		'你是 PollyDB Agent 记忆系统的本地反思器。',
		'请基于 seed 和 evidence 生成一条 Claude 风格的 recap。',
		'',
		'Recap 风格要求：',
		'1. 一句话说清楚做了什么、怎么做的、为什么这样做。',
		'2. 必须包含具体的技术细节：文件名、函数名、关键变量名、具体的配置值。',
		'3. 解释因果关系，而不仅仅是陈述事实。',
		'4. 用中文输出；代码名、文件名、函数名保持原样。',
		'5. 控制在 1-2 句话以内，不要超过 200 字。',
		'6. 每条 recap 聚焦一个单一技术洞察，不要把多个不相关的发现合并。',
		'',
		'好的 recap 示例：',
		'※ recap: 修复了 V 编译器中符号链接模块无法导入的 bug，在 candidate_belongs_to_foreign_project (builder.v) 中新增对原始 symlink 路径的检查，之前只检查了 resolve 后的真实路径导致查找失败。',
		'※ recap: 将 pollydb 的 ChunkStore 写入路径从 writev 改为 mmap+msync，因为在高并发写入时 writev 的 scatter-gather 导致磁盘 I/O 碎片化，mmap 的连续地址空间将 p99 延迟从 12ms 降到 3ms。',
		'※ recap: 决定在 L1 memory_reflections 表中新增 parent_ref 字段建立演化链，替代之前仅依赖 memory_chain 物理链接的方案，因为 parent_ref 利用 pollydb 的 commit 不可变特性天然避免了链接悬空问题。',
		'',
		'坏的 recap 示例（禁止）：',
		'※ recap: 修复了一个 bug。  （太模糊，没有技术细节）',
		'※ recap: 我们讨论了几个方案，最后决定用方案A。  （没有技术细节和原因）',
		'※ recap: 代码重构了一下让性能更好。  （没有具体指标和方法）',
		'',
		'输出格式：',
		'输出必须严格包在 ${recap_begin_marker} 和 ${recap_end_marker} 之间。',
		'格式为：',
		'TITLE: <单行标题>',
		'TOPIC: <主题标签>',
		'RECAP: <※ recap: 一句话技术洞察>',
		'',
		'示例输出：',
		recap_begin_marker,
		'TITLE: ${title_hint}',
		'TOPIC: ${topic_hint}',
		'RECAP: ※ recap: 修复了...',
		recap_end_marker,
		'',
		'主题标题候选: ' + outline.title,
		'摘要要点:',
		outline.summary_points.join('\n'),
		'关键决策候选:',
		outline.decision_points.join('\n'),
		'',
		'Seed:',
		job.seed_text,
		'',
		'Evidence:',
		evidence_lines.join('\n\n'),
	].join('\n')
}

// parse_recap_generation 解析 recap 风格的 LLM 输出
pub fn parse_recap_generation(raw string) !ReflectionPersistInput {
	body := recap_generation_body(raw).trim_space()
	if body.len == 0 {
		return error('recap generation output is empty')
	}
	lines := body.split_into_lines()
	mut title := ''
	mut topic_key := ''
	mut recap_text := ''
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
		if trimmed.starts_with('RECAP:') {
			recap_text = trimmed['RECAP:'.len..].trim_space()
			continue
		}
		// 如果某行直接是 ※ recap: 开头，也接受
		if trimmed.starts_with('※ recap:') {
			recap_text = trimmed['※ recap:'.len..].trim_space()
			continue
		}
		// 收集未标记的内容作为 recap 正文
		if recap_text.len == 0 && trimmed.len > 0 && !trimmed.starts_with('#') {
			recap_text = trimmed
		}
	}
	if recap_text.len == 0 {
		return error('recap generation missing RECAP field')
	}
	// 确保 recap 以 ※ recap: 开头
	if !recap_text.starts_with('※ recap:') && !recap_text.starts_with('※recap:') {
		recap_text = '※ recap: ' + recap_text
	}
	return ReflectionPersistInput{
		title:           title
		topic_key:       topic_key
		summary_md:      recap_text + '\n'
		insight_md:      ''
		reflection_kind: 'recap'
	}
}

fn recap_generation_body(raw string) string {
	begin_idx := raw.last_index(recap_begin_marker) or { return raw }
	after_begin := begin_idx + recap_begin_marker.len
	tail := raw[after_begin..]
	end_idx := tail.index(recap_end_marker) or { return strip_llama_cli_tail(tail) }
	return tail[..end_idx]
}

// generate_recap_persist_input 使用 recap 风格提示词生成记忆卡片
pub fn generate_recap_persist_input(job ReflectionJob, mut generator ReflectionTextGenerator, options ReflectionDistillOptions) !ReflectionPersistInput {
	prompt := reflection_recap_prompt(job, options)
	raw := generator.generate(prompt)!
	mut input := parse_recap_generation(raw)!
	if input.title.len == 0 {
		outline := build_reflection_outline(job, options)
		input = ReflectionPersistInput{
			...input
			title: if options.title.len > 0 {
				options.title
			} else if outline.title.len > 0 {
				outline.title
			} else {
				'技术洞察'
			}
		}
	}
	if input.topic_key.len == 0 && options.topic_key.len > 0 {
		input = ReflectionPersistInput{
			...input
			topic_key: options.topic_key
		}
	}
	return input
}

pub fn generate_reflection_persist_input(job ReflectionJob, mut generator ReflectionTextGenerator, options ReflectionDistillOptions) !ReflectionPersistInput {
	outline := build_reflection_outline(job, options)
	prompt := reflection_distillation_prompt(job, options)
	raw := generator.generate(prompt)!
	mut input := parse_reflection_generation(raw)!
	if input.title.len == 0 {
		input = ReflectionPersistInput{
			...input
			title: if options.title.len > 0 {
				options.title
			} else if outline.title.len > 0 {
				outline.title
			} else {
				'未命名记忆复盘'
			}
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
	mut normalized := normalize_reflection_persist_input(job, input)
	normalized = reconcile_reflection_with_outline(normalized, outline)
	fallback := reflection_outline_persist_input(job, options, outline)
	if reflection_persist_input_needs_fallback(outline, normalized) {
		return fallback
	}
	return normalized
}

pub fn heuristic_reflection_persist_input(job ReflectionJob, options ReflectionDistillOptions) ReflectionPersistInput {
	return reflection_outline_persist_input(job, options, build_reflection_outline(job, options))
}

// heuristic_recap_persist_input 为 recap 风格生成启发式卡片（不经过 LLM）
pub fn heuristic_recap_persist_input(job ReflectionJob, options ReflectionDistillOptions) ReflectionPersistInput {
	outline := build_reflection_outline(job, options)
	title := if options.title.len > 0 {
		options.title
	} else if outline.title.len > 0 {
		outline.title
	} else {
		'${job.table_name}.${job.column_name} 技术洞察'
	}
	topic_key := if options.topic_key.len > 0 {
		options.topic_key
	} else {
		reflection_default_topic_key(job)
	}
	// 从 outline 提取最精炼的一句话作为 recap
	mut recap_parts := []string{}
	if outline.decision_points.len > 0 {
		recap_parts << outline.decision_points[0].trim('- *。，:： ')
	}
	if outline.summary_points.len > 0 {
		for point in outline.summary_points {
			cleaned := point.trim('- *。，:： ')
			if cleaned.len > 0 && cleaned !in recap_parts {
				recap_parts << cleaned
				break
			}
		}
	}
	recap_text := if recap_parts.len > 0 {
		recap_parts.join('；')
	} else {
		'从 ${job.evidence.len} 条近邻证据中提取的技术上下文'
	}
	return ReflectionPersistInput{
		title:           title
		topic_key:       topic_key
		summary_md:      '※ recap: ${recap_text}\n'
		insight_md:      ''
		reflection_kind: 'recap'
	}
}

fn compact_reflection_line(text string) string {
	single_line := text.replace('\r', ' ').replace('\n', ' ').trim_space()
	if single_line.len <= 120 {
		return single_line
	}
	mut out := ''
	mut boundary_len := 0
	for r in single_line.runes() {
		ch := r.str()
		if out.len + ch.len > 120 {
			break
		}
		out += ch
		if ch in ['。', '；', ';', '.', '，', ','] {
			boundary_len = out.len
		}
	}
	if boundary_len >= 24 {
		return out[..boundary_len].trim_space().trim('，,;； ')
	}
	return out.trim_space().trim('，。:：,;； ')
}

pub fn parse_reflection_generation(raw string) !ReflectionPersistInput {
	body := reflection_generation_body(raw).trim_space()
	if body.len == 0 {
		return error('reflection generation output is empty')
	}
	lines := body.split_into_lines()
	mut title := ''
	mut kind := ''
	mut topic_key := ''
	mut section := ''
	mut content_lines := []string{}
	mut evidence_lines := []string{}
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('TITLE:') {
			title = trimmed['TITLE:'.len..].trim_space()
			continue
		}
		if trimmed.starts_with('KIND:') {
			kind = trimmed['KIND:'.len..].trim_space().to_lower()
			continue
		}
		if trimmed.starts_with('TOPIC:') {
			topic_key = trimmed['TOPIC:'.len..].trim_space()
			continue
		}
		if trimmed == 'CONTENT:' || trimmed == 'SUMMARY_MD:' {
			section = 'content'
			continue
		}
		if trimmed == 'EVIDENCE:' || trimmed == 'INSIGHT_MD:' || trimmed == 'INSIGHT:' || trimmed == '## Insight' || trimmed == '# Insight' {
			section = 'evidence'
			continue
		}
		match section {
			'content' { content_lines << line }
			'evidence' { evidence_lines << line }
			else {}
		}
	}
	summary_md := content_lines.join('\n').trim_space()
	insight_md := evidence_lines.join('\n').trim_space()
	if summary_md.len == 0 {
		return error('reflection generation missing CONTENT or SUMMARY_MD')
	}
	return ReflectionPersistInput{
		title:      title
		summary_md: summary_md + '\n'
		insight_md: if insight_md.len > 0 {
			insight_md + '\n'
		} else {
			''
		}
		topic_key:       topic_key
		reflection_kind: kind
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
	if input.reflection_kind in ['fact', 'constraint', 'decision', 'state'] {
		return input
	}
	return ReflectionPersistInput{
		...input
		summary_md: compact_reflection_summary_markdown(input.summary_md)
		insight_md: compact_reflection_markdown(if input.insight_md.trim_space().len > 0 {
			input.insight_md
		} else {
			reflection_fallback_insight(job)
		}, '## 后续关注', 2)
	}
}

fn reconcile_reflection_with_outline(input ReflectionPersistInput, outline ReflectionOutline) ReflectionPersistInput {
	if input.reflection_kind in ['fact', 'constraint', 'decision', 'state'] {
		return input
	}
	summary_points := reflection_section_points(input.summary_md, '# 摘要')
	insight_points := reflection_summary_points(input.insight_md)
	final_summary := if reflection_points_match_outline(summary_points, outline.summary_points) {
		summary_points
	} else {
		outline.summary_points
	}
	final_decisions := outline.decision_points
	final_constraints := outline.constraint_points
	final_insight := if reflection_points_look_like_boilerplate(insight_points) {
		outline.insight_points
	} else if insight_points.len > 0 {
		insight_points
	} else {
		outline.insight_points
	}
	return ReflectionPersistInput{
		...input
		summary_md: reflection_summary_markdown(final_summary, final_decisions, final_constraints)
		insight_md: '## 后续关注\n\n' + final_insight.join('\n') + '\n'
	}
}

fn compact_reflection_summary_markdown(raw string) string {
	summary := reflection_polish_points(compact_reflection_markdown_section_points(raw, [
		'# 摘要',
	], 2), 2)
	decisions := reflection_polish_points(compact_reflection_markdown_section_points(raw, [
		'## 关键决策',
	], 2), 2)
	constraints := reflection_polish_points(compact_reflection_markdown_section_points(raw, [
		'## 重要约束',
	], 2), 2)
	return reflection_summary_markdown(summary, decisions, constraints)
}

fn reflection_section_points(raw string, heading string) []string {
	lines := raw.split_into_lines()
	mut in_section := false
	mut points := []string{}
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		if trimmed == heading {
			in_section = true
			continue
		}
		if in_section && trimmed.starts_with('#') {
			break
		}
		if !in_section {
			continue
		}
		if reflection_markdown_is_point(trimmed) {
			points << trimmed
		}
	}
	return points
}

fn compact_reflection_markdown_section_points(raw string, headings []string, max_points int) []string {
	lines := raw.split_into_lines()
	mut in_section := false
	mut points := []string{}
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		if trimmed in headings {
			in_section = true
			continue
		}
		if in_section && trimmed.starts_with('#') {
			break
		}
		if !in_section {
			continue
		}
		if reflection_markdown_is_point(trimmed) {
			if points.len < max_points {
				points << trimmed
			}
			continue
		}
		if points.len == 0 {
			points << '- ${trimmed}'
		}
		if points.len >= max_points {
			break
		}
	}
	return points
}

fn reflection_summary_markdown(summary_points []string, decision_points []string, constraint_points []string) string {
	mut sections := []string{}
	mut summary := reflection_polish_points(summary_points, 2)
	decisions := reflection_polish_points(decision_points, 2)
	constraints := reflection_polish_points(constraint_points, 2)
	if summary.len == 0 {
		summary << '- 当前主题已从 seed 与近邻证据中完成一次可回放蒸馏。'
	}
	sections << '# 摘要\n\n' + summary.join('\n')
	if decisions.len > 0 {
		sections << '## 关键决策\n\n' + decisions.join('\n')
	}
	if constraints.len > 0 {
		sections << '## 重要约束\n\n' + constraints.join('\n')
	}
	return sections.join('\n\n') + '\n'
}

fn reflection_polish_points(points []string, limit int) []string {
	mut out := []string{}
	mut seen := map[string]bool{}
	max_points := if limit > 0 { limit } else { points.len }
	for point in points {
		polished := reflection_polish_point(point)
		if reflection_looks_like_low_information_point(polished) {
			continue
		}
		key := compact_reflection_comparison_key(polished)
		if key.len == 0 || key in seen {
			continue
		}
		if reflection_point_subsumed_by_seen(key, seen) {
			continue
		}
		seen[key] = true
		out << polished
		if out.len >= max_points {
			break
		}
	}
	return out
}

fn reflection_point_subsumed_by_seen(key string, seen map[string]bool) bool {
	if key.len < 8 {
		return false
	}
	for existing, _ in seen {
		if existing.contains(key) || key.contains(existing) {
			return true
		}
	}
	return false
}

fn reflection_polish_point(point string) string {
	mut text := reflection_strip_bullet_prefix(point)
	text = reflection_rewrite_change_statement(text)
	text = reflection_rewrite_first_person_decision(text)
	text = strip_reflection_sentence_prefix(text)
	text = reflection_strip_vague_leading_clause(text)
	text = reflection_stabilize_diagnostic_claim(text)
	text = text.trim('，。:： ')
	return '- ' + compact_reflection_line(text)
}

fn reflection_strip_bullet_prefix(text string) string {
	mut out := text.trim_space()
	mut stripped := true
	for stripped {
		stripped = false
		for prefix in ['- ', '* '] {
			if !out.starts_with(prefix) {
				continue
			}
			out = out[prefix.len..].trim_space()
			stripped = true
		}
	}
	return out
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
		return '## 后续关注\n\n- PollyDB 继续持有真相；SQLite FTS 和 USearch 只作为可重建索引视图。\n'
	}
	return '## 后续关注\n\n- 这条反思必须保留 source_refs 与 root hash，复盘时回到原始 evidence。\n'
}

fn reflection_persist_input_needs_fallback(outline ReflectionOutline, input ReflectionPersistInput) bool {
	_ = outline
	if input.reflection_kind in ['fact', 'constraint', 'decision', 'state'] {
		return false
	}
	if strip_reflection_title_prefix(input.title).len == 0 {
		return true
	}
	points := reflection_summary_points(input.summary_md)
	if points.len == 0 {
		return true
	}
	normalized_points := points.map(compact_reflection_comparison_key(it)).filter(it.len > 0)
	if normalized_points.len >= 3 && normalized_points.all(it == normalized_points[0]) {
		return true
	}
	if compact_reflection_comparison_key(input.summary_md) == compact_reflection_comparison_key(input.insight_md) {
		return true
	}
	return false
}

fn reflection_points_match_outline(points []string, expected []string) bool {
	if points.len == 0 || expected.len == 0 {
		return false
	}
	normalized_points := points.map(compact_reflection_comparison_key(it)).filter(it.len > 0)
	normalized_expected := expected.map(compact_reflection_comparison_key(it)).filter(it.len > 0)
	if normalized_points.len == 0 || normalized_expected.len == 0 {
		return false
	}
	mut matches := 0
	for item in normalized_expected {
		if normalized_points.any(it.contains(item) || item.contains(it)) {
			matches++
		}
	}
	return matches > 0
}

fn reflection_points_look_like_boilerplate(points []string) bool {
	if points.len == 0 {
		return true
	}
	joined := compact_reflection_comparison_key(points.join('\n'))
	for marker in [
		'继续以原始entry和证据链作为这条记忆的事实来源',
		'若缺少直接证据不要把这条记忆提升为更强结论',
		'当前主题的语义近邻较少适合先累计更多同类entry再做更强蒸馏',
		'后续查询应优先命中这条主题标题再回放到原始证据',
	] {
		if joined.contains(compact_reflection_comparison_key(marker)) {
			return true
		}
	}
	return false
}

fn reflection_summary_points(raw string) []string {
	mut points := []string{}
	for line in raw.split_into_lines() {
		trimmed := line.trim_space()
		if reflection_markdown_is_point(trimmed) {
			points << trimmed
		}
	}
	return points
}

fn compact_reflection_comparison_key(text string) string {
	return text.to_lower().replace('\r', '').replace('\n', '').replace(' ', '').replace('\t', '').replace('-',
		'').replace('*', '').replace('#', '').trim('，。:：`"\'()[]')
}

fn build_reflection_outline(job ReflectionJob, options ReflectionDistillOptions) ReflectionOutline {
	candidates := reflection_candidates(job)
	title := if options.title.len > 0 {
		options.title
	} else {
		reflection_title_from_candidates(candidates)
	}
	title_key := compact_reflection_comparison_key(title)
	summary_candidates := candidates.filter(compact_reflection_comparison_key(it.text) != title_key)
	mut summary_points := reflection_pick_candidate_points(summary_candidates, 2, [
		.decision,
		.constraint,
		.summary,
	])
	mut decision_points := reflection_pick_candidate_points(candidates, 2, [.decision])
	if decision_points.len == 0 {
		decision_points = reflection_pick_fallback_summary_points(summary_candidates, 2, .decision)
	}
	mut constraint_points := reflection_pick_candidate_points(candidates, 2, [
		.constraint,
	])
	distillable := title.len > 0 || summary_points.len > 0 || decision_points.len > 0
		|| constraint_points.len > 0
	if summary_points.len == 0 && title.len > 0 {
		summary_points << '- ' + compact_reflection_line(title)
	}
	if summary_points.len == 1 && title.len > 0 {
		title_point := '- ' + compact_reflection_line(title)
		if compact_reflection_comparison_key(summary_points[0]) != compact_reflection_comparison_key(title_point) {
			summary_points << title_point
		}
	}
	if summary_points.len == 0 {
		summary_points = [
			'- 当前主题已从 seed 与近邻证据中完成一次可回放蒸馏。',
		]
	}
	mut insight_points := []string{}
	insight_points << '- 后续查询应优先命中这条主题标题，再回放到原始证据。'
	if job.evidence.len > 1 {
		insight_points << '- 当前主题在最近记忆中至少出现 ${job.evidence.len} 次，可继续向上合并为主题级记忆。'
	} else {
		insight_points << '- 当前主题的语义近邻较少，适合先累计更多同类 entry 再做更强蒸馏。'
	}
	return ReflectionOutline{
		title:             title
		title_basis:       title
		summary_points:    summary_points
		decision_points:   decision_points
		constraint_points: constraint_points
		insight_points:    insight_points
		distillable:       distillable
	}
}

fn reflection_pick_fallback_summary_points(candidates []ReflectionCandidate, limit int, target ReflectionCandidateKind) []string {
	mut points := []string{}
	mut seen := map[string]bool{}
	for candidate in candidates {
		if candidate.kind != .summary {
			continue
		}
		if !reflection_candidate_allowed_for_section(candidate, [target]) {
			continue
		}
		key := compact_reflection_comparison_key(candidate.text)
		if key.len == 0 || key in seen {
			continue
		}
		seen[key] = true
		points << candidate.text
		if points.len >= limit {
			break
		}
	}
	return points
}

fn reflection_outline_persist_input(job ReflectionJob, options ReflectionDistillOptions, outline ReflectionOutline) ReflectionPersistInput {
	topic_key := if options.topic_key.len > 0 {
		options.topic_key
	} else {
		reflection_default_topic_key(job)
	}
	return normalize_reflection_persist_input(job, ReflectionPersistInput{
		title:      if outline.title.len > 0 {
			outline.title
		} else {
			'${job.table_name}.${job.column_name} 记忆复盘'
		}
		topic_key:  topic_key
		summary_md: reflection_summary_markdown(outline.summary_points, outline.decision_points,
			outline.constraint_points)
		insight_md: '## 后续关注\n\n' + outline.insight_points.join('\n') + '\n'
	})
}

enum ReflectionCandidateKind {
	summary
	decision
	constraint
}

struct ReflectionCandidate {
	kind ReflectionCandidateKind
	text string
}

struct RankedReflectionCandidate {
	candidate ReflectionCandidate
	index     int
	priority  int
}

fn reflection_candidates(job ReflectionJob) []ReflectionCandidate {
	mut out := []ReflectionCandidate{}
	mut seen := map[string]bool{}
	for raw in [job.seed_text] {
		for line in raw.split_into_lines() {
			for candidate in reflection_candidates_from_line(line) {
				key := '${candidate.kind}:${compact_reflection_comparison_key(candidate.text)}'
				if key in seen {
					continue
				}
				seen[key] = true
				out << candidate
			}
		}
	}
	for evidence in job.evidence {
		for line in evidence.text.split_into_lines() {
			for candidate in reflection_candidates_from_line(line) {
				key := '${candidate.kind}:${compact_reflection_comparison_key(candidate.text)}'
				if key in seen {
					continue
				}
				seen[key] = true
				out << candidate
			}
		}
	}
	return out
}

fn reflection_candidates_from_line(line string) []ReflectionCandidate {
	cleaned :=
		strip_reflection_title_prefix(line).replace('\t', ' ').replace('  ', ' ').trim_space()
	if cleaned.len == 0 {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_shell_line(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_debug_process(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_test_status_fragment(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_validation_status_fragment(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_one_off_validation_process(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_investigation_process(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_unresolved_question_fragment(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_future_action_process(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_context_dependent_short_note(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_dialogue_control_fragment(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_corrupt_or_truncated_fragment(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_malformed_inline_code(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_isolated_path_fragment(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_ascii_label_fragment(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_isolated_artifact_fragment(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_isolated_token_fragment(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_broken_quote_fragment(cleaned) {
		return []ReflectionCandidate{}
	}
	if reflection_looks_like_broken_code_fragment(cleaned) {
		return []ReflectionCandidate{}
	}
	if cleaned.len < 4 {
		return []ReflectionCandidate{}
	}
	fragments := reflection_candidate_line_fragments(cleaned)
	if fragments.len > 1 {
		mut out := []ReflectionCandidate{}
		mut seen := map[string]bool{}
		for fragment in fragments {
			for candidate in reflection_candidates_from_line(fragment) {
				key := '${candidate.kind}:${compact_reflection_comparison_key(candidate.text)}'
				if key in seen {
					continue
				}
				seen[key] = true
				out << candidate
			}
		}
		return out
	}
	mut candidates := []ReflectionCandidate{}
	decision_candidate := reflection_decision_text(cleaned)
	mut has_stable_decision := false
	if decision := decision_candidate {
		has_stable_decision = !reflection_looks_transient_status(decision)
	}
	if !has_stable_decision {
		for quoted_text in reflection_quoted_candidate_texts(cleaned) {
			candidates << ReflectionCandidate{
				kind: .summary
				text: '- ' + compact_reflection_line(quoted_text)
			}
		}
	}
	if decision_text := decision_candidate {
		candidates << ReflectionCandidate{
			kind: .decision
			text: '- ' + compact_reflection_line(decision_text)
		}
	}
	for constraint_text in reflection_constraint_texts(cleaned) {
		candidates << ReflectionCandidate{
			kind: .constraint
			text: '- ' + compact_reflection_line(constraint_text)
		}
	}
	if candidates.len > 0 {
		return candidates
	}
	return [
		ReflectionCandidate{
			kind: .summary
			text: '- ' + compact_reflection_line(cleaned)
		},
	]
}

fn reflection_candidate_line_fragments(line string) []string {
	mut normalized := line
	for marker in ['。', '！', '？', ';', '；'] {
		normalized = normalized.replace(marker, '\n')
	}
	mut fragments := []string{}
	for fragment in normalized.split_into_lines() {
		cleaned := fragment.trim_space().trim('，,:： ')
		if cleaned.len >= 4 {
			fragments << cleaned
		}
	}
	if fragments.len == 0 {
		return [line]
	}
	return fragments
}

fn reflection_quoted_candidate_texts(line string) []string {
	mut out := []string{}
	for pair in [
		['“', '”'],
		['"', '"'],
		["'", "'"],
		['`', '`'],
	] {
		start := line.index(pair[0]) or { continue }
		end := line.last_index(pair[1]) or { continue }
		if end <= start {
			continue
		}
		content := line[start + pair[0].len..end].trim_space().trim('，。:： ')
		if content.len < 4 {
			continue
		}
		if pair[0] == '`' && content.contains('`') {
			continue
		}
		if reflection_looks_transient_status(content) || reflection_looks_like_shell_line(content) {
			continue
		}
		out << content
	}
	return out
}

fn reflection_decision_text(line string) ?string {
	if !reflection_looks_like_decision(line) {
		return none
	}
	mut out := strip_reflection_sentence_prefix(line)
	if idx := out.index('而不是') {
		if idx > 0 {
			out = out[..idx].trim_space()
		}
	}
	out = out.trim('，。:： ')
	return if out.len > 0 { out } else { none }
}

fn strip_reflection_sentence_prefix(line string) string {
	mut out := strip_reflection_title_prefix(line).trim_space()
	for prefix in ['然后把', '然后将', '然后', '接着把', '接着将', '接着',
		'同时把', '同时将', '同时', '并且把', '并且将', '并且'] {
		if out.starts_with(prefix) {
			if prefix.ends_with('把') || prefix.ends_with('将') {
				out = prefix[prefix.len - 3..] + out[prefix.len..]
			} else {
				out = out[prefix.len..].trim_space()
			}
			break
		}
	}
	return out.trim_space()
}

fn reflection_rewrite_change_statement(line string) string {
	mut out := strip_reflection_sentence_prefix(line)
	if !out.starts_with('把') && !out.starts_with('将') {
		return out
	}
	for marker in ['改成了', '改成', '改为了', '改为', '配置为了', '配置为',
		'切换到了', '切换到'] {
		idx := out.index(marker) or { continue }
		left := out[..idx].trim_space().trim('，。:： ')
		right := out[idx + marker.len..].trim_space().trim('，。:： ')
		if left.len == 0 || right.len == 0 {
			continue
		}
		subject := reflection_strip_change_subject_prefix(left)
		value := reflection_unquote(right)
		if subject.len > 0 && value.len > 0 {
			return '${subject}：${value}'
		}
	}
	return out
}

fn reflection_rewrite_first_person_decision(line string) string {
	mut out := line.trim_space()
	for marker in ['我改用', '我改成', '我采用', '我选择'] {
		idx := out.index(marker) or { continue }
		before := out[..idx].trim_space().trim('，。:： ')
		after := out[idx + marker.len..].trim_space().trim('，。:： ')
		if after.len == 0 {
			continue
		}
		verb := marker['我'.len..]
		if before.len == 0 {
			return '${verb}${after}'
		}
		return '${before}，${verb}${after}'
	}
	return out
}

fn reflection_strip_change_subject_prefix(text string) string {
	mut out := text.trim_space()
	for prefix in ['把', '将'] {
		if out.starts_with(prefix) {
			out = out[prefix.len..].trim_space()
		}
	}
	return out.trim('，。:： ')
}

fn reflection_unquote(text string) string {
	mut out := text.trim_space()
	for pair in [
		['“', '”'],
		['"', '"'],
		["'", "'"],
		['`', '`'],
	] {
		if out.starts_with(pair[0]) && out.ends_with(pair[1]) && out.len > pair[0].len + pair[1].len {
			out = out[pair[0].len..out.len - pair[1].len].trim_space()
			break
		}
	}
	return out.trim('，。:： ')
}

fn reflection_constraint_texts(line string) []string {
	mut constraints := []string{}
	mut has_specific := false
	if quoted := reflection_negative_phrase(line) {
		constraints << quoted
		has_specific = true
	}
	if idx := line.index('而不是') {
		if idx > 0 {
			rhs := line[idx + '而不是'.len..].trim_space().trim('，。:： ')
			if rhs.starts_with('把') {
				constraints << '不要' + rhs
			} else if rhs.starts_with('将') {
				constraints << '不要' + rhs
			} else if rhs.len > 0 {
				constraints << rhs
			}
			has_specific = true
		}
	}
	if reflection_looks_like_constraint(line) && !has_specific {
		constraints << line
	}
	mut deduped := []string{}
	mut seen := map[string]bool{}
	for item in constraints {
		key := compact_reflection_comparison_key(item)
		if key.len == 0 || key in seen {
			continue
		}
		seen[key] = true
		deduped << item
	}
	return deduped
}

fn reflection_negative_phrase(line string) ?string {
	for pair in [
		['“', '”'],
		['"', '"'],
		["'", "'"],
	] {
		start := line.index(pair[0]) or { continue }
		end := line.last_index(pair[1]) or { continue }
		if end <= start {
			continue
		}
		content := line[start + pair[0].len..end].trim_space()
		if reflection_looks_like_constraint(content) {
			return content
		}
	}
	for marker in ['不把', '不要', '不能', '不得', '不需要'] {
		idx := line.index(marker) or { continue }
		mut out := line[idx..].trim_space().trim('，。:： ')
		prefix := line[..idx].trim_space().trim('，。:： ')
		if prefix.len > 0 && prefix.len <= 80 && reflection_contains_durable_artifact(prefix) {
			out = '${prefix} ${out}'
		}
		if out.len > 0 {
			return out
		}
	}
	return none
}

fn reflection_pick_candidate_points(candidates []ReflectionCandidate, limit int, kinds []ReflectionCandidateKind) []string {
	mut ranked := []RankedReflectionCandidate{}
	for idx, candidate in candidates {
		if candidate.kind !in kinds {
			continue
		}
		ranked << RankedReflectionCandidate{
			candidate: candidate
			index:     idx
			priority:  reflection_candidate_priority(candidate)
		}
	}
	prefer_stable := ranked.any(!reflection_candidate_is_transient(it.candidate))
	ranked.sort_with_compare(fn (a &RankedReflectionCandidate, b &RankedReflectionCandidate) int {
		if a.priority > b.priority {
			return -1
		}
		if a.priority < b.priority {
			return 1
		}
		if a.index < b.index {
			return -1
		}
		if a.index > b.index {
			return 1
		}
		return 0
	})
	mut points := []string{}
	mut seen := map[string]bool{}
	for item in ranked {
		candidate := item.candidate
		if prefer_stable && reflection_candidate_is_transient(candidate) {
			continue
		}
		if !reflection_candidate_allowed_for_section(candidate, kinds) {
			continue
		}
		key := compact_reflection_comparison_key(candidate.text)
		if key.len == 0 || key in seen {
			continue
		}
		seen[key] = true
		points << candidate.text
		if points.len >= limit {
			break
		}
	}
	return points
}

fn reflection_candidate_allowed_for_section(candidate ReflectionCandidate, kinds []ReflectionCandidateKind) bool {
	text := strip_reflection_title_prefix(candidate.text.trim_space())
	if reflection_looks_like_shell_line(text) {
		return false
	}
	if reflection_looks_like_debug_process(text) {
		return false
	}
	if reflection_looks_like_test_status_fragment(text) {
		return false
	}
	if reflection_looks_like_validation_status_fragment(text) {
		return false
	}
	if reflection_looks_like_one_off_validation_process(text) {
		return false
	}
	if reflection_looks_like_investigation_process(text) {
		return false
	}
	if reflection_looks_like_malformed_inline_code(text) {
		return false
	}
	if reflection_looks_like_raw_schema_fragment(text) {
		return false
	}
	if reflection_looks_like_isolated_path_fragment(text) {
		return false
	}
	if reflection_looks_like_ascii_label_fragment(text) {
		return false
	}
	if reflection_looks_like_isolated_artifact_fragment(text) {
		return false
	}
	if reflection_looks_like_isolated_token_fragment(text) {
		return false
	}
	if reflection_looks_like_broken_quote_fragment(text) {
		return false
	}
	if reflection_looks_like_broken_code_fragment(text) {
		return false
	}
	if reflection_looks_like_choice_fragment(text) {
		return false
	}
	want_summary := ReflectionCandidateKind.summary in kinds
	if want_summary {
		return !reflection_looks_like_runtime_error(text)
			&& !reflection_looks_transient_status(text)
			&& !reflection_looks_like_context_dependent_short_note(text)
	}
	want_constraints := ReflectionCandidateKind.constraint in kinds
	want_decisions := ReflectionCandidateKind.decision in kinds && !want_constraints
	if want_constraints {
		if reflection_looks_transient_status(text) || reflection_looks_like_runtime_error(text) {
			return false
		}
		return reflection_looks_like_constraint(text)
	}
	if want_decisions {
		if reflection_looks_transient_status(text) {
			return false
		}
		if reflection_looks_like_runtime_error(text) {
			return false
		}
		if reflection_looks_like_root_cause(text) && !reflection_looks_like_decision(text) {
			return false
		}
		return reflection_looks_like_decision(text) || reflection_contains_durable_artifact(text)
	}
	return true
}

fn reflection_candidate_is_transient(candidate ReflectionCandidate) bool {
	return reflection_looks_transient_status(strip_reflection_title_prefix(candidate.text))
}

fn reflection_candidate_priority(candidate ReflectionCandidate) int {
	text := strip_reflection_title_prefix(candidate.text.trim_space())
	mut score := match candidate.kind {
		.summary { 2 }
		.decision { 4 }
		.constraint { 5 }
	}

	if reflection_looks_like_root_cause(text) {
		score += 5
	}
	if reflection_looks_like_constraint(text) {
		score += 4
	}
	if reflection_looks_like_decision(text) {
		score += 3
	}
	if reflection_contains_durable_artifact(text) {
		score += 2
	}
	if reflection_looks_transient_status(text) {
		score -= 6
	}
	return score
}

fn reflection_title_from_candidates(candidates []ReflectionCandidate) string {
	mut ranked := []RankedReflectionCandidate{}
	for idx, candidate in candidates {
		ranked << RankedReflectionCandidate{
			candidate: candidate
			index:     idx
			priority:  reflection_candidate_priority(candidate)
		}
	}
	ranked.sort_with_compare(fn (a &RankedReflectionCandidate, b &RankedReflectionCandidate) int {
		if a.priority > b.priority {
			return -1
		}
		if a.priority < b.priority {
			return 1
		}
		if a.index < b.index {
			return -1
		}
		if a.index > b.index {
			return 1
		}
		return 0
	})
	for item in ranked {
		candidate := item.candidate
		title := reflection_title_from_text(candidate.text)
		if title.len > 0 && reflection_title_is_useful(title) {
			return title
		}
	}
	return ''
}

fn reflection_title_from_text(text string) string {
	mut out := reflection_strip_bullet_prefix(strip_reflection_title_prefix(text))
	out = reflection_rewrite_first_person_decision(out)
	out = reflection_strip_vague_leading_clause(out)
	out = reflection_stabilize_diagnostic_claim(out)
	for marker in ['。', '：', ':'] {
		if idx := out.index(marker) {
			if idx > 0 {
				out = out[..idx].trim_space()
				break
			}
		}
	}
	return out
}

fn reflection_stabilize_diagnostic_claim(text string) string {
	mut out := text.trim_space()
	for marker in ['不是别的，是', '不是别的是'] {
		idx := out.index(marker) or { continue }
		rest := out[idx + marker.len..].trim_space().trim('，。:： ')
		if rest.len >= 6 {
			out = rest
			break
		}
	}
	for marker in ['因为', '原因是'] {
		idx := out.index(marker) or { continue }
		if idx <= 0 {
			continue
		}
		prefix := out[..idx]
		if !(prefix.contains('可疑') || prefix.contains('看起来')) {
			continue
		}
		rest := out[idx + marker.len..].trim_space().trim('，。:： ')
		if rest.len >= 6 {
			out = rest
			break
		}
	}
	for suffix in ['，所以更可疑', '，所以看起来更可疑', '，看起来更可疑',
		'，这条线更可疑', '，更可疑'] {
		if out.ends_with(suffix) {
			out = out[..out.len - suffix.len].trim_space()
			break
		}
	}
	return out.trim('，。:： ')
}

fn reflection_strip_vague_leading_clause(text string) string {
	cleaned := text.trim_space()
	for marker in ['：', ':'] {
		idx := cleaned.index(marker) or { continue }
		prefix := cleaned[..idx].trim_space()
		rest := cleaned[idx + marker.len..].trim_space()
		if rest.len >= 6 && reflection_looks_like_vague_resolution_title(prefix) {
			return rest
		}
	}
	return cleaned
}

fn reflection_title_is_useful(title string) bool {
	cleaned := strip_reflection_title_prefix(title).trim_space()
	if cleaned.len < 6 {
		return false
	}
	lower := cleaned.to_lower()
	if reflection_looks_like_choice_fragment(cleaned) || lower.starts_with('直接往') {
		return false
	}
	if reflection_looks_like_debug_process(cleaned) {
		return false
	}
	if reflection_looks_like_test_status_fragment(cleaned) {
		return false
	}
	if reflection_looks_like_validation_status_fragment(cleaned) {
		return false
	}
	if reflection_looks_like_one_off_validation_process(cleaned) {
		return false
	}
	if reflection_looks_like_investigation_process(cleaned) {
		return false
	}
	if reflection_looks_like_vague_resolution_title(cleaned) {
		return false
	}
	if reflection_looks_like_unresolved_question_fragment(cleaned) {
		return false
	}
	if reflection_looks_like_future_action_process(cleaned) {
		return false
	}
	if reflection_looks_like_context_dependent_short_note(cleaned) {
		return false
	}
	if reflection_looks_like_dialogue_control_fragment(cleaned) {
		return false
	}
	if reflection_looks_like_corrupt_or_truncated_fragment(cleaned) {
		return false
	}
	if reflection_looks_like_malformed_inline_code(cleaned) {
		return false
	}
	if reflection_looks_like_raw_schema_fragment(cleaned) {
		return false
	}
	if reflection_looks_like_isolated_path_fragment(cleaned) {
		return false
	}
	if reflection_looks_like_isolated_token_fragment(cleaned) {
		return false
	}
	if reflection_looks_like_broken_quote_fragment(cleaned) {
		return false
	}
	if reflection_looks_like_broken_code_fragment(cleaned) {
		return false
	}
	for marker in ['这台机器', '当前机器', '本机', '刚好有', '刚好被', '当前环境'] {
		if lower.contains(marker) {
			return false
		}
	}
	for marker in ['我建议分开看', '先分开看', '我先看一下', '我去看一下',
		'我准备', '我要开始', '我要动', '我会先', '我先把', '接下来我会'] {
		if lower.contains(marker) {
			return false
		}
	}
	if reflection_looks_transient_status(cleaned) {
		return false
	}
	return true
}

fn reflection_looks_like_choice_fragment(line string) bool {
	lower := line.to_lower()
	return lower.contains('还是') || lower.contains('裸指针')
}

fn reflection_looks_like_debug_process(line string) bool {
	lower := line.to_lower()
	for marker in ['lldb', 'thread backtrace', 'bt ', '回溯', '我换成更直接',
		'目标就是抓', '再往上是', '往上是', '调用栈', '栈上'] {
		if lower.contains(marker) {
			return true
		}
	}
	return false
}

fn reflection_looks_like_test_status_fragment(line string) bool {
	lower := line.to_lower()
	if line.contains('FINAL|') {
		return true
	}
	if lower.contains(' -> ') && (lower.contains('final|') || lower.contains('status')
		|| lower.contains('200|') || lower.contains('检查通过')
		|| lower.contains('测试状态')) {
		return true
	}
	return false
}

fn reflection_looks_like_validation_status_fragment(line string) bool {
	lower := line.to_lower()
	if lower.contains('smoke') && (lower.contains('全绿') || lower.contains('通过')
		|| lower.contains('主链') || lower.contains('green')) {
		return true
	}
	if lower.contains('/tmp/') && (lower.contains('_probe.') || lower.contains('probe.php')
		|| lower.contains('smoke')) {
		return true
	}
	return false
}

fn reflection_looks_like_one_off_validation_process(line string) bool {
	lower := line.to_lower()
	if lower.contains('刚才那个') && (lower.contains('大概率') || lower.contains('中间态')
		|| lower.contains('再把') || lower.contains('再跑')
		|| lower.contains('确认这轮')) {
		return true
	}
	if lower.contains('我再') && (lower.contains('跑一遍') || lower.contains('各跑一遍')
		|| lower.contains('确认这轮') || lower.contains('看一下这轮')) {
		return true
	}
	if lower.contains('我再看一下') || lower.contains('我顺手') {
		return true
	}
	if lower.contains('对照') && (lower.contains('我再做') || lower.contains('做一组')
		|| lower.contains('做一轮') || lower.contains('做个')) {
		return true
	}
	if lower.contains('非敏感字段') || lower.contains('连通性探测') {
		return true
	}
	if lower.starts_with('我这轮') || lower.starts_with('这轮主要')
		|| lower.starts_with('本轮主要') {
		return true
	}
	if (lower.contains('现在我把') || lower.contains('我把'))
		&& (lower.contains('跑一遍') || lower.contains('再跑')
		|| lower.contains('确认')) {
		return true
	}
	if (lower.contains('确认') || lower.contains('验证'))
		&& (lower.contains('闭环') || lower.contains('真正通')
		|| lower.contains('整个链路') || lower.contains('没有漏掉')) {
		return true
	}
	return false
}

fn reflection_looks_like_investigation_process(line string) bool {
	lower := line.to_lower()
	if lower.contains('到底是怎么') || lower.contains('确认是不是')
		|| lower.contains('看一下是不是') || lower.contains('我再确认一次') {
		return true
	}
	if lower.contains('对照实验') || lower.contains('做一个实验')
		|| lower.contains('做个实验') {
		return true
	}
	if lower.contains('确认这个') || lower.contains('确认回归')
		|| lower.contains('正式跑法') {
		return true
	}
	if lower.contains('不是最终') || lower.contains('不一定是最终')
		|| lower.contains('如果它能') || lower.contains('如果能立刻')
		|| lower.contains('说明崩点') || lower.contains('碰到正确层')
		|| lower.contains('刚才那条改动') || lower.contains('如果成立')
		|| lower.contains('如果真是') || lower.contains('不是我们要的')
		|| lower.contains('还不是我们要的') || lower.contains('有信息量') {
		return true
	}
	if lower.contains('先确认') && (lower.contains('是不是') || lower.contains('怎么')) {
		return true
	}
	if lower.contains('不想继续空猜') || lower.contains('继续空猜') {
		return true
	}
	if lower.contains('看起来是做了的') || lower.contains('看起来像是做了的') {
		return true
	}
	return false
}

fn reflection_looks_like_vague_resolution_title(line string) bool {
	lower := line.to_lower().trim_space().trim('，。:： ')
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

fn reflection_looks_like_future_action_process(line string) bool {
	lower := line.to_lower()
	if lower.contains('接下来就把') || lower.contains('接下来我会')
		|| lower.contains('接下来再') || lower.contains('然后再')
		|| lower.contains('下一步我要') || lower.contains('下一步我会')
		|| lower.contains('这轮要等') || lower.contains('如果是，我会')
		|| lower.contains('如果是我会') || lower.contains('我直接改掉')
		|| lower.contains('直接改掉') || lower.contains('这处很小')
		|| lower.contains('跑一个相关测试') {
		return true
	}
	if lower.starts_with('我去把') || lower.starts_with('我会把')
		|| lower.starts_with('我要去') || lower.starts_with('我要先')
		|| lower.starts_with('我要重新') || lower.starts_with('我就直接')
		|| lower.starts_with('我准备把') || lower.starts_with('我准备直接') {
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

fn reflection_looks_like_dialogue_control_fragment(line string) bool {
	cleaned := strip_reflection_title_prefix(line).trim_space().trim('- *，。:： ')
	lower := cleaned.to_lower()
	if lower.len == 0 {
		return true
	}
	for prefix in ['同意', '好的', '好啊', '好，', '继续', '开始吧'] {
		if lower.starts_with(prefix) {
			return true
		}
	}
	return lower.contains('你继续') || lower.contains('开始验证吧')
		|| lower.contains('你现在可以直接改') || lower.contains('你可以直接改')
		|| lower.contains('现在可以直接改')
}

fn reflection_looks_like_unresolved_question_fragment(line string) bool {
	cleaned := strip_reflection_title_prefix(line).trim_space().trim('- *，。:： ')
	lower := cleaned.to_lower()
	for prefix in ['是不是', '是否', '为什么', '怎么', '哪里', '哪一层'] {
		if lower.starts_with(prefix) {
			return true
		}
	}
	return cleaned.ends_with('?') || cleaned.ends_with('？')
}

fn reflection_looks_like_corrupt_or_truncated_fragment(line string) bool {
	cleaned := line.trim_space()
	if cleaned.contains('�') {
		return true
	}
	if cleaned.contains('](') && !cleaned.contains(')') {
		return true
	}
	if reflection_has_unbalanced_cjk_quotes(cleaned) {
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

fn reflection_has_unbalanced_cjk_quotes(text string) bool {
	if text.count('“') != text.count('”') {
		return true
	}
	close_idx := text.index('”') or { return false }
	open_idx := text.index('“') or { return false }
	return close_idx < open_idx
}

fn reflection_looks_like_raw_schema_fragment(line string) bool {
	lower := strip_reflection_title_prefix(line).trim_space().trim('- *`，。:： ').to_lower()
	for prefix in ['add column ', 'alter table ', 'create table ', 'drop table ', 'create index ',
		'drop index '] {
		if lower.starts_with(prefix) {
			return true
		}
	}
	return false
}

fn reflection_looks_like_malformed_inline_code(line string) bool {
	cleaned := strip_reflection_title_prefix(line).trim_space()
	first_tick := cleaned.index('`') or { return false }
	if first_tick == 0 {
		return false
	}
	before := cleaned[..first_tick].trim_space()
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

fn reflection_looks_like_isolated_path_fragment(line string) bool {
	cleaned := strip_reflection_title_prefix(line).trim_space().trim('- *`，。:： ')
	if cleaned.runes().len > 32 {
		return false
	}
	if !cleaned.contains('/') {
		return false
	}
	if reflection_looks_like_decision(cleaned) || reflection_looks_like_root_cause(cleaned)
		|| reflection_looks_like_constraint(cleaned) {
		return false
	}
	return true
}

fn reflection_looks_like_isolated_token_fragment(line string) bool {
	cleaned := strip_reflection_title_prefix(line).trim_space().trim('- *`，。:： ')
	if cleaned.len == 0 || cleaned.runes().len > 80 {
		return false
	}
	if cleaned.contains(' ') || cleaned.contains('/') || cleaned.contains('.')
		|| cleaned.contains('`') {
		return false
	}
	if reflection_looks_like_decision(cleaned) || reflection_looks_like_root_cause(cleaned)
		|| reflection_looks_like_constraint(cleaned) {
		return false
	}
	mut has_symbol_separator := false
	for ch in cleaned.bytes() {
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| (ch >= `0` && ch <= `9`) || ch == `_` || ch == `-`) {
			return false
		}
		if ch == `_` || ch == `-` {
			has_symbol_separator = true
		}
	}
	return has_symbol_separator || cleaned.runes().len <= 24
}

fn reflection_looks_like_ascii_label_fragment(line string) bool {
	cleaned := strip_reflection_title_prefix(line).trim_space().trim('- *`，。:： ')
	if cleaned.len == 0 || cleaned.runes().len > 40 {
		return false
	}
	if reflection_looks_like_decision(cleaned) || reflection_looks_like_root_cause(cleaned)
		|| reflection_looks_like_constraint(cleaned) {
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

fn reflection_looks_like_isolated_artifact_fragment(line string) bool {
	cleaned := strip_reflection_title_prefix(line).trim_space().trim('- *`，。:： ')
	if cleaned.len == 0 || cleaned.runes().len > 64 {
		return false
	}
	if cleaned.contains(' ') || cleaned.contains('/') || cleaned.contains('：')
		|| cleaned.contains(':') {
		return false
	}
	if reflection_looks_like_decision(cleaned) || reflection_looks_like_root_cause(cleaned)
		|| reflection_looks_like_constraint(cleaned) {
		return false
	}
	mut has_artifact_separator := false
	for ch in cleaned.bytes() {
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| (ch >= `0` && ch <= `9`) || ch == `_` || ch == `-` || ch == `.`
			|| ch == `+`) {
			return false
		}
		if ch == `.` || ch == `_` || ch == `-` || ch == `+` {
			has_artifact_separator = true
		}
	}
	return has_artifact_separator
}

fn reflection_looks_like_low_information_point(point string) bool {
	cleaned := strip_reflection_title_prefix(point).trim_space().trim('- *，。:： ')
	return reflection_looks_like_isolated_path_fragment(cleaned)
		|| reflection_looks_like_isolated_artifact_fragment(cleaned)
		|| reflection_looks_like_isolated_token_fragment(cleaned)
}

fn reflection_looks_like_broken_quote_fragment(line string) bool {
	cleaned := strip_reflection_title_prefix(line).trim_space().trim('- *，。:： ')
	if cleaned.len == 0 {
		return false
	}
	if cleaned.contains('”') && !cleaned.contains('“') {
		return true
	}
	if cleaned.contains('"') && cleaned.count('"') == 1 {
		return true
	}
	if cleaned.contains('`') && cleaned.count('`') % 2 == 1 {
		return true
	}
	return false
}

fn reflection_looks_like_broken_code_fragment(line string) bool {
	cleaned := strip_reflection_title_prefix(line).trim_space().trim('- *，。:： ')
	if cleaned.len == 0 {
		return false
	}
	if reflection_looks_like_decision(cleaned) || reflection_looks_like_root_cause(cleaned)
		|| reflection_looks_like_constraint(cleaned) {
		return false
	}
	return cleaned.starts_with('&') || cleaned.starts_with('*_') || cleaned.starts_with('_')
}

fn reflection_looks_like_decision(line string) bool {
	lower := line.to_lower()
	return lower.contains('改成') || lower.contains('改为') || lower.contains('使用')
		|| lower.contains('采用') || lower.contains('改用') || lower.contains('通过')
		|| lower.contains('切换到') || lower.contains('同步到') || lower.contains('新增')
		|| lower.contains('更新') || lower.contains('启用') || lower.contains('配置为')
		|| lower.contains('迁移到') || lower.contains('接入') || lower.contains('确认下来')
		|| lower.contains('确认下来了') || lower.contains('范围确认')
		|| lower.contains('完整的') || lower.contains('能力补充')
		|| lower.contains('功能补充') || lower.contains('能力边界')
		|| lower.contains('功能组')
}

fn reflection_looks_like_root_cause(line string) bool {
	lower := line.to_lower()
	return lower.contains('原因') || lower.contains('触发点')
		|| lower.contains('解释为什么') || lower.contains('说明')
		|| lower.contains('定位到') || lower.contains('根因')
}

fn reflection_looks_like_constraint(line string) bool {
	lower := line.to_lower()
	return lower.contains('不把') || lower.contains('不要') || lower.contains('不能')
		|| lower.contains('不得') || lower.contains('必须') || lower.contains('需要')
		|| lower.contains('避免') || lower.contains('只适合') || lower.contains('仅适合')
		|| lower.contains('只做') || lower.contains('只服务于') || lower.contains('只用于')
		|| lower.contains('仅用于') || lower.contains('不复用')
		|| lower.contains('没有别的') || lower.contains('限制') || lower.contains('约束')
		|| lower.contains('前提') || lower.contains('要求')
}

fn reflection_contains_durable_artifact(line string) bool {
	return line.contains('`') || line.contains('/') || line.contains('.v') || line.contains('.js')
		|| line.contains('.ts') || line.contains('.json') || line.contains('.md')
		|| line.contains('_ROOT') || line.contains('_PATH') || line.contains('@')
}

fn reflection_looks_transient_status(line string) bool {
	lower := line.to_lower()
	return lower.contains('验证通过') || lower.contains('测试已经启动')
		|| lower.contains('当前在') || lower.contains('尚未推送')
		|| lower.contains('推到远端') || lower.contains('提交')
		|| lower.contains('申请权限') || lower.contains('提权')
		|| lower.contains('受限沙箱') || lower.contains('我先') || lower.contains('我会先')
		|| lower.contains('随后会') || lower.contains('现在把') || lower.contains('我在等')
		|| lower.contains('我要动') || lower.contains('我要开始')
		|| lower.contains('我准备') || lower.contains('准备直接')
		|| lower.contains('我去看') || lower.contains('先确认') || lower.contains('先把')
		|| lower.contains('我要把') || lower.contains('我把测试改成')
		|| lower.contains('我会直接') || lower.contains('会直接指出')
		|| lower.contains('找到具体')
}

fn reflection_looks_like_shell_line(line string) bool {
	lower := line.to_lower()
	if lower.starts_with('sudo ') || lower.starts_with('cd ') || lower.starts_with('$ ')
		|| lower.starts_with('./') || lower.starts_with('../') || lower.starts_with('php ')
		|| lower.starts_with('make ') || lower.starts_with('npm ') || lower.starts_with('cargo ')
		|| lower.starts_with('v test ') || lower.starts_with('v run ') {
		return true
	}
	if line.contains('# ') && line.contains('@') && line.contains(':') {
		return true
	}
	return false
}

fn reflection_looks_like_runtime_error(line string) bool {
	lower := line.to_lower()
	return lower.contains('panic:') || lower.contains('exception:') || lower.contains('traceback')
		|| lower.contains('file not found') || lower.contains('segmentation fault')
		|| lower.contains('command failed') || lower.contains('exit code')
}

fn reflection_looks_like_context_dependent_short_note(line string) bool {
	cleaned := strip_reflection_title_prefix(line).trim_space().trim('- *，。:： ')
	if cleaned.len > 36 {
		return false
	}
	if reflection_contains_durable_artifact(cleaned) || reflection_looks_like_root_cause(cleaned)
		|| reflection_looks_like_constraint(cleaned) {
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

fn strip_reflection_title_prefix(text string) string {
	mut out := text.replace('\r', ' ').replace('\n', ' ').trim_space()
	for prefix in ['你说得对，所以我已经', '你说得对，所以', '你说得对，',
		'你这个反馈很对。', '你这个反馈很对，', '好的，', '好的。', '是的，',
		'对，', '现在我来', '现在已经', '我确认了：', '我确认了:',
		'我确认了，', '我确认了。', '我确认了', '我已经', '所以我已经'] {
		if out.starts_with(prefix) {
			out = out[prefix.len..].trim_space()
		}
	}
	for prefix in ['我找到更稳的做法了：', '我找到更稳的做法了:',
		'我找到更稳的做法了，', '这条我刚看到一个很像根因的地方了：',
		'这条我刚看到一个很像根因的地方了:',
		'这条我刚看到一个很像根因的地方了，'] {
		if out.starts_with(prefix) {
			out = out[prefix.len..].trim_space()
		}
	}
	return out.trim('，。:： ')
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
			metadata_json:          encode_memory_link_metadata(ref, job.seed_scope,
				job.seed_anchor, job.seed_text, job.reflection_kind)
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
			metadata_json:          encode_memory_link_metadata(ref, job.seed_scope,
				job.seed_anchor, job.seed_text, job.reflection_kind)
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
