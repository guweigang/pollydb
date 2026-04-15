module storage

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
