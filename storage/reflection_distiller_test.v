module storage

struct MockReflectionGenerator {
	output string
mut:
	last_prompt string
}

fn (mut generator MockReflectionGenerator) generate(prompt string) !string {
	generator.last_prompt = prompt
	return generator.output
}

fn test_parse_reflection_generation_with_markers() {
	input := parse_reflection_generation('noise
BEGIN_REFLECTION
TITLE: 数据库优化讨论
TOPIC: db-optimization
SUMMARY_MD:
# Summary

- 讨论了 PollyDB 和 FTS 的边界。

INSIGHT_MD:
## Insight

- SQLite 只做 FTS。
END_REFLECTION
more noise') or {
		panic(err)
	}
	assert input.title == '数据库优化讨论'
	assert input.topic_key == 'db-optimization'
	assert input.summary_md.contains('PollyDB')
	assert input.insight_md.contains('SQLite')
}

fn test_parse_reflection_generation_accepts_markdown_insight_heading() {
	input := parse_reflection_generation('BEGIN_REFLECTION
TITLE: 本地记忆边界
TOPIC: local-memory
SUMMARY_MD:
# Summary

- PollyDB 持有真相。

## Insight

- SQLite 只做 FTS。
END_REFLECTION') or {
		panic(err)
	}
	assert input.summary_md.contains('PollyDB')
	assert !input.summary_md.contains('SQLite 只做 FTS')
	assert input.insight_md.contains('SQLite 只做 FTS')
}

fn test_generate_reflection_persist_input_uses_job_context() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'docs'
		primary_key:     'doc-1'.bytes()
		column_name:     'body'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/h1:memory'
		seed_text:       'PollyDB 持有真相，SQLite 只做 FTS。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'docs'
				primary_key: 'doc-2'.bytes()
				column_name: 'body'
				target_id:   'target-2'
				score:       0.98
				scope:       .path
				kind:        'heading_path'
				anchor:      '/h1:index'
				path_hint:   'blocks[0]'
				text:        'USearch 是可重建 ANN 视图。'
			},
		]
	}
	mut generator := MockReflectionGenerator{
		output: 'BEGIN_REFLECTION
TITLE: 本地记忆索引边界
TOPIC:
SUMMARY_MD:
# Summary

- PollyDB 是真相层。

INSIGHT_MD:
## Insight

- SQLite 和 USearch 都是派生视图。
END_REFLECTION'
	}
	input := generate_reflection_persist_input(job, mut generator, ReflectionDistillOptions{
		topic_key: 'local-memory'
	}) or { panic(err) }
	assert generator.last_prompt.contains('PollyDB 持有真相')
	assert generator.last_prompt.contains('USearch 是可重建 ANN 视图')
	assert input.title == '本地记忆索引边界'
	assert input.topic_key == 'local-memory'
	assert input.summary_md.contains('PollyDB')
	assert input.insight_md.contains('USearch')
}

fn test_generate_reflection_persist_input_compacts_runaway_output() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'docs'
		primary_key:     'doc-1'.bytes()
		column_name:     'body'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/h1:memory'
		seed_text:       'PollyDB 持有真相，SQLite 只做 FTS，USearch 只做 ANN。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'docs'
				primary_key: 'doc-2'.bytes()
				column_name: 'body'
				target_id:   'target-2'
				score:       0.98
				scope:       .path
				kind:        'heading_path'
				anchor:      '/h1:index'
				path_hint:   'blocks[0]'
				text:        'Reflector 写回 summary 与 semantic links。'
			},
		]
	}
	mut generator := MockReflectionGenerator{
		output: 'BEGIN_REFLECTION
TITLE: 本地记忆边界
TOPIC: local-memory
SUMMARY_MD:
# Summary

- PollyDB 保存记忆真相。
- SQLite FTS 和 USearch 是派生索引。
- 这一条不应该进入最终摘要。
- 这一条也不应该进入最终摘要。
END_REFLECTION'
	}
	input := generate_reflection_persist_input(job, mut generator, ReflectionDistillOptions{}) or {
		panic(err)
	}
	assert input.summary_md.contains('PollyDB 保存记忆真相')
	assert input.summary_md.contains('SQLite FTS')
	assert !input.summary_md.contains('不应该进入')
	assert input.insight_md.contains('PollyDB 继续持有真相')
	assert input.insight_md.contains('USearch')
}
