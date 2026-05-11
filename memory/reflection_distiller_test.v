module memory

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
# 摘要

- PollyDB 是真相层。

## 关键决策

- SQLite 只做 FTS。

## 重要约束

- USearch 只做 ANN。

INSIGHT_MD:
## 后续关注

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
	assert input.summary_md.contains('## 重要约束')
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
# 摘要

- PollyDB 保存记忆真相。
- SQLite FTS 和 USearch 是派生索引。

## 关键决策

- SQLite 只做 FTS。
- USearch 只做 ANN。
- 这一条不应该进入最终决策。

## 重要约束

- 不要把派生索引当成真相层。
- 必须保留 source_refs。
- 这一条不应该进入最终约束。
END_REFLECTION'
	}
	input := generate_reflection_persist_input(job, mut generator, ReflectionDistillOptions{}) or {
		panic(err)
	}
	assert input.summary_md.contains('PollyDB')
	assert input.summary_md.contains('SQLite')
	assert input.summary_md.contains('## 重要约束')
	assert !input.summary_md.contains('不应该进入最终决策')
	assert !input.summary_md.contains('不应该进入最终约束')
	assert input.insight_md.contains('后续关注')
}

fn test_generate_reflection_persist_input_falls_back_when_sections_repeat_same_claim() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '你说得对，所以我已经把模板改成不把配置路径写死的方式了。\n现在 Linux 这边改成了 systemd 实例模板。'
	}
	mut generator := MockReflectionGenerator{
		output: 'BEGIN_REFLECTION
TITLE: 把模板改成不把配置路径写死
TOPIC:
SUMMARY_MD:
# 摘要

- 配置路径写死会导致配置文件被修改，影响系统稳定性。

## 关键决策

- 配置路径写死会导致配置文件被修改，影响系统稳定性。

## 重要约束

- 配置路径写死会导致配置文件被修改，影响系统稳定性。

INSIGHT_MD:
## 后续关注

- 配置路径写死会导致配置文件被修改，影响系统稳定性。
END_REFLECTION'
	}
	input := generate_reflection_persist_input(job, mut generator, ReflectionDistillOptions{}) or {
		panic(err)
	}
	assert input.title.starts_with('把模板改成不把配置路径写死')
	assert input.summary_md.contains('现在 Linux 这边改成了 systemd 实例模板')
	assert input.summary_md.contains('## 关键决策')
	assert input.summary_md.contains('## 重要约束')
	assert !input.summary_md.contains('影响系统稳定性')
}

fn test_heuristic_reflection_avoids_choice_fragment_title_and_double_bullets() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .block
		seed_anchor:     'entry:1'
		seed_text:       '返回裸指针”还是“直接往 `ctx.ret` 写 zval'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				score:       0.97
				scope:       .block
				kind:        'message'
				anchor:      'entry:2'
				text:        '把 PHP 暴露的 `dispatch_request/dispatch_body/dispatch_envelope/dispatch` 改成返回 `RequestOwnedZBox`。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				score:       0.95
				scope:       .block
				kind:        'message'
				anchor:      'entry:3'
				text:        '这说明锅已经不在 sample 了，是真正的 bridge/runtime 返回值丢失。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.title.contains('还是')
	assert input.title.contains('RequestOwnedZBox') || input.title.contains('bridge/runtime')
	assert !input.summary_md.contains('- - ')
	assert input.summary_md.contains('## 关键决策')
}

fn test_heuristic_reflection_filters_broken_quote_fragments_from_summary() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .block
		seed_anchor:     'entry:1'
		seed_text:       '把 PHP 暴露的 `dispatch_request/dispatch_body/dispatch_envelope/dispatch` 改成返回 `RequestOwnedZBox`。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				score:       0.97
				scope:       .block
				kind:        'message'
				anchor:      'entry:2'
				text:        '这说明锅已经不在 sample 了，是真正的 bridge/runtime 返回值丢失。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				score:       0.95
				scope:       .block
				kind:        'message'
				anchor:      'entry:3'
				text:        'ctx.ret` 写 zval”的，是**方法的真实 V 返回类型**，不是 `php_return_type`。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.summary_md.contains('ctx.ret` 写 zval”的')
	assert !input.summary_md.contains('php_return_type')
	assert input.summary_md.contains('bridge/runtime 返回值丢失')
	assert input.summary_md.contains('RequestOwnedZBox')
}

fn test_heuristic_reflection_filters_broken_code_fragments_from_summary() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .block
		seed_anchor:     'entry:1'
		seed_text:       '把 PHP 暴露的 `dispatch_request/dispatch_body/dispatch_envelope/dispatch` 改成返回 `RequestOwnedZBox`。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				score:       0.97
				scope:       .block
				kind:        'message'
				anchor:      'entry:2'
				text:        '这说明锅已经不在 sample 了，是真正的 bridge/runtime 返回值丢失。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				score:       0.95
				scope:       .block
				kind:        'message'
				anchor:      'entry:3'
				text:        '&VSlimResponse` 版本保留成内部 `*_raw。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.summary_md.contains('&VSlimResponse')
	assert !input.summary_md.contains('*_raw')
	assert input.summary_md.contains('bridge/runtime 返回值丢失')
	assert input.summary_md.contains('RequestOwnedZBox')
}

fn test_heuristic_reflection_filters_test_status_fragments() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .block
		seed_anchor:     'entry:1'
		seed_text:       'login -> console` 这条已经恢复成 `FINAL|200|1830|`。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				score:       0.97
				scope:       .block
				kind:        'message'
				anchor:      'entry:2'
				text:        '测试状态变成 FINAL|200|1830|，说明这次检查通过。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.title.contains('FINAL|')
	assert !input.title.contains('login -> console')
	assert !input.summary_md.contains('FINAL|')
	assert !input.summary_md.contains('login -> console')
}

fn test_heuristic_reflection_filters_smoke_and_tmp_probe_fragments() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .block
		seed_anchor:     'entry:1'
		seed_text:       'smoke 已经全绿了，说明主链实际上是通的。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				score:       0.97
				scope:       .block
				kind:        'message'
				anchor:      'entry:2'
				text:        '/tmp/ks_singleton_pages_probe.php'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.title.contains('smoke')
	assert !input.summary_md.contains('/tmp/ks_singleton_pages_probe.php')
	assert !input.summary_md.contains('全绿')
}

fn test_heuristic_reflection_filters_one_off_validation_process() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .block
		seed_anchor:     'entry:1'
		seed_text:       '刚才那个 smoke 脚本大概率只是撞到旧 `so` 或中间态，我再把它和 PHPT 各跑一遍，确认这轮。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				score:       0.97
				scope:       .block
				kind:        'message'
				anchor:      'entry:2'
				text:        'body'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.title.contains('刚才那个')
	assert !input.title.contains('smoke')
	assert !input.summary_md.contains('body')
	assert !input.summary_md.contains('PHPT 各跑一遍')
}

fn test_heuristic_reflection_filters_debug_process_fragments() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .block
		seed_anchor:     'entry:1'
		seed_text:       '`lldb` 没把回溯吐出来，我换成更直接的 `thread backtrace`。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				score:       0.97
				scope:       .block
				kind:        'message'
				anchor:      'entry:2'
				text:        '/console/ops'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				score:       0.95
				scope:       .block
				kind:        'message'
				anchor:      'entry:3'
				text:        '`lldb`，目标就是抓 `/ops` 的回溯。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.title.contains('lldb')
	assert !input.summary_md.contains('/console/ops')
	assert !input.summary_md.contains('thread backtrace')
}

fn test_heuristic_reflection_persist_input_uses_structured_sections_and_clean_title() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '你说得对，所以我已经把模板改成不把配置路径写死的方式了。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.88
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '服务模板如果把 toml 路径写死，就只适合单实例，不适合多环境切换。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title == '把模板改成不把配置路径写死的方式了'
	assert input.summary_md.contains('# 摘要')
	assert input.summary_md.contains('## 关键决策')
	assert input.summary_md.contains('## 重要约束')
	assert input.summary_md.contains('toml 路径写死') || input.summary_md.contains('单实例')
	assert input.insight_md.contains('## 后续关注')
}

fn test_heuristic_reflection_persist_input_prefers_durable_sentences_over_transient_status() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '验证通过了，我现在把这批文件按同一组功能改动一起提交。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.95
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '我已经定位到直接触发点了：`buffer.js` 不是运行时动态推出来的，而是代码里直接用 `@VMODROOT` 拼路径去读。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.92
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        '这样就能解释为什么你的进程会去找 `/tmp/vjsx/...`，也说明运行时资源路径解析依赖 `@VMODROOT`。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.summary_md.contains('buffer.js') || input.summary_md.contains('@VMODROOT')
	assert !input.summary_md.contains('验证通过了，我现在把这批文件按同一组功能改动一起提交')
	assert !input.summary_md.contains('随后会把当前 main 上的两条本地提交一并推到远端')
}

fn test_heuristic_reflection_persist_input_skips_shell_prompt_lines() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '我已经定位到直接触发点了：`buffer.js` 不是运行时动态推出来的，而是代码里直接用 `@VMODROOT` 拼路径去读。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        'root@iZ2ze426aj3w242kk3b9dxZ:~/wwwroot/vhttpd# ./vhttpd examples/feishu_cb-app-ts/remote.example.toml'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.summary_md.contains('buffer.js')
	assert !input.summary_md.contains('root@iZ2ze426aj3w242kk3b9dxZ')
	assert !input.summary_md.contains('./vhttpd examples/feishu_cb-app-ts/remote.example.toml')
}

fn test_heuristic_reflection_persist_input_keeps_runtime_errors_out_of_decisions_and_constraints() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '我已经定位到直接触发点了：`buffer.js` 不是运行时动态推出来的，而是代码里直接用 `@VMODROOT` 拼路径去读。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.94
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        'V panic: /tmp/vjsx/web/js/buffer.js file not found'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        '这样就能解释为什么你的进程会去找 `/tmp/vjsx/...`，也说明运行时资源路径解析依赖 `@VMODROOT`。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.summary_md.contains('## 关键决策\n\n- V panic:')
	assert !input.summary_md.contains('## 重要约束\n\n- V panic:')
	assert input.summary_md.contains('buffer.js') || input.summary_md.contains('@VMODROOT')
}

fn test_heuristic_reflection_persist_input_omits_empty_decision_and_constraint_sections() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '这次讨论主要围绕 fetch 主机运行时支持和对应测试。'
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.summary_md.contains('# 摘要')
	assert !input.summary_md.contains('## 关键决策')
	assert !input.summary_md.contains('## 重要约束')
}

fn test_heuristic_reflection_persist_input_promotes_capability_scope_to_decision() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '把改动范围确认下来了，这一批是完整的 fetch 主机运行时支持和对应测试，不像是混杂了别的主题。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '这批改动看起来像一组新的 host fetch 能力补充：已有 4 个文件的增量修改，加上 3 个新文件。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.summary_md.contains('## 关键决策')
	assert input.summary_md.contains('完整的 fetch 主机运行时支持')
	assert input.summary_md.contains('host fetch 能力补充')
	assert !input.summary_md.contains('## 重要约束')
}

fn test_heuristic_reflection_persist_input_filters_planning_lines_from_sections() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '不要求用户先手动 export，也兼容现在的安装脚本。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.94
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '我要动两处文件：把 runtime_doctor.sh 做成和程序一致的多候选探测。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        '我去看一下 ~/Source/vhttpd 里的 GitHub Actions 配置。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.summary_md.contains('不要求用户先手动 export')
	assert input.summary_md.contains('## 重要约束')
	assert !input.summary_md.contains('我要动两处文件')
	assert !input.summary_md.contains('我去看一下')
}

fn test_heuristic_reflection_persist_input_skips_conversational_title_candidates() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '我建议分开看。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '代码全面改成 import guweigang.vjsx。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        '不要再走 /tmp/vjsx -> ~/.vmodules/vjsx 这种临时软链方案。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title != '我建议分开看'
	assert input.title.contains('import guweigang.vjsx') || input.title.contains('/tmp/vjsx')
	assert input.summary_md.contains('代码全面改成 import guweigang.vjsx')
}

fn test_heuristic_reflection_persist_input_filters_first_person_test_rewrite_plan() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       'http.Server 支持先塞一个已经监听好的 TcpListener。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '固定端口也不够稳，说明这台机器上刚好有别的进程占着该端口。我要把测试改成“先向系统申请空闲端口”。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        'http.Server 支持先塞一个已经监听好的 TcpListener。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title == 'http.Server 支持先塞一个已经监听好的 TcpListener'
	assert !input.summary_md.contains('我要把测试改成')
	assert input.title.contains('TcpListener')
	assert input.summary_md.contains('先向系统申请空闲端口')
}

fn test_heuristic_reflection_persist_input_filters_context_dependent_short_notes() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       'http.Server 支持先塞一个已经监听好的 TcpListener。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '固定端口也不够稳，说明这台机器上刚好有别的进程占着该端口。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        '每次调用都传一遍。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.summary_md.contains('端口')
	assert !input.summary_md.contains('每次调用都传一遍')
	assert !input.summary_md.contains('## 关键决策')
}

fn test_heuristic_reflection_persist_input_filters_future_work_promises() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '不要求用户先手动 export，也兼容现在的安装脚本。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '然后把 README 的安装说明改成“默认会自动找包内 runtime/vjsx，也支持 VJSX_ASSET_ROOT 覆盖”。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        '找到具体 workflow 和脚本链路后，我会直接指出是哪一步造成的。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.summary_md.contains('README 的安装说明：默认会自动找包内 runtime/vjsx')
	assert input.summary_md.contains('## 重要约束')
	assert !input.summary_md.contains('我会直接指出')
	assert !input.summary_md.contains('找到具体 workflow')
}

fn test_heuristic_reflection_filters_isolated_token_titles() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       'updated_at'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        'memory_reflections 应该优先通过 topic_key 做 add/update 判定。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title == 'memory_reflections 应该优先通过 topic_key 做 add/update 判定'
	assert !input.summary_md.contains('updated_at')
}

fn test_heuristic_reflection_filters_one_off_closure_validation() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '现在我把 3 条真实写动作再跑一遍，确认整个闭环真正通。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '普通 typed write 应该根据 write_set 增量维护标量索引，避免小写入扫描整棵树。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title == '普通 typed write 应该根据 write_set 增量维护标量索引，避免小写入扫描整棵树'
	assert !input.summary_md.contains('确认整个闭环真正通')
}

fn test_heuristic_reflection_filters_investigation_process_titles() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       'VSlim` 依赖的 V `mysql` 模块到底是怎么建连接的，确认是不是它对 `127.0.0.1/root/password'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        'VSlim 的数据库连接配置应该显式记录 host、user 和 password，避免依赖模块默认值。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title == 'VSlim 的数据库连接配置应该显式记录 host、user 和 password，避免依赖模块默认值'
	assert !input.summary_md.contains('到底是怎么建连接')
	assert !input.summary_md.contains('确认是不是')
}

fn test_heuristic_reflection_filters_command_and_regression_confirmation_noise() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       'zim_VSlim__Psr7__ServerRequest_withAttribute` 和 `vphp_return_obj` 的桥接代码，确认这个 `r'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.96
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        'php test.phpt'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.95
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        '我补一次正式跑法确认回归。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-4'.bytes()
				column_name: 'content_md'
				target_id:   'target-4'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[2]'
				text:        'ServerRequest.withAttribute 返回对象时必须走 vphp_return_obj，避免把对象返回值当普通 zval 处理。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title == 'ServerRequest.withAttribute 返回对象时必须走 vphp_return_obj，避免把对象返回值当普通 zval 处理'
	assert !input.summary_md.contains('php test.phpt')
	assert !input.summary_md.contains('正式跑法确认回归')
	assert !input.summary_md.contains('确认这个')
}

fn test_heuristic_reflection_filters_malformed_inline_code_and_informal_debug_conclusion() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '把 PHP 暴露的 `dispatch_request/dispatch_body/dispatch_envelope/dispatch` 改成返回 `RequestOwnedZBox`'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.96
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '这说明锅已经不在 sample 了，是真正的 bridge/runtime 返回值丢失。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.95
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        r'WorkspaceContextMiddleware` 里 `$handler->handle($request)` 直接拿回了 `null'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-4'.bytes()
				column_name: 'content_md'
				target_id:   'target-4'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[2]'
				text:        'PHP 暴露的 dispatch_request/dispatch_body/dispatch_envelope/dispatch 应该返回 RequestOwnedZBox。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title == '把 PHP 暴露的 `dispatch_request/dispatch_body/dispatch_envelope/dispatch` 改成返回 `RequestOwnedZBox`'
	assert input.summary_md.contains('dispatch_request/dispatch_body/dispatch_envelope/dispatch')
	assert input.summary_md.contains('bridge/runtime 返回值丢失')
	assert !input.summary_md.contains('WorkspaceContextMiddleware`')
	assert !input.summary_md.contains('`null')
}

fn test_heuristic_reflection_filters_hypothesis_validation_process() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '这不是最终一定的答案，但如果它能立刻让这条 PHPT 通过，就说明崩点确实就在“对象返回”。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        'PHP 类方法返回对象时必须走对象返回桥接层。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.title.contains('不是最终一定')
	assert !input.title.contains('如果它能')
	assert !input.summary_md.contains('不是最终一定')
	assert !input.summary_md.contains('如果它能')
}

fn test_heuristic_reflection_filters_future_action_process() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '把范围压到 prepared-query 这条链了。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '确认 query builder 的写接口能直接用，接下来就把 console 页的表单和 controller action 一次性补�...'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        'prepared-query 写接口需要避开 VSlim Query 包装。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.title.contains('把范围压到')
	assert !input.title.contains('这条链')
	assert !input.summary_md.contains('接下来就把')
	assert !input.summary_md.contains('一次性补')
	assert !input.summary_md.contains('�')
}

fn test_heuristic_reflection_filters_unresolved_question_only_process() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '是不是同一个 `v_ptr` 被不同 PHP wrapper 重复接管'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '同一个 `v_ptr` 不能被多个 PHP wrapper 同时接管所有权。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.title.contains('是不是同一个')
	assert !input.summary_md.contains('是不是同一个')
}

fn test_heuristic_reflection_filters_malformed_code_and_first_person_validation() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       r'dispatch_request(new VSlim\Vhttpd\Request(...))` 这条验证路径里，表单 body 没有自动落成 `parsedBody'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        'vphp` 或 `vslim'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        '我再看一下这轮改动边界和验证结果，确认没有漏掉明显的回归'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-4'.bytes()
				column_name: 'content_md'
				target_id:   'target-4'
				score:       0.89
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[2]'
				text:        '表单 body 解析需要显式写入 parsedBody。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.title.contains('dispatch_request(new VSlim')
	assert !input.title.contains('vphp`')
	assert !input.title.contains('我再看一下')
	assert !input.summary_md.contains('dispatch_request(new VSlim')
	assert !input.summary_md.contains('vphp`')
	assert !input.summary_md.contains('我再看一下')
}

fn test_heuristic_reflection_rewrites_vague_resolution_title() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '定位到了：污染源不在 `authUser`，也不在 `resolveContext`，而是在 `dashboard()`。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '表结构已经说明原因了：`updated_at` 这一列在旧库上没加成功，而 `chunks/status/owner` 加上了。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title != '定位到了'
	assert !input.title.contains('表结构已经说明原因了')
	assert !input.summary_md.contains('定位到了：')
	assert !input.summary_md.contains('表结构已经说明原因了：')
	assert input.title.contains('污染源') || input.title.contains('updated_at')
}

fn test_heuristic_reflection_keeps_title_fallback_for_complete_markdown() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '定位到了：污染源不在 `authUser`，也不在 `resolveContext`，而是在 `dashboard()`。'
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title.contains('污染源')
	assert input.summary_md.contains('- 污染源不在 `authUser`，也不在 `resolveContext`，而是在 `dashboard()`')
}

fn test_heuristic_reflection_filters_raw_schema_fragments_before_outline() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '表结构已经说明原因了：`updated_at` 这一列在旧库上没加成功，而 `chunks/status/owner` 加上了。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        'ADD COLUMN updated_at datetime not null'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title.contains('updated_at')
	assert !input.summary_md.contains('ADD COLUMN')
}

fn test_heuristic_reflection_strips_conversational_root_cause_prefix() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '这条我刚看到一个很像根因的地方了：`resolve_container_service()` 从容器拿的是 `RequestOwnedZBox`。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '返回值需要从 box 里 take 出 zval，再交给 ctx，避免被提前 drain 掉。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.title.contains('这条我刚看到')
	assert input.title.contains('resolve_container_service')
		|| input.title.contains('RequestOwnedZBox') || input.title.contains('zval')
	assert input.summary_md.contains('resolve_container_service')
}

fn test_heuristic_reflection_filters_future_first_person_rewrite_actions() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '我去把这一步改成“从 box 里 take 出 zval，再交给 ctx”，就不该再被 drain 掉。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.93
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '最终做法是返回值从 box 中取出 zval 后再交给 ctx 管理。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.summary_md.contains('我去把')
	assert input.summary_md.contains('zval')
}

fn test_heuristic_reflection_strips_confirmation_prefix_and_future_steps() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '我确认了：`persistent_assoc_with_value/without_key` 只服务于 `attributes_ref` 这一路。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '下一步我要去对齐崩溃前最后一批日志。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title.starts_with('`persistent_assoc_with_value/without_key`')
	assert !input.title.contains('我确认了')
	assert !input.summary_md.contains('下一步我要')
}

fn test_heuristic_reflection_rewrites_first_person_decisions() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '不能直接当 PHP 脚本跑，我改用官方 `run-tests.php` 复核它们，避免误判。'
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.summary_md.contains('改用官方 `run-tests.php`')
	assert !input.summary_md.contains('我改用')
}

fn test_heuristic_reflection_treats_single_artifact_scope_as_constraint() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '`persistent_assoc_with_value/without_key` 只服务于 `attributes_ref` 这一路，没有别的 payload 复用。'
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.summary_md.contains('## 重要约束')
	assert input.summary_md.contains('attributes_ref')
}

fn test_reflection_job_has_distillable_outline_rejects_empty_boilerplate_jobs() {
	empty_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '我再看一下这轮验证结果。'
	}
	assert !reflection_job_has_distillable_outline(empty_job, ReflectionDistillOptions{})

	durable_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-2'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '代码全面改成 import guweigang.vjsx。'
	}
	assert reflection_job_has_distillable_outline(durable_job, ReflectionDistillOptions{})
}

fn test_reflection_job_has_distillable_outline_rejects_debug_and_probe_process() {
	debug_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '再往上是 [main__VSlimPsr7ServerRequest_free](/Users/demo/generated.c)。'
	}
	assert !reflection_job_has_distillable_outline(debug_job, ReflectionDistillOptions{})

	probe_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-2'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '会只看非敏感字段，并做一个最轻的连通性探测。'
	}
	assert !reflection_job_has_distillable_outline(probe_job, ReflectionDistillOptions{})

	progress_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-3'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '我这轮主要做了三件事。'
	}
	assert !reflection_job_has_distillable_outline(progress_job, ReflectionDistillOptions{})
}

fn test_reflection_job_has_distillable_outline_rejects_isolated_symbols_and_dialogue_controls() {
	symbol_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       'builtin__DenseArray_has_index'
	}
	assert !reflection_job_has_distillable_outline(symbol_job, ReflectionDistillOptions{})

	project_name_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-2'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       'knowledge-studio'
	}
	assert !reflection_job_has_distillable_outline(project_name_job, ReflectionDistillOptions{})

	artifact_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-3'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       'vslim.so'
	}
	assert !reflection_job_has_distillable_outline(artifact_job, ReflectionDistillOptions{})

	dialogue_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-4'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '同意，你继续，一定要挖出 vslim 或 vphp 的 bug。'
	}
	assert !reflection_job_has_distillable_outline(dialogue_job, ReflectionDistillOptions{})
}

fn test_heuristic_reflection_removes_isolated_artifact_points_from_summary() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '`make ext` 失败是个已知编译环境问题，不是这次 bug 本身：它少了 `mysql.h` include。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        'vslim.so'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.summary_md.contains('mysql.h')
	assert !input.summary_md.contains('- vslim.so')
}

fn test_heuristic_reflection_compacts_long_lines_without_ellipsis_fragments() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '`TraceMiddleware(request->withHeader)` 和 `SessionStartMiddleware` 同时在链上，才会把真实顺序 dispatch 到最终 handler，而且被前置 middleware 改过 header 的 ServerRequest 需要继续保留。'
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert !input.summary_md.contains('...')
	assert !input.summary_md.contains('……')
	assert input.summary_md.contains('TraceMiddleware')
}

fn test_heuristic_reflection_stabilizes_diagnostic_claims() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '`borrowed` 这条线看起来更可疑了，因为 `NextHandler` 是 `memdup` 出来的裸 V 内存。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.92
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '对象 registry 清理代码看起来是做了的，所以我不想继续空猜。'
			},
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'target-3'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[1]'
				text:        '`NextHandler` wrapper 不能重复接管 `borrowed` 指针。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title.contains('NextHandler')
	assert input.summary_md.contains('memdup')
	assert !input.title.contains('可疑')
	assert !input.summary_md.contains('空猜')
	assert !input.summary_md.contains('看起来是做了的')
	assert input.summary_md.contains('NextHandler')
}

fn test_heuristic_reflection_prefers_specific_compile_failure_over_signal_title() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '编译这边有新信号了：`vslim_generated.c` 更新时间已经变了，但 `vslim.so` 没产出来。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '共享库阶段的失败点也明确了，不是别的，是 `Makefile` 这条 `ext` 没带 MySQL 头文件路径。'
			},
		]
	}
	input := heuristic_reflection_persist_input(job, ReflectionDistillOptions{})
	assert input.title.contains('Makefile') || input.title.contains('vslim_generated.c')
	assert input.title.contains('MySQL') || input.title.contains('vslim.so')
	assert !input.title.contains('有新信号')
	assert input.summary_md.contains('Makefile')
}

fn test_reflection_job_has_distillable_outline_rejects_experiment_plans() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '我去做一个对照实验：同一套模板、同一套数据，不通过容器里的单例 `ConsoleController`。'
	}
	assert !reflection_job_has_distillable_outline(job, ReflectionDistillOptions{})
}

fn test_reflection_job_has_distillable_outline_rejects_process_labels_and_future_checks() {
	label_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       'session + access'
	}
	assert !reflection_job_has_distillable_outline(label_job, ReflectionDistillOptions{})

	future_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-2'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '我再确认一次“只有 workspace middleware，没有 access/trace”时到底稳不稳。'
	}
	assert !reflection_job_has_distillable_outline(future_job, ReflectionDistillOptions{})

	wait_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-3'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '这轮要等新 `.so` 生效后才有意义。'
	}
	assert !reflection_job_has_distillable_outline(wait_job, ReflectionDistillOptions{})

	regenerate_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-4'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '我要重新生成 `php_bridge.c`，这一步用 `emit-only` 就够了。'
	}
	assert !reflection_job_has_distillable_outline(regenerate_job, ReflectionDistillOptions{})

	conditional_job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-5'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '如果是，我会把读路径的失败面再收稳一点。'
	}
	assert !reflection_job_has_distillable_outline(conditional_job, ReflectionDistillOptions{})
}

fn test_reflection_job_has_distillable_outline_rejects_unbalanced_cjk_quotes() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '2 attrs 不能回退”，一个看“3 attrs 能不能终于过'
	}
	assert !reflection_job_has_distillable_outline(job, ReflectionDistillOptions{})
}

fn test_reflection_job_has_distillable_outline_rejects_non_target_failure_process() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '这个失败也有信息量，不过还不是我们要的那个崩溃。'
		evidence:        [
			ReflectionEvidence{
				table_name:  'entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'target-2'
				score:       0.91
				scope:       .block
				kind:        'paragraph'
				anchor:      '/'
				path_hint:   'blocks[0]'
				text:        '会话没带回去。'
			},
		]
	}
	assert !reflection_job_has_distillable_outline(job, ReflectionDistillOptions{})
}

fn test_reflection_job_has_distillable_outline_rejects_truncated_markdown_links() {
	job := ReflectionJob{
		branch_name:     'main'
		table_name:      'entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/'
		seed_text:       '现在 [WorkspaceRepository.php](/Users/demo/app/Repositories/WorkspaceRepository.'
	}
	assert !reflection_job_has_distillable_outline(job, ReflectionDistillOptions{})
}
