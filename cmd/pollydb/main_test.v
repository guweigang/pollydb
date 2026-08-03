module main

import os
import storage
import term
import time

fn test_parse_register_table_spec() {
	spec := parse_register_table_spec('users', 'id', 'id:string,name:string,email:string?,active:bool',
		'email_idx:email') or { panic(err) }
	assert spec.name() == 'users'
	assert spec.table.primary_key == ['id']
	assert spec.table.columns.len == 4
	assert spec.table.columns[2].name == 'email'
	assert spec.table.columns[2].nullable
	assert spec.table.columns[3].typ == .bool_
	assert spec.indexes.len == 1
	assert spec.indexes[0].name == 'email_idx'
	assert spec.indexes[0].column == 'email'
	assert !spec.indexes[0].stores_row
}

fn test_parse_register_table_spec_covering_index() {
	spec := parse_register_table_spec('users', 'id', 'id:string,name:string,email:string?',
		'email_cover:email:covering') or { panic(err) }
	assert spec.indexes.len == 1
	assert spec.indexes[0].name == 'email_cover'
	assert spec.indexes[0].column == 'email'
	assert spec.indexes[0].stores_row
}

fn test_parse_register_table_spec_sum_aggregate_column() {
	spec := parse_register_table_spec('metrics', 'id', 'id:i64:sum,name:string', '-') or {
		panic(err)
	}
	assert spec.table.columns.len == 2
	assert spec.table.columns[0].aggregate == .sum
	assert spec.table.columns[1].aggregate == .none
}

fn test_parse_register_table_spec_enum_and_json_columns() {
	spec := parse_register_table_spec('items', 'id', 'id:string,status:enum(active|draft|done),meta:json,enabled:bool',
		'-') or { panic(err) }
	assert spec.table.columns.len == 4
	assert spec.table.columns[1].typ == .enum_
	assert spec.table.columns[1].enum_values == ['active', 'draft', 'done']
	assert spec.table.columns[2].typ == .json_
	assert spec.table.columns[3].typ == .bool_
}

fn test_parse_register_table_spec_datetime_modifiers() {
	spec := parse_register_table_spec('events', 'id', 'id:string,created_at:datetime:current_timestamp,updated_at:datetime:current_timestamp:auto_update',
		'-') or { panic(err) }
	assert spec.table.columns[1].typ == .datetime_
	assert spec.table.columns[1].default_current_timestamp
	assert !spec.table.columns[1].auto_update_current_timestamp
	assert spec.table.columns[2].default_current_timestamp
	assert spec.table.columns[2].auto_update_current_timestamp
}

fn test_parse_register_table_spec_json_path_indexes() {
	spec := parse_register_table_spec('items', 'id', 'id:string,meta:json', 'kind_idx:meta.kind:string,flag_cover:meta.enabled:bool:covering') or {
		panic(err)
	}
	assert spec.indexes.len == 2
	assert spec.indexes[0].is_json_path()
	assert spec.indexes[0].json_field == 'kind'
	assert spec.indexes[0].json_field_type == .string_
	assert !spec.indexes[0].stores_row
	assert spec.indexes[1].is_json_path()
	assert spec.indexes[1].json_field == 'enabled'
	assert spec.indexes[1].json_field_type == .bool_
	assert spec.indexes[1].stores_row
}

fn test_parse_register_table_spec_markdown_selector_indexes() {
	spec := parse_register_table_spec('notes', 'id', 'id:string,body:markdown', 'body_heading_text_idx:body#heading_text:2:string,body_link_count_idx:body#links:i64,body_code_lang_cover:body#code_block_lang:string:covering') or {
		panic(err)
	}
	assert spec.indexes.len == 3
	assert spec.indexes[0].is_field_selector()
	assert spec.indexes[0].column == 'body'
	assert spec.indexes[0].field_selector_plugin() == 'markdown'
	assert spec.indexes[0].field_selector() == 'heading_text:2'
	assert spec.indexes[0].json_field_type == .string_
	assert !spec.indexes[0].stores_row
	assert spec.indexes[1].is_field_selector()
	assert spec.indexes[1].field_selector() == 'links'
	assert spec.indexes[1].json_field_type == .i64_
	assert spec.indexes[2].is_field_selector()
	assert spec.indexes[2].field_selector() == 'code_block_lang'
	assert spec.indexes[2].json_field_type == .string_
	assert spec.indexes[2].stores_row
}

fn test_parse_index_defs_rejects_invalid_markdown_selector_type() {
	parse_index_defs('body_heading_text_idx:body#heading_text:2:bool') or {
		assert err.msg().contains('markdown selector index type must be string or i64')
		return
	}
	panic('expected parse_index_defs to reject invalid markdown selector type')
}

fn test_format_table_spec_round_trips_markdown_selector_indexes() {
	spec := parse_register_table_spec('notes', 'id', 'id:string,body:markdown', 'body_heading_text_idx:body#heading_text:2:string,body_link_count_idx:body#links:i64,body_code_lang_cover:body#code_block_lang:string:covering') or {
		panic(err)
	}
	rendered := format_table_spec(spec)
	assert rendered.contains('body_heading_text_idx:body#heading_text:2:string')
	assert rendered.contains('body_link_count_idx:body#links:i64')
	assert rendered.contains('body_code_lang_cover:body#code_block_lang:string:covering')
}

fn test_parse_register_table_spec_embedding_indexes() {
	spec := parse_register_table_spec('notes', 'id', 'id:string,summary:string,body:markdown',
		'summary_vec_idx:summary#embedding(bge-small),body_path_vec_idx:body#embedding(path,bge-small)') or {
		panic(err)
	}
	assert spec.indexes.len == 2
	assert spec.indexes[0].is_embedding()
	assert spec.indexes[0].embedding_profile == 'bge-small'
	assert spec.indexes[0].embedding_scope == ''
	assert spec.indexes[1].is_embedding()
	assert spec.indexes[1].embedding_source_plugin == 'markdown'
	assert spec.indexes[1].embedding_scope == 'path'
}

fn test_format_table_spec_round_trips_embedding_indexes() {
	spec := parse_register_table_spec('notes', 'id', 'id:string,summary:string,body:markdown',
		'summary_vec_idx:summary#embedding(bge-small),body_path_vec_idx:body#embedding(path,bge-small)') or {
		panic(err)
	}
	rendered := format_table_spec(spec)
	assert rendered.contains('summary_vec_idx:summary#embedding(bge-small)')
	assert rendered.contains('body_path_vec_idx:body#embedding(path,bge-small)')
}

fn test_parse_index_defs_dash_means_empty() {
	indexes := parse_index_defs('-') or { panic(err) }
	assert indexes.len == 0
}

fn test_parse_index_defs_rejects_unknown_mode() {
	parse_index_defs('email_idx:email:weird') or {
		assert err.msg().contains('unsupported index mode')
		return
	}
	panic('expected parse_index_defs to reject unknown index mode')
}

fn test_parse_register_table_spec_mixed_index_modes() {
	spec := parse_register_table_spec('users', 'id', 'id:string,email:string?,name:string',
		'email_idx:email,email_cover:email:covering') or { panic(err) }
	assert spec.indexes.len == 2
	assert !spec.indexes[0].stores_row
	assert spec.indexes[1].stores_row
}

fn test_parse_typed_value_prefix_string_column() {
	column := storage.ColumnDef.new('email', .string_, false) or { panic(err) }
	value := parse_typed_value(column, 'ada@') or { panic(err) }
	match value {
		string { assert value == 'ada@' }
		else { panic('expected string prefix') }
	}
}

fn test_parse_typed_value_current_timestamp_datetime() {
	column := storage.ColumnDef.datetime('created_at', false) or { panic(err) }
	value := parse_typed_value(column, 'CURRENT_TIMESTAMP') or { panic(err) }
	match value {
		string {
			_ := time.parse_rfc3339(value) or { panic(err) }
		}
		else {
			panic('expected datetime string')
		}
	}
}

fn test_cli_new_strips_double_dash() {
	cli := PollyDbCli.new(['--', 'status', '/tmp/example'])
	assert cli.args == ['status', '/tmp/example']
}

fn test_cli_new_extracts_json_flag() {
	cli := PollyDbCli.new(['preview-schema-update', '--json', './schema.yml'])
	assert cli.json_output
	assert cli.args == ['preview-schema-update', './schema.yml']
}

fn test_cli_title_renders_without_panicking() {
	title := cli_title('Table')
	assert title.len > 0
	assert term.strip_ansi(title).contains('Table')
}

fn test_usage_includes_prefix_index_projected() {
	cli := PollyDbCli.new([])
	assert cli.usage().contains('prefix-index-projected')
}

fn test_usage_includes_query_fts_commands() {
	cli := PollyDbCli.new([])
	assert cli.usage().contains('query-fts-preview')
	assert cli.usage().contains('query-fts')
}

fn test_usage_includes_agentview_memory_commands() {
	cli := PollyDbCli.new([])
	assert cli.usage().contains('distill-agentview-memory')
	assert cli.usage().contains('extract-agentview-memory')
	assert cli.usage().contains('POLLYDB_MEMORY_EMBEDDING_MODEL')
	assert cli.usage().contains('POLLYDB_MEMORY_GENERATION_MODEL')
	assert cli.usage().contains('POLLYDB_MEMORY_FAST_DISTILL')
}

fn test_usage_includes_scan_index_between() {
	cli := PollyDbCli.new([])
	assert cli.usage().contains('scan-index-between')
}

fn test_usage_includes_scan_index_after_and_before() {
	cli := PollyDbCli.new([])
	assert cli.usage().contains('scan-index-after')
	assert cli.usage().contains('scan-index-before')
}

fn test_run_register_table_on_empty_branch_does_not_rebuild_indexes() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-cli-register-table-empty-branch')
	defer {
		os.rmdir_all(dir) or {}
	}
	_ := storage.PersistentDatabase.init(dir, 'main') or { panic(err) }
	mut cli := PollyDbCli.new(['create-table', dir, 'users', 'id', 'id:string,email:string', '-'])
	cli.run_register_table() or { panic(err) }

	mut reopened := storage.PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	assert reopened.has_table('users')
	assert reopened.branch_names_committed().len == 0
}

fn test_run_rebuild_indexes_on_empty_branch_is_noop() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-cli-rebuild-indexes-empty-branch')
	defer {
		os.rmdir_all(dir) or {}
	}
	_ := storage.PersistentDatabase.init(dir, 'main') or { panic(err) }
	mut cli := PollyDbCli.new(['rebuild-indexes', dir])
	cli.run_rebuild_indexes() or { panic(err) }
}

fn test_usage_includes_aggregate_commands() {
	cli := PollyDbCli.new([])
	assert cli.usage().contains('count-rows')
	assert cli.usage().contains('count-rows-range')
	assert cli.usage().contains('sum-column')
	assert cli.usage().contains('sum-column-range')
	assert cli.usage().contains('projectors')
	assert cli.usage().contains('register-aggregate-projection')
	assert cli.usage().contains('refresh-aggregate-projections')
	assert cli.usage().contains('stale_one | stale_up_to | stale_all')
	assert cli.usage().contains('aggregate projector priority')
	assert cli.usage().contains('aggregate projector cost_hint')
}

fn test_usage_includes_create_table_alias() {
	cli := PollyDbCli.new([])
	assert cli.usage().contains('create-table')
}

fn test_usage_includes_rebuild_indexes() {
	cli := PollyDbCli.new([])
	assert cli.usage().contains('rebuild-indexes')
	assert cli.usage().contains('--json')
}

fn test_parse_aggregate_projection_refresh_policy() {
	assert parse_aggregate_projection_refresh_policy('none') or { panic(err) } == .none
	assert parse_aggregate_projection_refresh_policy('stale_one') or { panic(err) } == .stale_one
	assert parse_aggregate_projection_refresh_policy('stale_up_to') or { panic(err) } == .stale_up_to
	assert parse_aggregate_projection_refresh_policy('stale_all') or { panic(err) } == .stale_all
}

fn test_parse_aggregate_projection_cost_hint() {
	assert parse_aggregate_projection_cost_hint('low') or { panic(err) } == .low
	assert parse_aggregate_projection_cost_hint('medium') or { panic(err) } == .medium
	assert parse_aggregate_projection_cost_hint('high') or { panic(err) } == .high
}

fn test_parse_fts_scope() {
	assert parse_fts_scope('heading') or { panic(err) } == .heading
	assert parse_fts_scope('code_block') or { panic(err) } == .code_block
	parse_fts_scope('regex') or {
		assert err.msg().contains('unknown fts scope')
		return
	}
	panic('expected parse_fts_scope to reject invalid scope')
}

fn test_parse_fts_query_kind() {
	assert parse_fts_query_kind('term') or { panic(err) } == .term
	assert parse_fts_query_kind('any') or { panic(err) } == .any
	parse_fts_query_kind('regex') or {
		assert err.msg().contains('unknown fts query kind')
		return
	}
	panic('expected parse_fts_query_kind to reject invalid kind')
}

fn test_parse_optional_columns_and_limit() {
	columns, limit := parse_optional_columns_and_limit(['body,title', '5'], 0) or { panic(err) }
	assert columns == ['body', 'title']
	assert limit == 5
	columns_only_limit, limit_only := parse_optional_columns_and_limit(['7'], 0) or { panic(err) }
	assert columns_only_limit.len == 0
	assert limit_only == 7
}

fn test_usage_includes_set_json_path() {
	cli := PollyDbCli.new([])
	assert cli.usage().contains('set-json-path')
}

fn test_usage_includes_patch_json_paths() {
	cli := PollyDbCli.new([])
	assert cli.usage().contains('patch-json-paths')
	assert cli.usage().contains('null-json-path')
	assert cli.usage().contains('delete-json-path')
}

fn test_usage_includes_sync_commands() {
	cli := PollyDbCli.new([])
	assert cli.usage().contains('sync-push')
	assert cli.usage().contains('sync-pull')
	assert cli.usage().contains('recommend-sync-policy')
	assert cli.usage().contains('sync-push-sidecar')
	assert cli.usage().contains('sync-pull-sidecar')
	assert cli.usage().contains('sidecar-repos')
	assert cli.usage().contains('sidecar-repo-summaries')
	assert cli.usage().contains('sidecar-global-activity')
	assert cli.usage().contains('sidecar-open-repo')
	assert cli.usage().contains('sidecar-governance-status')
	assert cli.usage().contains('sidecar-branches')
	assert cli.usage().contains('sidecar-branch-status')
	assert cli.usage().contains('sidecar-init-governance')
	assert cli.usage().contains('sidecar-grant-repo')
	assert cli.usage().contains('sidecar-set-repo-policy')
	assert cli.usage().contains('sidecar-set-branch-policy')
	assert cli.usage().contains('sidecar-set-rate-limit')
	assert cli.usage().contains('sidecar-audit-log')
	assert cli.usage().contains('sidecar-repo-activity')
	assert cli.usage().contains('sidecar-branch-activity')
	assert cli.usage().contains('sidecar-branch-log')
	assert cli.usage().contains('manifest_depth1 | manifest_depth2 | auto')
}

fn test_parse_sync_negotiation_policy() {
	assert parse_sync_negotiation_policy('regular') or { panic(err) } == .regular
	assert parse_sync_negotiation_policy('manifest_depth1') or { panic(err) } == .manifest_depth1
	assert parse_sync_negotiation_policy('manifest_depth2') or { panic(err) } == .manifest_depth2
	assert parse_sync_negotiation_policy('auto') or { panic(err) } == .auto
	parse_sync_negotiation_policy('weird') or {
		assert err.msg().contains('invalid sync negotiation policy')
		return
	}
	panic('expected invalid sync negotiation policy error')
}

fn test_cli_looks_like_url() {
	assert cli_looks_like_url('http://127.0.0.1:19191')
	assert cli_looks_like_url('https://example.com')
	assert !cli_looks_like_url('/tmp/mydb')
}

fn test_cli_render_sync_result_includes_auto_merged_status() {
	output := cli_render_sync_result('Sync Push (Sidecar)', 'push', '/tmp/source', 'main',
		'http://127.0.0.1:19191', 'main', 'manifest_depth1', 5, 1024, 'main', 'commit-123',
		'auto_merged')
	assert term.strip_ansi(output).contains('auto_merged')
}

fn test_parse_json_path_updates() {
	updates := parse_json_path_updates('kind.code=string:beta,enabled=null,legacy=delete,flag=bool:true') or {
		panic(err)
	}
	assert updates.len == 4
	assert updates[0].path == 'kind.code'
	assert updates[0].op == .set
	assert updates[1].op == .set
	assert updates[2].op == .delete
	assert updates[3].op == .set
}

fn test_parse_checkpoint_mode() {
	assert parse_checkpoint_mode('full')! == .full
	assert parse_checkpoint_mode('data_only')! == .data_only
	parse_checkpoint_mode('weird') or {
		assert err.msg().contains('invalid checkpoint mode')
		return
	}
	panic('expected invalid checkpoint mode error')
}

fn test_resolve_db_context_uses_cwd_repository_default_branch() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-cli-context-default-branch')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut db := storage.PersistentDatabase.init(dir, 'dev') or { panic(err) }
	db.create_branch('feature', '') or { panic(err) }
	db.close() or { panic(err) }
	old_cwd := os.getwd()
	defer {
		os.chdir(old_cwd) or {}
	}
	os.chdir(dir) or { panic(err) }
	cli := PollyDbCli.new(['get-row', 'users', '001'])
	ctx := cli.resolve_db_context(1, true) or { panic(err) }
	assert ctx.root_dir == os.real_path(dir)
	assert ctx.default_branch == 'dev'
	assert ctx.branch == 'dev'
	assert ctx.next_idx == 1
}

fn test_resolve_db_context_accepts_explicit_branch_without_root_dir() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-cli-context-explicit-branch')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut db := storage.PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.create_branch('feature', '') or { panic(err) }
	db.close() or { panic(err) }
	old_cwd := os.getwd()
	defer {
		os.chdir(old_cwd) or {}
	}
	os.chdir(dir) or { panic(err) }
	cli := PollyDbCli.new(['get-row', 'feature', 'users', '001'])
	ctx := cli.resolve_db_context(1, true) or { panic(err) }
	assert ctx.root_dir == os.real_path(dir)
	assert ctx.default_branch == 'main'
	assert ctx.branch == 'feature'
	assert ctx.next_idx == 2
}

fn test_resolve_db_context_accepts_repository_layout_without_repo_meta() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-cli-context-layout-only')
	defer {
		os.rmdir_all(dir) or {}
	}
	os.mkdir_all(os.join_path(dir, '.pollydb')) or { panic(err) }
	os.write_file(os.join_path(dir, '.pollydb', 'catalog.meta'), '') or { panic(err) }
	old_cwd := os.getwd()
	defer {
		os.chdir(old_cwd) or {}
	}
	os.chdir(dir) or { panic(err) }
	cli := PollyDbCli.new(['tables'])
	ctx := cli.resolve_db_context(1, true) or { panic(err) }
	assert ctx.root_dir == os.real_path(dir)
	assert ctx.default_branch == 'main'
	assert ctx.branch == 'main'
	assert ctx.next_idx == 1
}

fn test_build_typed_row() {
	spec := parse_register_table_spec('users', 'id', 'id:string,active:bool,score:i64,payload:bytes?,email:string?',
		'-') or { panic(err) }
	row := build_typed_row(spec, 'id=001,active=true,score=42,payload=hex:6162,email=null') or {
		panic(err)
	}
	id := row.get('id') or { panic(err) }
	active := row.get('active') or { panic(err) }
	score := row.get('score') or { panic(err) }
	payload := row.get('payload') or { panic(err) }
	email := row.get('email') or { panic(err) }
	match id {
		string { assert id == '001' }
		else { panic('expected string id') }
	}
	match active {
		bool { assert active }
		else { panic('expected bool active') }
	}
	match score {
		i64 { assert score == 42 }
		else { panic('expected i64 score') }
	}
	match payload {
		[]u8 { assert payload == 'ab'.bytes() }
		else { panic('expected bytes payload') }
	}
	match email {
		storage.NullValue {}
		else { panic('expected null email') }
	}
}

fn test_build_typed_row_accepts_enum_and_json() {
	spec := parse_register_table_spec('items', 'id', 'id:string,status:enum(active|draft),meta:json',
		'-') or { panic(err) }
	row := build_typed_row(spec, 'id=001,status=active,meta={"kind":"alpha","enabled":true}') or {
		panic(err)
	}
	status := row.get('status') or { panic(err) }
	meta := row.get('meta') or { panic(err) }
	match status {
		string { assert status == 'active' }
		else { panic('expected enum string status') }
	}
	match meta {
		string { assert meta.contains('"kind":"alpha"') }
		else { panic('expected json string meta') }
	}
}

fn test_apply_insert_defaults_populates_datetime_columns() {
	spec := parse_register_table_spec('users', 'id', 'id:string,name:string,created_at:datetime:current_timestamp,updated_at:datetime:current_timestamp:auto_update',
		'-') or { panic(err) }
	row := build_typed_row(spec, 'id=u-001,name=Ada') or { panic(err) }
	with_defaults := apply_insert_defaults(spec, row)
	created_at := with_defaults.get('created_at') or { panic(err) }
	updated_at := with_defaults.get('updated_at') or { panic(err) }
	match created_at {
		string {
			_ := time.parse_rfc3339(created_at) or { panic(err) }
		}
		else {
			panic('expected datetime string created_at')
		}
	}
	match updated_at {
		string {
			_ := time.parse_rfc3339(updated_at) or { panic(err) }
		}
		else {
			panic('expected datetime string updated_at')
		}
	}
	auto_filled := detect_auto_filled_columns(spec, row, with_defaults)
	assert auto_filled == ['created_at', 'updated_at']
}

fn test_format_merge_preview() {
	formatted := format_merge_preview(storage.RootHashMergePreview{
		ours_branch:       'main'
		theirs_branch:     'feature'
		base_commit_cid:   'base'
		base_root_cid:     'base-root'
		ours_commit_cid:   'ours'
		ours_root_cid:     'ours-root'
		theirs_commit_cid: 'theirs'
		theirs_root_cid:   'theirs-root'
		conflicts:         0
		changed_keys:      2
		changed_subtrees:  1
		fast_forward:      false
		ours_unchanged:    false
		theirs_unchanged:  false
	})
	assert formatted.contains('ours_branch=main')
	assert formatted.contains('theirs_branch=feature')
	assert formatted.contains('changed_keys=2')
}

fn test_format_merge_report() {
	formatted := format_merge_report(storage.RootHashMergeReport{
		preview:        storage.RootHashMergePreview{
			ours_branch:       'main'
			theirs_branch:     'feature'
			base_commit_cid:   'base'
			base_root_cid:     'base-root'
			ours_commit_cid:   'ours'
			ours_root_cid:     'ours-root'
			theirs_commit_cid: 'theirs'
			theirs_root_cid:   'theirs-root'
			conflicts:         1
			changed_keys:      4
			changed_subtrees:  1
			fast_forward:      false
			ours_unchanged:    false
			theirs_unchanged:  false
		}
		table_stats:    [
			storage.MergeTableStat{
				table_name:       'users'
				row_changes:      2
				index_changes:    1
				conflict_changes: 1
			},
		]
		conflict_keys:  [
			storage.MergeConflictPreview{
				key:        't|users|001'
				table_name: 'users'
				index_name: ''
			},
		]
		conflict_limit: 8
	})
	assert formatted.contains('table=users')
	assert formatted.contains('row_changes=2')
	assert formatted.contains('conflict_key=t|users|001')
}
